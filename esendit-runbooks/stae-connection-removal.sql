BEGIN;

UPDATE "MediaJob" mj
SET
  status = 'PENDING',
  "runAfter" = NOW(),
  "endedAt" = NOW(),
  error = 'Reset stale RUNNING AUTO_QC job; no active qcli process found after timeout'
FROM "Creative" c
WHERE c.id = mj."creativeId"
  AND mj.type = 'AUTO_QC'
  AND mj.id = 'abc04e56-7ff1-46da-b4a3-fdefa0916d94'
  AND mj.status = 'RUNNING'
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
  AND mj.id = 'abc04e56-7ff1-46da-b4a3-fdefa0916d94'
  AND mj.status = 'PENDING'
  AND c."qcStatus" = 'IN_PROGRESS'
RETURNING
  c.id,
  c.valid,
  c.caption,
  c."qcStatus";

COMMIT;