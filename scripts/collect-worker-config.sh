#!/usr/bin/env bash
set -Eeuo pipefail

RG="${RG:-esendit}"
SB_NS="${SB_NS:-esendit}"

APPS=(
  "backend"
  "esendit-media-worker"
  "esendit-preset-worker"
  "esendit-bulk-worker"
  "esendit-delivery-worker"
)

QUEUES=(
  "esendit-media-jobs"
  "esendit-preset-jobs"
  "esendit-bulk-jobs"
  "esendit-delivery-jobs"
  "esendit-delivery-jobs-static-vm"
  "esendit-delivery-connection-check-results"
)

TS="$(date +%Y%m%d-%H%M%S)"
OUT_DIR="worker-config-$TS"
mkdir -p "$OUT_DIR"

echo "Collecting worker config into: $OUT_DIR"
echo "Resource group: $RG"
echo "Service Bus namespace: $SB_NS"

run_cmd() {
  local name="$1"
  shift

  {
    echo "TIME: $(date -Is)"
    echo "COMMAND: $*"
    echo
    "$@"
  } > "$OUT_DIR/$name.txt" 2>&1 || {
    echo "FAILED: $name" | tee -a "$OUT_DIR/errors.txt"
  }
}

sanitize_env_json() {
  python3 - "$1" "$2" <<'PY'
import json, re, sys

src = sys.argv[1]
dst = sys.argv[2]

sensitive = re.compile(
    r"(SECRET|PASSWORD|TOKEN|KEY|CONNECTION|CONN|DATABASE_URL|DB_URL|SAS|CREDENTIAL|PRIVATE|CERT|CLIENT_SECRET)",
    re.I,
)

try:
    data = json.load(open(src))
except Exception as e:
    open(dst, "w").write(f"Failed to parse JSON: {e}\n")
    sys.exit(0)

envs = (
    data.get("properties", {})
        .get("template", {})
        .get("containers", [{}])[0]
        .get("env", [])
)

rows = []
for e in envs:
    name = e.get("name")
    value = e.get("value")
    secret_ref = e.get("secretRef")

    if secret_ref:
        shown = f"<secretRef:{secret_ref}>"
    elif name and sensitive.search(name):
        shown = "<redacted>"
    else:
        shown = value

    rows.append({
        "name": name,
        "value": shown,
        "secretRef": secret_ref,
    })

rows = sorted(rows, key=lambda x: x.get("name") or "")

with open(dst, "w") as f:
    for r in rows:
        f.write(f"{r['name']}\t{r['value']}\n")
PY
}

run_cmd "00_az_account" az account show -o jsonc

echo "Collecting Service Bus queues..."
for q in "${QUEUES[@]}"; do
  safe_q="${q//[^a-zA-Z0-9_-]/_}"

  run_cmd "queue_${safe_q}_details" az servicebus queue show \
    --resource-group "$RG" \
    --namespace-name "$SB_NS" \
    --name "$q" \
    --query "{
      name:name,
      countDetails:countDetails,
      maxDeliveryCount:maxDeliveryCount,
      lockDuration:lockDuration,
      defaultMessageTimeToLive:defaultMessageTimeToLive,
      deadLetteringOnMessageExpiration:deadLetteringOnMessageExpiration,
      requiresDuplicateDetection:requiresDuplicateDetection,
      duplicateDetectionHistoryTimeWindow:duplicateDetectionHistoryTimeWindow
    }" \
    -o jsonc
done

