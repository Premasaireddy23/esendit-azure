Below is a reusable **runbook + script** for this exact situation:

> Wrong delivery profile was selected, send got committed/locked in Planner + Commit, delivery task failed, and you want to remove only those failed committed rows so client can correct profile and commit again.

---

# Runbook: Unlock wrong-profile committed sends

## When to use this

Use this only when:

```txt
DeliveryTask is FAILED
Failure is caused by wrong delivery profile / wrong route
Client needs to re-commit same creative/channel from Planner + Commit
You want to unlock those committed PlanLine rows
```

Do **not** use this for normal FTP/SFTP/network failures.

---

# Script: `unlock-wrong-profile-committed-sends.sh`

Create file:

```bash
nano unlock-wrong-profile-committed-sends.sh
```

Paste this:

```bash
#!/usr/bin/env bash
set -euo pipefail

# -------------------------------------------------------------------
# eSendIT - Unlock wrong-profile committed sends
#
# Purpose:
#   Removes selected FAILED DeliveryTask rows and their committed
#   PlanLine rows so Planner + Commit can be committed again.
#
# Safety:
#   - DRY_RUN=true by default
#   - Backs up DeliveryTask and PlanLine rows before deletion
#   - Deletes only FAILED delivery tasks matching the error pattern
#   - Does NOT delete PlanningEntry
#   - Does NOT touch QC, presets, transcode, tracking success rows, or files
#
# Usage:
#   export DATABASE_URL="postgresql://..."
#   ./unlock-wrong-profile-committed-sends.sh /tmp/final_failed_delivery_ids.txt
#
# Apply:
#   DRY_RUN=false ./unlock-wrong-profile-committed-sends.sh /tmp/final_failed_delivery_ids.txt
# -------------------------------------------------------------------

IDS_FILE="${1:-/tmp/final_failed_delivery_ids.txt}"
DRY_RUN="${DRY_RUN:-true}"

# Match only expected preset-wait/wrong-profile type failures.
# You can override this if needed:
# ERROR_PATTERN='Waiting for preset output XDCAMHD422MXF%' DRY_RUN=false ./script file
ERROR_PATTERN="${ERROR_PATTERN:-Waiting for preset output%}"

# Optional safety: require STATIC_VM route in transcript.
# Set REQUIRE_STATIC_VM=false if the wrong profile was not STATIC_VM.
REQUIRE_STATIC_VM="${REQUIRE_STATIC_VM:-true}"

RUN_ID="$(date +%Y%m%d_%H%M%S)"
DT_BACKUP_TABLE="DeliveryTask_backup_wrong_profile_${RUN_ID}"
PL_BACKUP_TABLE="PlanLine_backup_wrong_profile_${RUN_ID}"

if [[ -z "${DATABASE_URL:-}" ]]; then
  echo "ERROR: DATABASE_URL is not set"
  exit 1
fi

if [[ ! -f "$IDS_FILE" ]]; then
  echo "ERROR: IDs file not found: $IDS_FILE"
  exit 1
fi

if [[ ! -s "$IDS_FILE" ]]; then
  echo "ERROR: IDs file is empty: $IDS_FILE"
  exit 1
fi

BAD_IDS=$(grep -vE '^[0-9a-fA-F-]{36}$' "$IDS_FILE" || true)
if [[ -n "$BAD_IDS" ]]; then
  echo "ERROR: IDs file contains invalid UUID values:"
  echo "$BAD_IDS"
  exit 1
fi

echo "============================================================"
echo "eSendIT unlock wrong-profile committed sends"
echo "============================================================"
echo "IDs file           : $IDS_FILE"
echo "DRY_RUN            : $DRY_RUN"
echo "ERROR_PATTERN      : $ERROR_PATTERN"
echo "REQUIRE_STATIC_VM  : $REQUIRE_STATIC_VM"
echo "Delivery backup    : $DT_BACKUP_TABLE"
echo "PlanLine backup    : $PL_BACKUP_TABLE"
echo "============================================================"
echo ""

if [[ "$DRY_RUN" == "true" ]]; then
  echo "Running DRY RUN only. No data will be changed."
  echo ""

  psql "$DATABASE_URL" -v ON_ERROR_STOP=1 \
    -v ids_file="$IDS_FILE" \
    -v error_pattern="$ERROR_PATTERN" \
    -v require_static_vm="$REQUIRE_STATIC_VM" <<'SQL'

CREATE TEMP TABLE target_ids (
  id uuid PRIMARY KEY
);

\copy target_ids(id) FROM :'ids_file'

WITH candidate AS (
  SELECT
    dt.id AS delivery_task_id,
    dt.status,
    dt.attempts,
    dt."lastError",
    dt."planLineId",
    pl."creativeId",
    pl."channelId",
    pv."projectId",
    pv.version AS plan_version,
    dt.transcript->'deliveryRouting' AS delivery_routing,
    dt.transcript->'selectedPreset' AS selected_preset
  FROM "DeliveryTask" dt
  JOIN target_ids t ON t.id = dt.id
  LEFT JOIN "PlanLine" pl ON pl.id = dt."planLineId"
  LEFT JOIN "PlanVersion" pv ON pv.id = pl."planVersionId"
),
eligible AS (
  SELECT *
  FROM candidate
  WHERE status = 'FAILED'
    AND "lastError" ILIKE :'error_pattern'
    AND (
      :'require_static_vm' <> 'true'
      OR delivery_routing->>'preferredRoute' = 'STATIC_VM'
      OR delivery_routing->>'mainRoute' = 'STATIC_VM'
    )
)
SELECT
  'INPUT_IDS' AS check_name,
  COUNT(*) AS count
FROM target_ids

UNION ALL

SELECT
  'FOUND_DELIVERY_TASKS' AS check_name,
  COUNT(*) AS count
FROM candidate

UNION ALL

SELECT
  'ELIGIBLE_TO_UNLOCK' AS check_name,
  COUNT(*) AS count
FROM eligible

UNION ALL

SELECT
  'DISTINCT_PLAN_LINES_TO_REMOVE' AS check_name,
  COUNT(DISTINCT "planLineId") AS count
FROM eligible
WHERE "planLineId" IS NOT NULL;

SELECT
  delivery_task_id,
  status,
  attempts,
  "lastError",
  "planLineId",
  "creativeId",
  "channelId",
  "projectId",
  plan_version,
  delivery_routing,
  selected_preset
FROM eligible
ORDER BY delivery_task_id;

SELECT
  'NOT_ELIGIBLE_OR_NOT_FOUND' AS section,
  c.*
FROM candidate c
WHERE NOT (
  c.status = 'FAILED'
  AND c."lastError" ILIKE :'error_pattern'
  AND (
    :'require_static_vm' <> 'true'
    OR c.delivery_routing->>'preferredRoute' = 'STATIC_VM'
    OR c.delivery_routing->>'mainRoute' = 'STATIC_VM'
  )
)
ORDER BY c.delivery_task_id;

SQL

  echo ""
  echo "DRY RUN complete. If output looks correct, run:"
  echo ""
  echo "DRY_RUN=false $0 $IDS_FILE"
  echo ""
  exit 0
fi

echo "APPLY MODE. This will backup and delete eligible rows."
echo "Press Ctrl+C now if this is not intended."
sleep 5

psql "$DATABASE_URL" -v ON_ERROR_STOP=1 \
  -v ids_file="$IDS_FILE" \
  -v error_pattern="$ERROR_PATTERN" \
  -v require_static_vm="$REQUIRE_STATIC_VM" \
  -v dt_backup_table="$DT_BACKUP_TABLE" \
  -v pl_backup_table="$PL_BACKUP_TABLE" <<'SQL'

BEGIN;

CREATE TEMP TABLE target_ids (
  id uuid PRIMARY KEY
);

\copy target_ids(id) FROM :'ids_file'

CREATE TEMP TABLE eligible_tasks AS
SELECT
  dt.*
FROM "DeliveryTask" dt
JOIN target_ids t ON t.id = dt.id
WHERE dt.status = 'FAILED'
  AND dt."lastError" ILIKE :'error_pattern'
  AND (
    :'require_static_vm' <> 'true'
    OR dt.transcript->'deliveryRouting'->>'preferredRoute' = 'STATIC_VM'
    OR dt.transcript->'deliveryRouting'->>'mainRoute' = 'STATIC_VM'
  );

DO $$
DECLARE
  input_count int;
  eligible_count int;
BEGIN
  SELECT COUNT(*) INTO input_count FROM target_ids;
  SELECT COUNT(*) INTO eligible_count FROM eligible_tasks;

  IF eligible_count = 0 THEN
    RAISE EXCEPTION 'No eligible rows found. Nothing deleted.';
  END IF;

  IF input_count <> eligible_count THEN
    RAISE EXCEPTION 'Safety stop: input IDs (%) != eligible rows (%). Run DRY_RUN=true and inspect mismatches.', input_count, eligible_count;
  END IF;
END $$;

CREATE TEMP TABLE eligible_plan_lines AS
SELECT DISTINCT pl.*
FROM "PlanLine" pl
JOIN eligible_tasks et ON et."planLineId" = pl.id
WHERE et."planLineId" IS NOT NULL;

CREATE TABLE :"dt_backup_table" AS
SELECT * FROM eligible_tasks;

CREATE TABLE :"pl_backup_table" AS
SELECT * FROM eligible_plan_lines;

-- Delete only selected failed delivery tasks.
DELETE FROM "DeliveryTask" dt
USING eligible_tasks et
WHERE dt.id = et.id
  AND dt.status = 'FAILED'
  AND dt."lastError" ILIKE :'error_pattern';

-- Delete only the matching committed PlanLine rows.
-- Extra safety: delete a PlanLine only if no other DeliveryTask still references it.
DELETE FROM "PlanLine" pl
USING eligible_plan_lines epl
WHERE pl.id = epl.id
  AND NOT EXISTS (
    SELECT 1
    FROM "DeliveryTask" dt
    WHERE dt."planLineId" = pl.id
  );

COMMIT;

SQL

echo ""
echo "Unlock completed."
echo "Backup tables created:"
echo "  $DT_BACKUP_TABLE"
echo "  $PL_BACKUP_TABLE"
echo ""
echo "Run verification queries below."
```

