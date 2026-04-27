Below is a **QC Queue / Media Worker incident runbook** you can keep.

# eSendIT QC Queue Stuck / Re-QC / Stale RUNNING Runbook

## Problem identifier

Use this incident name:

```text
QC-MEDIA-WORKER-STUCK-QUEUE / STALE-AUTO-QC-JOBS
```

## Main symptoms

```text
QC jobs stay Queued for long time
QC jobs stay In Progress for long time
Already PASSED creatives start QC again
Service Bus queue shows 0 but UI shows queued
Service Bus queue has messages but worker logs are quiet
Worker logs show AggregateError
DB shows RUNNING jobs but no qcli/mediainfo/ffmpeg process
```

---

# 1. First checks

## Check Service Bus queue

```bash
az servicebus queue show \
  --resource-group esendit \
  --namespace-name esendit \
  --name esendit-media-jobs \
  --query "countDetails" \
  -o table
```

## Check media worker env

```bash
az containerapp show \
  -g esendit \
  -n esendit-media-worker \
  --query "properties.template.containers[0].env[?name=='APP_MODE' || name=='MEDIA_WORKER_ENABLED' || name=='SERVICE_BUS_ENABLED' || name=='SERVICE_BUS_TRANSPORT' || name=='ESENDIT_QUEUE_PREFIX' || name=='MEDIA_WORKER_WATCHDOG_SERVICE_BUS_WAKE' || name=='MEDIA_WORKER_SERVICE_BUS_DB_FALLBACK_ENABLED' || name=='QC_QCLI_TIMEOUT_MINUTES' || name=='MEDIA_JOB_STALE_RUNNING_MINUTES']" \
  -o table
```

Expected stable config:

```text
APP_MODE=worker
MEDIA_WORKER_ENABLED=true
SERVICE_BUS_ENABLED=true
SERVICE_BUS_TRANSPORT=websocket
ESENDIT_QUEUE_PREFIX=esendit
MEDIA_WORKER_WATCHDOG_SERVICE_BUS_WAKE=false
MEDIA_WORKER_SERVICE_BUS_DB_FALLBACK_ENABLED=true
QC_QCLI_TIMEOUT_MINUTES=20
MEDIA_JOB_STALE_RUNNING_MINUTES=30
```

## Check logs

```bash
az containerapp logs show \
  -g esendit \
  -n esendit-media-worker \
  --tail 150
```

Good logs:

```text
Using Azure Service Bus WebSocket transport
Media worker started (service bus: esendit-media-jobs)
Media worker Service Bus DB fallback polling enabled every 30000ms
```

---

# 2. DB health check

Run this in DB:

```sql
SELECT
  mj.status AS job_status,
  c."qcStatus" AS creative_qc_status,
  COUNT(*) AS count
FROM "MediaJob" mj
JOIN "Creative" c ON c.id = mj."creativeId"
WHERE mj.type = 'AUTO_QC'
  AND mj.status IN ('PENDING', 'RUNNING')
GROUP BY mj.status, c."qcStatus"
ORDER BY mj.status, c."qcStatus";
```

## Healthy states

```text
0 rows
```

or temporarily:

```text
PENDING | NOT_STARTED
RUNNING | IN_PROGRESS
```

## Bad states

```text
PENDING | PASSED        -- duplicate stale job
RUNNING | PASSED        -- dangerous, passed creative may re-QC
PENDING | IN_PROGRESS   -- fake in-progress
RUNNING | NOT_STARTED   -- inconsistent stale state
RUNNING | IN_PROGRESS running for 20+ min with no qcli process
```

---

# 3. If already PASSED creatives are getting QC again

## Stop media worker first

```bash
az containerapp update \
  -g esendit \
  -n esendit-media-worker \
  --set-env-vars MEDIA_WORKER_ENABLED=false
```

## Cancel duplicate active jobs for PASSED creatives only

```sql
BEGIN;

UPDATE "MediaJob" mj
SET
  status = 'FAILED',
  "endedAt" = NOW(),
  error = 'Cancelled stale duplicate AUTO_QC job because creative is already PASSED'
FROM "Creative" c
WHERE c.id = mj."creativeId"
  AND mj.type = 'AUTO_QC'
  AND mj.status IN ('PENDING', 'RUNNING')
  AND c."qcStatus" = 'PASSED'
RETURNING
  mj.id,
  mj.status,
  mj.attempts,
  c.valid,
  c.caption,
  c."qcStatus";

COMMIT;
```