echo "Collecting Container App configs..."
for app in "${APPS[@]}"; do
  safe_app="${app//[^a-zA-Z0-9_-]/_}"
  app_dir="$OUT_DIR/$safe_app"
  mkdir -p "$app_dir"

  echo "App: $app"

  az containerapp show \
    -g "$RG" \
    -n "$app" \
    -o json > "$app_dir/full-show-raw.json" 2>"$app_dir/full-show-error.txt" || true

  sanitize_env_json "$app_dir/full-show-raw.json" "$app_dir/env-sanitized.tsv"

  {
    echo "APP: $app"
    echo "TIME: $(date -Is)"
    echo
    echo "==== TERMINATION GRACE ===="
    az containerapp show \
      -g "$RG" \
      -n "$app" \
      --query "properties.template.terminationGracePeriodSeconds" \
      -o tsv || true

    echo
    echo "==== SCALE CONFIG ===="
    az containerapp show \
      -g "$RG" \
      -n "$app" \
      --query "properties.template.scale" \
      -o jsonc || true

    echo
    echo "==== IMAGE ===="
    az containerapp show \
      -g "$RG" \
      -n "$app" \
      --query "properties.template.containers[0].image" \
      -o tsv || true

    echo
    echo "==== ENV SANITIZED ===="
    cat "$app_dir/env-sanitized.tsv" || true

    echo
    echo "==== SECRET NAMES ONLY ===="
    az containerapp secret list \
      -g "$RG" \
      -n "$app" \
      --query "[].name" \
      -o table || true

    echo
    echo "==== REPLICAS ===="
    az containerapp replica list \
      -g "$RG" \
      -n "$app" \
      -o table || true

    echo
    echo "==== REVISIONS ===="
    az containerapp revision list \
      -g "$RG" \
      -n "$app" \
      --query "[].{
        name:name,
        active:properties.active,
        trafficWeight:properties.trafficWeight,
        createdTime:properties.createdTime,
        replicas:properties.replicas
      }" \
      -o jsonc || true

  } > "$app_dir/summary.txt" 2>&1

  # App-specific expected env checks
  {
    echo "APP: $app"
    echo "TIME: $(date -Is)"
    echo
    echo "==== IMPORTANT ENV CHECK ===="

    case "$app" in
      backend)
        grep -E "^(APP_MODE|SERVICE_BUS_ENABLED|SERVICE_BUS_TRANSPORT|SERVICE_BUS_PREFETCH|SERVICE_BUS_MAX_CONCURRENT_CALLS|SERVICE_BUS_MAX_AUTO_LOCK_RENEW_MS)" "$app_dir/env-sanitized.tsv" || true
        ;;
      esendit-media-worker)
        grep -E "^(APP_MODE|MEDIA_WORKER_ENABLED|SERVICE_BUS_ENABLED|SERVICE_BUS_TRANSPORT|SERVICE_BUS_PREFETCH|SERVICE_BUS_MAX_CONCURRENT_CALLS|SERVICE_BUS_MAX_AUTO_LOCK_RENEW_MS|MEDIA_WORKER_SERVICE_BUS_DB_FALLBACK_ENABLED|MEDIA_WORKER_SERVICE_BUS_DB_FALLBACK_POLL_MS|MEDIA_WORKER_WATCHDOG_SERVICE_BUS_WAKE|MEDIA_WORKER_WATCHDOG_STALE_PENDING_REFRESH_ENABLED|MEDIA_WORKER_WATCHDOG_PENDING_WAKE_MAX_PER_RUN|MEDIA_WORKER_BUSY_ABANDON_DELAY_MS|MEDIA_WORKER_SHUTDOWN_GRACE_MS|MEDIA_JOB_STALE_RUNNING_AUTO_QC_MINUTES|MEDIA_JOB_STALE_RUNNING_PROXY_GEN_MINUTES|MEDIA_WORKDIR_CLEANUP_ENABLED|MEDIA_WORKDIR_MIN_FREE_MB|QC_QCLI_TIMEOUT_MINUTES)" "$app_dir/env-sanitized.tsv" || true
        ;;
      esendit-preset-worker)
        grep -E "^(APP_MODE|PRESET_WORKER_ENABLED|SERVICE_BUS_ENABLED|SERVICE_BUS_TRANSPORT|SERVICE_BUS_PREFETCH|SERVICE_BUS_MAX_CONCURRENT_CALLS|SERVICE_BUS_MAX_AUTO_LOCK_RENEW_MS|PRESET_WORKER_BUSY_ABANDON_DELAY_MS|PRESET_WORKER_SHUTDOWN_GRACE_MS)" "$app_dir/env-sanitized.tsv" || true
        ;;
      esendit-bulk-worker)
        grep -E "^(APP_MODE|BULK_MEDIA_WORKER_ENABLED|SERVICE_BUS_ENABLED|SERVICE_BUS_TRANSPORT|SERVICE_BUS_PREFETCH|SERVICE_BUS_MAX_CONCURRENT_CALLS|SERVICE_BUS_MAX_AUTO_LOCK_RENEW_MS|BULK_MEDIA_WORKER_BUSY_ABANDON_DELAY_MS|BULK_MEDIA_WORKER_SHUTDOWN_GRACE_MS)" "$app_dir/env-sanitized.tsv" || true
        ;;
      esendit-delivery-worker)
        grep -E "^(APP_MODE|DELIVERY_WORKER_ENABLED|SERVICE_BUS_ENABLED|SERVICE_BUS_TRANSPORT|SERVICE_BUS_PREFETCH|SERVICE_BUS_MAX_CONCURRENT_CALLS|SERVICE_BUS_MAX_AUTO_LOCK_RENEW_MS|DELIVERY_WORKER_BUSY_ABANDON_DELAY_MS|DELIVERY_WORKER_SHUTDOWN_GRACE_MS)" "$app_dir/env-sanitized.tsv" || true
        ;;
    esac
  } > "$app_dir/important-env-check.txt" 2>&1

done

# Combined readable report
{
  echo "# Worker Config Collection"
  echo
  echo "Time: $(date -Is)"
  echo "Resource group: $RG"
  echo "Service Bus namespace: $SB_NS"
  echo
  echo "## Queues"
  for q in "${QUEUES[@]}"; do
    safe_q="${q//[^a-zA-Z0-9_-]/_}"
    echo
    echo "### $q"
    cat "$OUT_DIR/queue_${safe_q}_details.txt" || true
  done

  echo
  echo "## Apps"
  for app in "${APPS[@]}"; do
    safe_app="${app//[^a-zA-Z0-9_-]/_}"
    echo
    echo "============================================================"
    echo "## $app"
    echo "============================================================"
    echo
    cat "$OUT_DIR/$safe_app/summary.txt" || true
    echo
    echo "---- Important env check ----"
    cat "$OUT_DIR/$safe_app/important-env-check.txt" || true
  done

  echo
  echo "## Errors"
  cat "$OUT_DIR/errors.txt" 2>/dev/null || echo "No command errors captured."
} > "$OUT_DIR/combined-report.txt"

tar -czf "$OUT_DIR.tar.gz" "$OUT_DIR"

echo
echo "Done."
echo "Folder:  $OUT_DIR"
echo "Archive: $OUT_DIR.tar.gz"
echo
echo "Upload/share this archive back:"
echo "$OUT_DIR.tar.gz"
