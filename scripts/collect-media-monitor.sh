#!/usr/bin/env bash
set -Eeuo pipefail

RG="${RG:-esendit}"
SB_NS="${SB_NS:-esendit}"
MEDIA_APP="${MEDIA_APP:-esendit-media-worker}"
MEDIA_QUEUE="${MEDIA_QUEUE:-esendit-media-jobs}"
SAMPLES="${SAMPLES:-10}"
INTERVAL="${INTERVAL:-30}"

TS="$(date +%Y%m%d-%H%M%S)"
OUT_DIR="media-monitor-$TS"
mkdir -p "$OUT_DIR"

echo "Collecting media worker monitor output into: $OUT_DIR"
echo "Resource group: $RG"
echo "Service Bus namespace: $SB_NS"
echo "Media app: $MEDIA_APP"
echo "Media queue: $MEDIA_QUEUE"
echo "Samples: $SAMPLES"
echo "Interval: ${INTERVAL}s"

# Load .env if available for DATABASE_URL
if [ -f ".env" ]; then
  set -a
  # shellcheck disable=SC1091
  source .env || true
  set +a
fi

run_cmd() {
  local name="$1"
  shift
  echo "---- running: $name ----"
  {
    echo "COMMAND: $*"
    echo "TIME: $(date -Is)"
    echo
    "$@"
  } > "$OUT_DIR/$name.txt" 2>&1 || {
    echo "Command failed: $name" | tee -a "$OUT_DIR/errors.txt"
  }
}

run_sql() {
  local name="$1"
  local query="$2"

  if [ -z "${DATABASE_URL:-}" ]; then
    echo "DATABASE_URL is not set. Skipping SQL: $name" | tee -a "$OUT_DIR/errors.txt"
    return 0
  fi

  if ! command -v psql >/dev/null 2>&1; then
    echo "psql not found. Skipping SQL: $name" | tee -a "$OUT_DIR/errors.txt"
    return 0
  fi

  {
    echo "QUERY: $query"
    echo "TIME: $(date -Is)"
    echo
    psql "$DATABASE_URL" -v ON_ERROR_STOP=1 -P pager=off -A -F $'\t' -c "$query"
  } > "$OUT_DIR/$name.tsv" 2>&1 || {
    echo "SQL failed: $name" | tee -a "$OUT_DIR/errors.txt"
  }
}

# Azure config / KEDA / replica state
run_cmd "00_az_account" az account show -o jsonc

run_cmd "01_media_worker_scale_config" az containerapp show \
  -g "$RG" \
  -n "$MEDIA_APP" \
  --query "properties.template.scale" \
  -o jsonc

run_cmd "02_media_worker_selected_env" az containerapp show \
  -g "$RG" \
  -n "$MEDIA_APP" \
  --query "properties.template.containers[0].env[?name=='APP_MODE' || name=='MEDIA_WORKER_ENABLED' || name=='SERVICE_BUS_ENABLED' || name=='SERVICE_BUS_TRANSPORT' || name=='ESENDIT_QUEUE_PREFIX' || name=='MEDIA_JOB_STALE_RUNNING_MINUTES' || name=='QC_QCLI_TIMEOUT_MINUTES' || name=='MEDIA_WORKER_WATCHDOG_SERVICE_BUS_WAKE' || name=='MEDIA_WORKER_SERVICE_BUS_DB_FALLBACK_ENABLED' || name=='MEDIA_WORKER_SERVICE_BUS_DB_FALLBACK_POLL_MS' || name=='MEDIA_WORKDIR_CLEANUP_ENABLED' || name=='MEDIA_WORKDIR_MIN_FREE_MB']" \
  -o jsonc

run_cmd "03_media_worker_secrets_present" az containerapp secret list \
  -g "$RG" \
  -n "$MEDIA_APP" \
  --query "[?name=='sb-conn' || name=='keda-sb-conn'].name" \
  -o table

run_cmd "04_media_worker_replicas_now" az containerapp replica list \
  -g "$RG" \
  -n "$MEDIA_APP" \
  -o table

run_cmd "05_servicebus_queue_now" az servicebus queue show \
  --resource-group "$RG" \
  --namespace-name "$SB_NS" \
  --name "$MEDIA_QUEUE" \
  --query "countDetails" \
  -o jsonc

# DB one-time snapshots
run_sql "10_media_job_counts" "
SELECT
  type,
  status,
  COUNT(*) AS count
FROM \"MediaJob\"
WHERE type IN ('AUTO_QC', 'PROXY_GEN')
GROUP BY type, status
ORDER BY type, status;
"

run_sql "11_qc_active_jobs" "
SELECT
  mj.status AS job_status,
  c.\"qcStatus\" AS creative_qc_status,
  COUNT(*) AS count
FROM \"MediaJob\" mj
JOIN \"Creative\" c ON c.id = mj.\"creativeId\"
WHERE mj.type = 'AUTO_QC'
  AND mj.status IN ('PENDING', 'RUNNING')
