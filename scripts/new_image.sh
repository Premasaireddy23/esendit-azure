set -euo pipefail

# --- config ---
RG="${RG:-esendit}"
ACR_NAME="${ACR_NAME:-Esendit}"
REPO="${REPO:-esendit-backend}"
APPS=(backend esendit-media-worker esendit-preset-worker esendit-bulk-worker esendit-delivery-worker)

ACR_SERVER="$(az acr show -n "$ACR_NAME" --query loginServer -o tsv)"

# --- precheck ---
if [[ ! -f docker/ffmbc/ffmbc ]]; then
  echo "ERROR: docker/ffmbc/ffmbc not found in build context"
  exit 1
fi

chmod +x docker/ffmbc/ffmbc || true

# --- compute next vX tag ---
LATEST_NUM="$(
  az acr repository show-tags -n "$ACR_NAME" --repository "$REPO" -o tsv \
  | grep -E '^v[0-9]+$' | sed 's/^v//' | sort -n | tail -1
)"
if [[ -z "${LATEST_NUM:-}" ]]; then LATEST_NUM=0; fi
TAG="v$((LATEST_NUM + 1))"

echo "Deploying tag: $TAG"
echo "Image: $ACR_SERVER/$REPO:$TAG"

# --- build + push (cloud build) ---
az acr build \
  -r "$ACR_NAME" \
  -t "$REPO:$TAG" \
  -f Dockerfile \
  --build-arg ENABLE_FFMBC=1 \
  .

# --- deploy image to all apps + force 1 replica + activate+restart revision ---
for APP in "${APPS[@]}"; do
  echo "== update $APP -> $TAG =="
  az containerapp update -g "$RG" -n "$APP" \
    --image "$ACR_SERVER/$REPO:$TAG" \
    --min-replicas 1 --max-replicas 1

  REV="$(az containerapp show -g "$RG" -n "$APP" --query properties.latestRevisionName -o tsv)"
  az containerapp revision activate -g "$RG" -n "$APP" --revision "$REV" || true
  az containerapp revision restart -g "$RG" -n "$APP" --revision "$REV" || true
done

echo "Done. Tag=$TAG"