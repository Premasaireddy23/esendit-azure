set -euo pipefail

RG="${RG:-esendit}"
APPS=(backend esendit-media-worker esendit-preset-worker esendit-bulk-worker esendit-delivery-worker)

for APP in "${APPS[@]}"; do
  echo "==== $APP env ===="
  az containerapp show -g "$RG" -n "$APP" \
    --query "properties.template.containers[0].env[].{name:name,value:value,secretRef:secretRef}" \
    -o table
  echo
done
