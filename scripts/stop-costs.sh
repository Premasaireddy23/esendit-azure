#!/usr/bin/env bash
set -euo pipefail

RG="${RG:-esendit}"
STATE_DIR="${STATE_DIR:-.az-state}"
mkdir -p "$STATE_DIR"

retry() {
  local n=0 max=6 delay=2
  while true; do
    "$@" && return 0
    n=$((n+1))
    if (( n >= max )); then return 1; fi
    sleep $((delay*n))
  done
}

get_api_version() {
  local rt="$1"
  az provider show -n Microsoft.App \
    --query "resourceTypes[?resourceType=='$rt'].apiVersions" -o tsv \
    | tr '\t' '\n' | grep -vi preview | head -n1
}

SUB_ID="$(az account show --query id -o tsv)"

API_CA="$(get_api_version containerApps || true)"
: "${API_CA:=2025-07-01}"

echo "[stop] Resource group: $RG"
echo "[stop] Using ContainerApps api-version: $API_CA"

# List apps via ARM generic resource listing (avoids containerapp extension JSON issues)
APPS="$(retry az resource list -g "$RG" \
  --resource-type "Microsoft.App/containerApps" \
  --query "[].name" -o tsv)"

if [[ -z "${APPS// }" ]]; then
  echo "[stop] No Container Apps found in RG=$RG"
else
  echo "[stop] Container Apps:"
  echo "$APPS" | sed 's/^/  - /'
fi

FAIL=0

for APP in $APPS; do
  echo "[stop] Stopping Container App: $APP"
  if ! retry az rest --method post \
      --url "https://management.azure.com/subscriptions/${SUB_ID}/resourceGroups/${RG}/providers/Microsoft.App/containerApps/${APP}/stop?api-version=${API_CA}" \
      >/dev/null; then
    echo "[stop] WARN: failed to stop $APP (ARM may be unavailable)."
    FAIL=1
    continue
  fi

  # Optional status check
  STATUS="$(az rest --method get \
      --url "https://management.azure.com/subscriptions/${SUB_ID}/resourceGroups/${RG}/providers/Microsoft.App/containerApps/${APP}?api-version=${API_CA}" \
      --query "properties.runningStatus" -o tsv 2>/dev/null || echo "?")"
  echo "[stop]   $APP runningStatus=$STATUS"
done

# Stop Postgres Flexible Server(s) compute
PGS="$(az resource list -g "$RG" --resource-type "Microsoft.DBforPostgreSQL/flexibleServers" --query "[].name" -o tsv 2>/dev/null || true)"
for PG in $PGS; do
  echo "[stop] Stopping Postgres flexible server compute: $PG"
  az postgres flexible-server stop -g "$RG" -n "$PG" >/dev/null || true
done

echo
echo "[stop] Done."
echo "[stop] NOTE: Storage/ServiceBus/ACR/LogAnalytics still incur some cost."
exit $FAIL
