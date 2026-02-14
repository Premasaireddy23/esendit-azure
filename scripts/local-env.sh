# source scripts/az-env.sh

export RG="${RG:-esendit}"
export LOCATION="${LOCATION:-centralindia}"

# Resource names (from your `az resource list`)
export ACR_NAME="${ACR_NAME:-Esendit}"
export POSTGRES_NAME="${POSTGRES_NAME:-esendit}"

# Container apps
export APP_BACKEND="${APP_BACKEND:-backend}"
export APP_MEDIA_WORKER="${APP_MEDIA_WORKER:-esendit-media-worker}"
export APP_PRESET_WORKER="${APP_PRESET_WORKER:-esendit-preset-worker}"
export APP_BULK_WORKER="${APP_BULK_WORKER:-esendit-bulk-worker}"
export APP_DELIVERY_WORKER="${APP_DELIVERY_WORKER:-esendit-delivery-worker}"

export APPS=(
  "$APP_BACKEND"
  "$APP_MEDIA_WORKER"
  "$APP_PRESET_WORKER"
  "$APP_BULK_WORKER"
  "$APP_DELIVERY_WORKER"
)

export ACR_LOGIN_SERVER="$(az acr show -n "$ACR_NAME" --query loginServer -o tsv 2>/dev/null || true)"
export BACKEND_FQDN="$(az containerapp show -n "$APP_BACKEND" -g "$RG" --query properties.configuration.ingress.fqdn -o tsv 2>/dev/null || true)"

# Tag helper (git sha + timestamp)
export TAG="$( (git rev-parse --short HEAD 2>/dev/null || echo manual)-$(date +%Y%m%d%H%M%S) )"

echo "RG=$RG"
echo "ACR_LOGIN_SERVER=$ACR_LOGIN_SERVER"
echo "BACKEND_FQDN=$BACKEND_FQDN"
echo "TAG=$TAG"