Make executable:

```bash
chmod +x unlock-wrong-profile-committed-sends.sh
```

---

# How to use

## 1. Create task ID file

Example for your case:

```bash
cat > /tmp/final_failed_delivery_ids.txt <<'EOF'
ee46df7f-340f-4fb2-9414-a0dd622e88e0
75f5fdb5-679c-43d5-bfc7-000924532c68
ea122dc2-b457-46ec-84f0-ca60b88222b3
def0fb5f-f9e9-4c02-8428-061b91885aa5
88da62e6-3b76-4a4a-b648-06672e1e6795
74dcdb63-416d-4fa6-9101-7b925045b641
ccf8deaa-3f54-4c9f-b98b-e1dfb08d658f
EOF
```

---

## 2. Dry run first

```bash
./unlock-wrong-profile-committed-sends.sh /tmp/final_failed_delivery_ids.txt
```

Check output carefully.

It should show:

```txt
INPUT_IDS = 7
FOUND_DELIVERY_TASKS = 7
ELIGIBLE_TO_UNLOCK = 7
DISTINCT_PLAN_LINES_TO_REMOVE = 7
```

If eligible count is not same as input count, do not apply.

---

## 3. Apply

```bash
DRY_RUN=false ./unlock-wrong-profile-committed-sends.sh /tmp/final_failed_delivery_ids.txt
```

