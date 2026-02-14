#!/usr/bin/env bash
set -euo pipefail

RG="${RG:-esendit}"

# Default: your 5 apps (override if needed)
APPS_OVERRIDE="${APPS_OVERRIDE:-backend esendit-media-worker esendit-preset-worker esendit-bulk-worker esendit-delivery-worker}"

MIN_REPLICAS="${MIN_REPLICAS:-1}"
MAX_REPLICAS="${MAX_REPLICAS:-1}"

WAIT_SECONDS="${WAIT_SECONDS:-600}"
WAIT_INTERVAL="${WAIT_INTERVAL:-5}"

API_VERSION="${API_VERSION:-2025-07-01}"

echo "[start] Resource group: $RG"
echo "[start] Apps: $APPS_OVERRIDE"
echo "[start] Desired replicas: min=$MIN_REPLICAS max=$MAX_REPLICAS"

now_ts() { date -u +"%Y-%m-%dT%H:%M:%SZ"; }

# Prevent az hangs from blocking forever (uses GNU timeout if available)
az_safe() {
  local t="$1"; shift
  if command -v timeout >/dev/null 2>&1; then
    timeout "${t}s" az "$@" || true
  else
    az "$@" || true
  fi
}

# -------- 1) Start Postgres first --------
PGS="$(az postgres flexible-server list -g "$RG" --query "[].name" -o tsv 2>/dev/null || true)"
for PG in $PGS; do
  echo "[start] Starting Postgres flexible server: $PG"
  az_safe 180 postgres flexible-server start -g "$RG" -n "$PG" >/dev/null

  echo "[start] Waiting for Postgres '$PG' to be Ready..."
  for _ in $(seq 1 60); do
    STATE="$(az postgres flexible-server show -g "$RG" -n "$PG" --query state -o tsv 2>/dev/null || echo "")"
    if [[ "$STATE" == "Ready" ]]; then
      echo "[start] Postgres '$PG' is Ready."
      break
    fi
    sleep 5
  done
done

# -------- helpers --------
app_id() {
  local app="$1"
  az containerapp show -g "$RG" -n "$app" --query id -o tsv 2>/dev/null || true
}

running_status() {
  local app="$1"
  az containerapp show -g "$RG" -n "$app" --query properties.runningStatus -o tsv 2>/dev/null || true
}

start_app() {
  local app="$1"
  local id st
  st="$(running_status "$app")"
  echo "[start] runningStatus: app=$app status=${st:-UNKNOWN}"

  if [[ "$st" != "Running" ]]; then
    id="$(app_id "$app")"
    if [[ -z "${id:-}" ]]; then
      echo "[start] WARN: cannot get resource id for app=$app"
      return 0
    fi
    echo "[start] Starting app via REST: app=$app"
    az rest -m post -u "https://management.azure.com${id}/start?api-version=${API_VERSION}" >/dev/null || true
  fi
}

wait_for_running() {
  local app="$1"
  local waited=0
  while (( waited < WAIT_SECONDS )); do
    local st
    st="$(running_status "$app")"
    if [[ "$st" == "Running" ]]; then
      echo "[start] OK running: app=$app"
      return 0
    fi
    echo "[start] waiting: app=$app status=${st:-UNKNOWN} waited=${waited}s"
    sleep "$WAIT_INTERVAL"
    waited=$(( waited + WAIT_INTERVAL ))
  done
  echo "[start] WARN: app not Running after ${WAIT_SECONDS}s: app=$app"
  return 1
}

ensure_scale() {
  local app="$1"
  local cur_min cur_max
  cur_min="$(az containerapp show -g "$RG" -n "$app" --query properties.template.scale.minReplicas -o tsv 2>/dev/null || echo "0")"
  cur_max="$(az containerapp show -g "$RG" -n "$app" --query properties.template.scale.maxReplicas -o tsv 2>/dev/null || echo "0")"
  cur_min="${cur_min:-0}"
  cur_max="${cur_max:-0}"

  if [[ "$cur_min" != "$MIN_REPLICAS" || "$cur_max" != "$MAX_REPLICAS" ]]; then
    echo "[start] Scale update: app=$app min=$MIN_REPLICAS max=$MAX_REPLICAS (was min=$cur_min max=$cur_max)"
    az_safe 240 containerapp update -g "$RG" -n "$app" \
      --min-replicas "$MIN_REPLICAS" --max-replicas "$MAX_REPLICAS" >/dev/null
  else
    echo "[start] Scale OK: app=$app min=$cur_min max=$cur_max"
  fi
}

active_revision() {
  local app="$1"
  az containerapp revision list -g "$RG" -n "$app" \
    --query "[?properties.active].name | [0]" -o tsv 2>/dev/null || true
}

replica_count() {
  local app="$1" rev="$2"
  az containerapp replica list -g "$RG" -n "$app" --revision "$rev" \
    --query "length(@)" -o tsv 2>/dev/null || echo "0"
}

wait_for_replicas() {
  local app="$1" rev="$2" want="${3:-1}"
  local waited=0
  while (( waited < WAIT_SECONDS )); do
    local c
    c="$(replica_count "$app" "$rev")"
    c="${c:-0}"
    if [[ "$c" =~ ^[0-9]+$ ]] && (( c >= want )); then
      echo "[start] OK replicas: app=$app rev=$rev count=$c"
      return 0
    fi
    echo "[start] waiting replicas: app=$app rev=$rev count=$c waited=${waited}s"
    sleep "$WAIT_INTERVAL"
    waited=$(( waited + WAIT_INTERVAL ))
  done
  echo "[start] WARN: replicas still < $want after ${WAIT_SECONDS}s: app=$app rev=$rev"
  return 1
}

# -------- 2) Start apps --------
read -r -a APPS <<< "$APPS_OVERRIDE"

echo "[start] Bringing up ${#APPS[@]} Container Apps..."
for APP in "${APPS[@]}"; do
  echo
  echo "[start] ---- $APP ----"

  start_app "$APP"
  wait_for_running "$APP" || true

  ensure_scale "$APP"

  REV="$(active_revision "$APP")"
  if [[ -z "${REV:-}" ]]; then
    echo "[start] WARN: cannot determine active revision for app=$APP"
    continue
  fi

  wait_for_replicas "$APP" "$REV" 1 || {
    echo "[start] Diagnostics @ $(now_ts) for app=$APP"
    az containerapp revision list -g "$RG" -n "$APP" -o table || true
    az containerapp logs show -g "$RG" -n "$APP" --tail 200 || true
  }
done

echo
echo "[start] Done."
