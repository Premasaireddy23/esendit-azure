#!/usr/bin/env bash
set -euo pipefail

# --- config ---
RG="${RG:-esendit}"
ACR_NAME="${ACR_NAME:-Esendit}"
REPO="${REPO:-esendit-backend}"
APPS=(backend esendit-media-worker esendit-preset-worker esendit-bulk-worker esendit-delivery-worker)

# --- per app replica config ---
declare -A MIN_REPLICAS=(
  [backend]=1
  [esendit-media-worker]=1
  [esendit-preset-worker]=1
  [esendit-bulk-worker]=0
  [esendit-delivery-worker]=1
)

declare -A MAX_REPLICAS=(
  [backend]=2
  [esendit-media-worker]=6
  [esendit-preset-worker]=30
  [esendit-bulk-worker]=1
  [esendit-delivery-worker]=6
)

# --- feature flags ---
ENABLE_FFMBC="${ENABLE_FFMBC:-1}"
ENABLE_ASPERA_CLI="${ENABLE_ASPERA_CLI:-1}"
ENABLE_ASPERA_ASCP_INSTALL="${ENABLE_ASPERA_ASCP_INSTALL:-1}"
DEPLOY_ACA="${DEPLOY_ACA:-1}"

ACR_SERVER="$(az acr show -n "$ACR_NAME" --query loginServer -o tsv)"

# --- precheck ---
if [[ ! -f docker/ffmbc/ffmbc ]]; then
  echo "ERROR: docker/ffmbc/ffmbc not found in build context"
  exit 1
fi

chmod +x docker/ffmbc/ffmbc || true

# --- compute tag unless provided ---
TAG="${TAG:-}"
if [[ -z "$TAG" ]]; then
  LATEST_NUM="$({
    az acr repository show-tags -n "$ACR_NAME" --repository "$REPO" -o tsv \
      | grep -E '^v[0-9]+$' | sed 's/^v//' | sort -n | tail -1
  } || true)"

  if [[ -z "${LATEST_NUM:-}" ]]; then
    LATEST_NUM=0
  fi

  TAG="v$((LATEST_NUM + 1))"
fi

echo "Building tag: $TAG"
echo "Image: $ACR_SERVER/$REPO:$TAG"
echo "Build args: ENABLE_FFMBC=$ENABLE_FFMBC ENABLE_ASPERA_CLI=$ENABLE_ASPERA_CLI ENABLE_ASPERA_ASCP_INSTALL=$ENABLE_ASPERA_ASCP_INSTALL"

# --- build + push (cloud build) ---
az acr build \
  -r "$ACR_NAME" \
  -t "$REPO:$TAG" \
  -f Dockerfile \
  --build-arg ENABLE_FFMBC="$ENABLE_FFMBC" \
  --build-arg ENABLE_ASPERA_CLI="$ENABLE_ASPERA_CLI" \
  --build-arg ENABLE_ASPERA_ASCP_INSTALL="$ENABLE_ASPERA_ASCP_INSTALL" \
  .

echo
echo "Build complete: $ACR_SERVER/$REPO:$TAG"

# --- optionally deploy image to all ACA apps ---
if [[ "$DEPLOY_ACA" == "1" ]]; then
  for APP in "${APPS[@]}"; do
    MIN="${MIN_REPLICAS[$APP]:-1}"
    MAX="${MAX_REPLICAS[$APP]:-1}"

    echo "== update $APP -> $TAG | min=$MIN max=$MAX =="

    az containerapp update -g "$RG" -n "$APP" \
      --image "$ACR_SERVER/$REPO:$TAG" \
      --min-replicas "$MIN" \
      --max-replicas "$MAX"

    REV="$(az containerapp show -g "$RG" -n "$APP" --query properties.latestRevisionName -o tsv)"
    az containerapp revision activate -g "$RG" -n "$APP" --revision "$REV" || true
    az containerapp revision restart -g "$RG" -n "$APP" --revision "$REV" || true
  done

  echo
  echo "ACA deployment complete."
else
  echo "Skipping ACA deployment because DEPLOY_ACA=$DEPLOY_ACA"
fi

echo
echo "If you also want this tag on the static VM worker, run:"
echo "  /opt/esendit-delivery-worker/deploy_vm_worker.sh $TAG"
echo
echo
echo "Done. Tag=$TAG"