---

# Verification after apply

## 1. Confirm failed DeliveryTask rows removed

```sql
SELECT COUNT(*) AS remaining_tasks
FROM "DeliveryTask"
WHERE id IN (
  'ee46df7f-340f-4fb2-9414-a0dd622e88e0'::uuid,
  '75f5fdb5-679c-43d5-bfc7-000924532c68'::uuid,
  'ea122dc2-b457-46ec-84f0-ca60b88222b3'::uuid,
  'def0fb5f-f9e9-4c02-8428-061b91885aa5'::uuid,
  '88da62e6-3b76-4a4a-b648-06672e1e6795'::uuid,
  '74dcdb63-416d-4fa6-9101-7b925045b641'::uuid,
  'ccf8deaa-3f54-4c9f-b98b-e1dfb08d658f'::uuid
);
```

Expected:

```txt
0
```

---

## 2. Confirm failed count

```sql
SELECT status, COUNT(*)
FROM "DeliveryTask"
GROUP BY status
ORDER BY status;
```

Expected:

```txt
SUCCESS 1164
PAUSED 7
```

`FAILED` should be gone for those 7.

---

## 3. Client flow after cleanup

```txt
1. Correct the wrong delivery profile in Channel/Destination.
2. Open Planner + Commit.
3. Those 7 creative/channel rows should be available again.
4. Client commits again.
5. Send again.
```

---

# Important notes

This script does **not** delete:

```txt
PlanningEntry
Creative
QC result
Preset output
Transcode output
Tracking success rows
Files/blobs
```

It only removes:

```txt
FAILED DeliveryTask rows listed in the ID file
Their matching committed PlanLine rows
```

So it is safe for this wrong-profile recovery case, but still always run dry-run first.