This is safe because it does **not** change the QC report/result. It only cancels the stale duplicate job.

---

# 4. If UI shows IN_PROGRESS but DB job is PENDING

This is fake running state.

```sql
BEGIN;

UPDATE "Creative" c
SET
  "qcStatus" = 'NOT_STARTED',
  "autoQcStartedAt" = NULL
FROM "MediaJob" mj
WHERE mj."creativeId" = c.id
  AND mj.type = 'AUTO_QC'
  AND mj.status = 'PENDING'
  AND c."qcStatus" = 'IN_PROGRESS'
RETURNING
  c.id,
  c.valid,
  c.caption,
  c."qcStatus";

COMMIT;
```

---

# 5. If DB shows RUNNING but no qcli/mediainfo/ffmpeg process

Check process:

```bash
az containerapp exec \
  -g esendit \
  -n esendit-media-worker \
  --command "sh -lc 'ps -eo pid,etime,pcpu,pmem,args | grep -E \"qcli|mediainfo|ffmpeg|node\" | grep -v grep || true'"
```

If only `node dist/main.js` is shown and DB still has `RUNNING`, those jobs are stale.

## Stop worker first

```bash
az containerapp update \
  -g esendit \
  -n esendit-media-worker \
  --set-env-vars MEDIA_WORKER_ENABLED=false
```

## Reset stale RUNNING jobs older than 20 minutes

```sql
BEGIN;

UPDATE "MediaJob" mj
SET
  status = 'PENDING',
  "runAfter" = NOW(),
  "endedAt" = NOW(),
  error = 'Reset stale RUNNING AUTO_QC job; no active qcli process found'
FROM "Creative" c
WHERE c.id = mj."creativeId"
  AND mj.type = 'AUTO_QC'
  AND mj.status = 'RUNNING'
  AND mj."startedAt" < NOW() - INTERVAL '20 minutes'
RETURNING
  mj.id,
  mj.status,
  mj.attempts,
  c.valid,
  c.caption,
  c."qcStatus";

UPDATE "Creative" c
SET
  "qcStatus" = 'NOT_STARTED',
  "autoQcStartedAt" = NULL
FROM "MediaJob" mj
WHERE mj."creativeId" = c.id
  AND mj.type = 'AUTO_QC'
  AND mj.status = 'PENDING'
  AND c."qcStatus" = 'IN_PROGRESS'
  AND mj.error = 'Reset stale RUNNING AUTO_QC job; no active qcli process found'
RETURNING
  c.id,
  c.valid,
  c.caption,
  c."qcStatus";

COMMIT;
```

Then restart media worker:

```bash
az containerapp update \
  -g esendit \
  -n esendit-media-worker \
  --set-env-vars SERVICE_BUS_ENABLED=true SERVICE_BUS_TRANSPORT=websocket APP_MODE=worker MEDIA_WORKER_ENABLED=true ESENDIT_QUEUE_PREFIX=esendit MEDIA_JOB_STALE_RUNNING_MINUTES=30 QC_QCLI_TIMEOUT_MINUTES=20 MEDIA_WORKER_WATCHDOG_SERVICE_BUS_WAKE=false MEDIA_WORKER_SERVICE_BUS_DB_FALLBACK_ENABLED=true MEDIA_WORKER_SERVICE_BUS_DB_FALLBACK_POLL_MS=30000 \
  --min-replicas 1 \
  --max-replicas 5
```

---

# 6. If qcli is actually stuck

If process shows same `qcli` running more than 20 minutes:

```bash
az containerapp exec \
  -g esendit \
  -n esendit-media-worker \
  --command "sh -lc 'ps -eo pid,etime,pcpu,pmem,args | grep -E \"qcli|mediainfo|ffmpeg\" | grep -v grep || true'"
```

Kill only the stuck qcli PID:

```bash
kill -TERM <pid>
sleep 10
kill -KILL <pid> 2>/dev/null || true
```

