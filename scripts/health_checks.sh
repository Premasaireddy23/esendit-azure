#!/usr/bin/env bash
set -euo pipefail

RG="${RG:-esendit}"
APPS=(backend esendit-media-worker esendit-preset-worker esendit-bulk-worker esendit-delivery-worker)

# Only check /health by default; override like:
#   HEALTH_PATHS="/health /metrics" ./health_checks.sh
HEALTH_PATHS=(${HEALTH_PATHS:-/health})

FILTER="The behavior of this command has been altered by the following extension: containerapp"
azc() { az "$@" 2> >(grep -vF "$FILTER" >&2); }

echo "=== App status + replicas (latest revision) ==="
for APP in "${APPS[@]}"; do
  # One 'show' call per app
  mapfile -t F < <(
    azc containerapp show -g "$RG" -n "$APP" \
      --query "[properties.provisioningState, properties.runningStatus, properties.latestRevisionName, properties.template.containers[0].image]" \
      -o tsv
  )
  
  PROV="${F[0]:-}"
  RUN="${F[1]:-}"
  REV="${F[2]:-}"
  IMG="${F[3]:-}"
  
  # fallback if REV is empty for any reason
  if [[ -z "${REV:-}" ]]; then
    REV="$(azc containerapp show -g "$RG" -n "$APP" --query properties.latestReadyRevisionName -o tsv 2>/dev/null || true)"
  fi
  

  # Replica count (no preview command)
  RC="$(azc containerapp replica list -g "$RG" -n "$APP" --revision "$REV" --query "length(@)" -o tsv 2>/dev/null || echo 0)"

  printf "%-24s prov=%-10s run=%-8s replicas=%-2s rev=%s\n" "$APP" "$PROV" "$RUN" "$RC" "$REV"
  echo "  image=$IMG"
done

echo
echo "=== Backend HTTP health ==="
FQDN="$(azc containerapp show -g "$RG" -n backend --query properties.configuration.ingress.fqdn -o tsv)"
echo "FQDN=$FQDN"

for P in "${HEALTH_PATHS[@]}"; do
  CODE="$(curl -sk -o /dev/null -w "%{http_code}" "https://$FQDN$P" || echo "000")"
  echo "$P -> $CODE"
done