GROUP BY mj.status, c.\"qcStatus\"
ORDER BY mj.status, c.\"qcStatus\";
"

run_sql "12_proxy_coverage" "
SELECT
  c.\"qcStatus\",
  proxy.\"uploadStatus\" AS proxy_status,
  COUNT(*) AS count
FROM \"Creative\" c
LEFT JOIN \"CreativeAsset\" proxy
  ON proxy.\"creativeId\" = c.id
 AND proxy.type = 'PROXY'
GROUP BY c.\"qcStatus\", proxy.\"uploadStatus\"
ORDER BY c.\"qcStatus\", proxy.\"uploadStatus\";
"

run_sql "13_running_jobs_detail" "
SELECT
  mj.id,
  mj.type,
  mj.status,
  mj.attempts,
  mj.\"createdAt\",
  mj.\"startedAt\",
  NOW() - mj.\"startedAt\" AS running_for,
  c.valid,
  c.caption,
  c.\"qcStatus\",
  mj.error
FROM \"MediaJob\" mj
JOIN \"Creative\" c ON c.id = mj.\"creativeId\"
WHERE mj.type IN ('AUTO_QC', 'PROXY_GEN')
  AND mj.status = 'RUNNING'
ORDER BY mj.\"startedAt\" ASC;
"

run_sql "14_pending_jobs_detail" "
SELECT
  mj.id,
  mj.type,
  mj.status,
  mj.attempts,
  mj.\"createdAt\",
  mj.\"runAfter\",
  c.valid,
  c.caption,
  c.\"qcStatus\",
  mj.error
FROM \"MediaJob\" mj
JOIN \"Creative\" c ON c.id = mj.\"creativeId\"
WHERE mj.type IN ('AUTO_QC', 'PROXY_GEN')
  AND mj.status = 'PENDING'
ORDER BY mj.type, mj.\"createdAt\" ASC
LIMIT 200;
"

run_sql "15_failed_jobs_detail" "
SELECT
  mj.id AS job_id,
  mj.type,
  mj.status,
  mj.attempts,
  mj.\"createdAt\",
  mj.\"startedAt\",
  mj.\"endedAt\",
  c.id AS creative_id,
  c.valid,
  c.caption,
  c.\"qcStatus\",
  src.\"uploadStatus\" AS source_status,
  proxy.\"uploadStatus\" AS proxy_status,
  mj.error
FROM \"MediaJob\" mj
JOIN \"Creative\" c ON c.id = mj.\"creativeId\"
LEFT JOIN \"CreativeAsset\" src
  ON src.\"creativeId\" = c.id
 AND src.type = 'SOURCE'
LEFT JOIN \"CreativeAsset\" proxy
  ON proxy.\"creativeId\" = c.id
 AND proxy.type = 'PROXY'
WHERE mj.type IN ('AUTO_QC', 'PROXY_GEN')
  AND mj.status = 'FAILED'
ORDER BY mj.\"endedAt\" DESC
LIMIT 100;
"

