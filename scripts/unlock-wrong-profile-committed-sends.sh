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