Then reset that specific job from DB using the stale RUNNING reset query above.

---

# 7. If Service Bus AggregateError appears

If QC is still passing and logs show:

```text
Failed to wake media job ... AggregateError
```

Check if watchdog wake is disabled:

```bash
az containerapp show \
  -g esendit \
  -n esendit-media-worker \
  --query "properties.template.containers[0].env[?name=='MEDIA_WORKER_WATCHDOG_SERVICE_BUS_WAKE' || name=='SERVICE_BUS_TRANSPORT']" \
  -o table
```

Expected:

```text
MEDIA_WORKER_WATCHDOG_SERVICE_BUS_WAKE=false
SERVICE_BUS_TRANSPORT=websocket
```

If not set:

```bash
az containerapp update \
  -g esendit \
  -n esendit-media-worker \
  --set-env-vars MEDIA_WORKER_WATCHDOG_SERVICE_BUS_WAKE=false SERVICE_BUS_TRANSPORT=websocket
```

---

# 8. Temporary safe fallback if Service Bus breaks again

Switch only media worker to DB polling mode:

```bash
az containerapp update \
  -g esendit \
  -n esendit-media-worker \
  --set-env-vars SERVICE_BUS_ENABLED=false APP_MODE=worker MEDIA_WORKER_ENABLED=true ESENDIT_QUEUE_PREFIX=esendit MEDIA_JOB_STALE_RUNNING_MINUTES=30 QC_QCLI_TIMEOUT_MINUTES=20 \
  --min-replicas 1 \
  --max-replicas 1
```

Expected log:

```text
Media worker started (polling every 2s)
```

Use this only as emergency fallback.

---

# 9. Scaling rule

For max 5 replicas and 1 replica per 25 queued QC jobs:

```bash
az containerapp update \
  -g esendit \
  -n esendit-media-worker \
  --min-replicas 1 \
  --max-replicas 5 \
  --scale-rule-name media-servicebus-qc \
  --scale-rule-type azure-servicebus \
  --scale-rule-metadata queueName=esendit-media-jobs messageCount=25 connectionFromEnv=SERVICE_BUS_CONNECTION_STRING
```

Replica behavior:

```text
0-25 messages    = 1 replica
26-50 messages   = 2 replicas
51-75 messages   = 3 replicas
76-100 messages  = 4 replicas
101+ messages    = 5 replicas max
```

Important rule:

```text
Do not manually scale down while RUNNING jobs exist.
Let ACA scale down naturally.
```

---

# 10. Final stable configuration

## Backend API

```text
APP_MODE=api
SERVICE_BUS_ENABLED=true
SERVICE_BUS_TRANSPORT=websocket
```

## Media worker

```text
APP_MODE=worker
MEDIA_WORKER_ENABLED=true
SERVICE_BUS_ENABLED=true
SERVICE_BUS_TRANSPORT=websocket
ESENDIT_QUEUE_PREFIX=esendit
MEDIA_WORKER_WATCHDOG_SERVICE_BUS_WAKE=false
MEDIA_WORKER_SERVICE_BUS_DB_FALLBACK_ENABLED=true
MEDIA_WORKER_SERVICE_BUS_DB_FALLBACK_POLL_MS=30000
MEDIA_JOB_STALE_RUNNING_MINUTES=30
QC_QCLI_TIMEOUT_MINUTES=20
min replicas=1
max replicas=5
```

## Static VM delivery worker

Also add:

```text
SERVICE_BUS_TRANSPORT=websocket
```

because it uses the same backend image and Azure Service Bus.

---

# 11. Do not do these

```text
Do not purge Service Bus queue unless confirmed safe.
Do not delete MediaJob rows directly.
Do not update PASSED creatives back to NOT_STARTED.
Do not manually scale down while jobs are RUNNING.
Do not disable QC checks/report logic.
Do not change qcli/MediaInfo output fields.
```

This is the safest order during incident:

```text
1. Stop media worker if passed jobs are re-QC’ing
2. Check DB status summary
3. Cancel stale PASSED duplicate jobs
4. Reset fake IN_PROGRESS / stale RUNNING jobs
5. Restart media worker with stable env
6. Verify DB returns 0 PENDING/RUNNING rows
```