run_sql "16_recent_proxy_durations" "
SELECT
  mj.id,
  c.valid,
  c.caption,
  ROUND(EXTRACT(EPOCH FROM (mj.\"endedAt\" - mj.\"startedAt\"))) AS processing_seconds,
  ROUND(EXTRACT(EPOCH FROM (mj.\"startedAt\" - mj.\"createdAt\"))) AS waiting_seconds,
  src.\"sizeBytes\" / 1024 / 1024 AS source_mb,
  proxy.\"sizeBytes\" / 1024 / 1024 AS proxy_mb,
  mj.error
FROM \"MediaJob\" mj
JOIN \"Creative\" c ON c.id = mj.\"creativeId\"
LEFT JOIN \"CreativeAsset\" src
  ON src.\"creativeId\" = c.id
 AND src.type = 'SOURCE'
LEFT JOIN \"CreativeAsset\" proxy
  ON proxy.\"creativeId\" = c.id
 AND proxy.type = 'PROXY'
WHERE mj.type = 'PROXY_GEN'
  AND mj.status = 'SUCCEEDED'
ORDER BY mj.\"endedAt\" DESC
LIMIT 50;
"

run_sql "17_passed_missing_proxy" "
SELECT
  c.id AS creative_id,
  c.\"accountId\",
  c.\"projectId\",
  c.valid,
  c.caption,
  c.\"qcStatus\",
  mj.id AS proxy_job_id,
  mj.status AS proxy_job_status,
  mj.attempts AS proxy_attempts,
  mj.error AS proxy_error
FROM \"Creative\" c
LEFT JOIN \"CreativeAsset\" proxy
  ON proxy.\"creativeId\" = c.id
 AND proxy.type = 'PROXY'
LEFT JOIN \"MediaJob\" mj
  ON mj.\"creativeId\" = c.id
 AND mj.type = 'PROXY_GEN'
WHERE c.\"qcStatus\" = 'PASSED'
  AND proxy.id IS NULL
ORDER BY c.\"updatedAt\" DESC
LIMIT 100;
"

# Time-series monitoring during upload
echo "Starting live samples..." | tee "$OUT_DIR/20_live_samples.txt"

for i in $(seq 1 "$SAMPLES"); do
  {
    echo
    echo "================ SAMPLE $i / $SAMPLES ================"
    echo "TIME: $(date -Is)"
    echo

    echo "---- Service Bus countDetails ----"
    az servicebus queue show \
      --resource-group "$RG" \
      --namespace-name "$SB_NS" \
      --name "$MEDIA_QUEUE" \
      --query "countDetails" \
      -o jsonc || true

    echo
    echo "---- ACA replicas ----"
    az containerapp replica list \
      -g "$RG" \
      -n "$MEDIA_APP" \
      -o table || true

    echo
    echo "---- DB MediaJob counts ----"
    if [ -n "${DATABASE_URL:-}" ] && command -v psql >/dev/null 2>&1; then
      psql "$DATABASE_URL" -v ON_ERROR_STOP=1 -P pager=off -A -F $'\t' -c "
        SELECT type, status, COUNT(*) AS count
        FROM \"MediaJob\"
        WHERE type IN ('AUTO_QC', 'PROXY_GEN')
        GROUP BY type, status
        ORDER BY type, status;
      " || true
    else
      echo "DATABASE_URL/psql not available"
    fi

    echo
    echo "---- DB running jobs ----"
    if [ -n "${DATABASE_URL:-}" ] && command -v psql >/dev/null 2>&1; then
      psql "$DATABASE_URL" -v ON_ERROR_STOP=1 -P pager=off -A -F $'\t' -c "
        SELECT
          mj.type,
          mj.status,
          mj.attempts,
          mj.\"startedAt\",
          NOW() - mj.\"startedAt\" AS running_for,
          c.valid,
          c.\"qcStatus\",
          mj.error
        FROM \"MediaJob\" mj
        JOIN \"Creative\" c ON c.id = mj.\"creativeId\"
        WHERE mj.type IN ('AUTO_QC', 'PROXY_GEN')
          AND mj.status = 'RUNNING'
        ORDER BY mj.\"startedAt\" ASC;
      " || true
    else
      echo "DATABASE_URL/psql not available"
    fi

  } >> "$OUT_DIR/20_live_samples.txt" 2>&1

  if [ "$i" -lt "$SAMPLES" ]; then
    sleep "$INTERVAL"
  fi
done

# Logs after samples
run_cmd "30_media_worker_system_logs_tail" az containerapp logs show \
  -g "$RG" \
  -n "$MEDIA_APP" \
  --type system \
  --tail 400

run_cmd "31_media_worker_console_logs_tail" az containerapp logs show \
  -g "$RG" \
  -n "$MEDIA_APP" \
  --tail 500

# Filter important log lines
{
  echo "TIME: $(date -Is)"
  echo
  echo "Important filtered log lines:"
  echo
  cat "$OUT_DIR/30_media_worker_system_logs_tail.txt" "$OUT_DIR/31_media_worker_console_logs_tail.txt" 2>/dev/null \
    | grep -Ei "KEDA|Scaler|Failed|Unauthorized|FailedGetExternalMetric|FailedComputeMetricsReplicas|Manage,EntityRead|ENOSPC|ENOENT|qcli|timeout|deadletter|proxy-finally|auto-qc-finally|Service Bus|AggregateError|no space left|no such file" || true
} > "$OUT_DIR/32_filtered_important_logs.txt"

# Final snapshot
run_cmd "40_servicebus_queue_final" az servicebus queue show \
  --resource-group "$RG" \
  --namespace-name "$SB_NS" \
  --name "$MEDIA_QUEUE" \
  --query "countDetails" \
  -o jsonc

run_cmd "41_media_worker_replicas_final" az containerapp replica list \
  -g "$RG" \
  -n "$MEDIA_APP" \
  -o table

run_sql "42_media_job_counts_final" "
SELECT
  type,
  status,
  COUNT(*) AS count
FROM \"MediaJob\"
WHERE type IN ('AUTO_QC', 'PROXY_GEN')
GROUP BY type, status
ORDER BY type, status;
"

run_sql "43_proxy_coverage_final" "
SELECT
  c.\"qcStatus\",
  proxy.\"uploadStatus\" AS proxy_status,
  COUNT(*) AS count
FROM \"Creative\" c
LEFT JOIN \"CreativeAsset\" proxy
  ON proxy.\"creativeId\" = c.id
 AND proxy.type = 'PROXY'
GROUP BY c.\"qcStatus\", proxy.\"uploadStatus\"
ORDER BY c.\"qcStatus\", proxy.\"uploadStatus\";
"

tar -czf "$OUT_DIR.tar.gz" "$OUT_DIR"

echo
echo "Done."
echo "Folder: $OUT_DIR"
echo "Archive: $OUT_DIR.tar.gz"
echo
echo "Share this archive/output back for analysis:"
echo "$OUT_DIR.tar.gz"
