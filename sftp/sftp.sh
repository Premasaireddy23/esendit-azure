#!/usr/bin/env bash
set -euo pipefail

# -----------------------------
# FTP Destination (TEST) on Azure Container Instances
# - FTP: port 21 + 4 passive ports (ACI port limit)
# - Persistent storage via Azure Files
# - Image pulled from ACR (imported server-side)
# -----------------------------

# ---- configurable (override via env vars) ----
SUBSCRIPTION_ID="${SUBSCRIPTION_ID:-}"                 # optional
RG="${RG:-rg-ftp-destination-test}"
LOC="${LOC:-northeurope}"

ACI_NAME="${ACI_NAME:-esendit-dest-ftp}"
DNS_LABEL="${DNS_LABEL:-esendit-ftp-32628-27645}"      # keep stable, or change to random if you want
FQDN="${DNS_LABEL}.${LOC}.azurecontainer.io"

FTP_USER="${FTP_USER:-ftpuser}"
FTP_PASS="${FTP_PASS:-Test@12345678}"                 # set your own, or override env var

PASV_MIN="${PASV_MIN:-30000}"
PASV_MAX="${PASV_MAX:-30003}"                         # keep small due to ACI ports limit

# ---- image import options (avoid Docker Hub 429 limits) ----
SRC_IMAGE="${SRC_IMAGE:-docker.io/fauria/vsftpd:latest}"   # source image to mirror
ACR_IMAGE="${ACR_IMAGE:-vsftpd:latest}"                   # repo:tag in your ACR

# Optional: set these to authenticate to Docker Hub and increase pull limits.
# Recommended to set DOCKERHUB_TOKEN as a Personal Access Token (PAT), not your password.
DOCKERHUB_USER="${DOCKERHUB_USER:-}"
DOCKERHUB_TOKEN="${DOCKERHUB_TOKEN:-${DOCKERHUB_PASS:-}}"

IMPORT_RETRIES="${IMPORT_RETRIES:-5}"
IMPORT_DELAY_SECONDS="${IMPORT_DELAY_SECONDS:-10}"

# Names can be auto-created once; if they already exist in the RG, we reuse them.
ACR_NAME="${ACR_NAME:-}"                              # optional: if empty, script reuses/creates one in RG
SHARE="${SHARE:-ftpdata}"

STATE_DIR="${STATE_DIR:-.az-state}"
STATE_FILE="$STATE_DIR/ftp-destination.env"
mkdir -p "$STATE_DIR"

need() { command -v "$1" >/dev/null 2>&1 || { echo "Missing: $1"; exit 1; }; }

retry() {
  local tries="$1"; shift
  local delay="$1"; shift
  local n=1
  until "$@"; do
    if (( n >= tries )); then
      return 1
    fi
    echo "[warn] command failed (attempt ${n}/${tries}). retrying in ${delay}s..."
    sleep "$delay"
    n=$((n+1))
    delay=$((delay*2))
  done
}
need az

az account show >/dev/null 2>&1 || { echo "Not logged in. Run: az login"; exit 1; }

if [[ -n "$SUBSCRIPTION_ID" ]]; then
  az account set --subscription "$SUBSCRIPTION_ID"
fi

echo "[info] Subscription:"
az account show --query "{name:name,id:id,user:user.name}" -o table

echo
echo "[plan] RG=$RG LOC=$LOC"
echo "[plan] ACI=$ACI_NAME FQDN=$FQDN"
echo "[plan] FTP_USER=$FTP_USER FTP_PASS=***"
echo "[plan] Passive ports: ${PASV_MIN}-${PASV_MAX}"
echo

# 1) RG
az group create -n "$RG" -l "$LOC" -o none

# 2) Providers (safe)
az provider register -n Microsoft.ContainerInstance >/dev/null
az provider register -n Microsoft.Storage >/dev/null
az provider register -n Microsoft.ContainerRegistry >/dev/null

# 3) Storage Account (reuse if exists, else create)
SA="$(az storage account list -g "$RG" --query "[0].name" -o tsv 2>/dev/null || true)"
if [[ -z "${SA:-}" ]]; then
  SA="esftp$RANDOM$RANDOM"
  SA="$(echo "$SA" | tr -cd 'a-z0-9' | cut -c1-24)"
  echo "[1/5] Creating Storage Account: $SA"
  az storage account create -g "$RG" -n "$SA" -l "$LOC" \
    --sku Standard_LRS --kind StorageV2 \
    --min-tls-version TLS1_2 \
    -o none
else
  echo "[1/5] Reusing Storage Account: $SA"
fi

SA_KEY="$(az storage account keys list -g "$RG" -n "$SA" --query "[0].value" -o tsv)"

echo "[2/5] Ensure file share + upload dir..."
az storage share create --account-name "$SA" --account-key "$SA_KEY" --name "$SHARE" -o none
az storage directory create --account-name "$SA" --account-key "$SA_KEY" --share-name "$SHARE" --name "upload" -o none || true

# 4) ACR (reuse if exists, else create)
if [[ -n "$ACR_NAME" ]]; then
  ACR="$ACR_NAME"
else
  ACR="$(az acr list -g "$RG" --query "[0].name" -o tsv 2>/dev/null || true)"
fi

if [[ -z "${ACR:-}" ]]; then
  ACR="esftpacr$RANDOM$RANDOM"
  ACR="$(echo "$ACR" | tr -cd 'a-z0-9' | cut -c1-24)"
  echo "[3/5] Creating ACR: $ACR"
  az acr create -g "$RG" -n "$ACR" --sku Basic --admin-enabled true -o none
else
  echo "[3/5] Reusing ACR: $ACR"
fi

ACR_SERVER="$(az acr show -g "$RG" -n "$ACR" --query loginServer -o tsv)"
ACR_USER="$(az acr credential show -g "$RG" -n "$ACR" --query username -o tsv)"
ACR_PASS="$(az acr credential show -g "$RG" -n "$ACR" --query passwords[0].value -o tsv)"

echo "[4/5] Import vsftpd image into ACR (server-side)..."

# If the tag already exists, don't re-import (helps avoid rate limits).
ACR_REPO="${ACR_IMAGE%%:*}"
ACR_TAG="${ACR_IMAGE##*:}"
if az acr repository show-tags -n "$ACR" --repository "$ACR_REPO" -o tsv 2>/dev/null | grep -qx "$ACR_TAG"; then
  echo "[4/5] Image already present: ${ACR_SERVER}/${ACR_IMAGE}"
else
  import_cmd=(az acr import -n "$ACR" --source "$SRC_IMAGE" --image "$ACR_IMAGE" --force)
  if [[ -n "$DOCKERHUB_USER" && -n "$DOCKERHUB_TOKEN" ]]; then
    import_cmd+=(-u "$DOCKERHUB_USER" -p "$DOCKERHUB_TOKEN")
  fi

  if ! retry "$IMPORT_RETRIES" "$IMPORT_DELAY_SECONDS" "${import_cmd[@]}"; then
    echo "[error] Failed to import $SRC_IMAGE into $ACR."
    echo "        If you see Docker Hub 429 rate limit, export DOCKERHUB_USER + DOCKERHUB_TOKEN (Docker Hub PAT) and re-run."
    echo "        Example:"
    echo "          export DOCKERHUB_USER=youruser"
    echo "          export DOCKERHUB_TOKEN=your_pat"
    exit 1
  fi

  # sanity check: confirm the tag exists after import
  if ! az acr repository show-tags -n "$ACR" --repository "$ACR_REPO" -o tsv | grep -qx "$ACR_TAG"; then
    echo "[error] Import completed but tag ${ACR_REPO}:${ACR_TAG} not found in ACR (unexpected)."
    exit 1
  fi
fi
# 5) Replace container group
echo "[5/5] Recreate ACI container group..."
az container delete -g "$RG" -n "$ACI_NAME" -y >/dev/null 2>&1 || true

az container create \
  -g "$RG" -n "$ACI_NAME" -l "$LOC" \
  --os-type Linux \
  --image "${ACR_SERVER}/vsftpd:latest" \
  --registry-login-server "$ACR_SERVER" \
  --registry-username "$ACR_USER" \
  --registry-password "$ACR_PASS" \
  --ip-address Public \
  --dns-name-label "$DNS_LABEL" \
  --ports 21 "$PASV_MIN" "$((PASV_MIN+1))" "$((PASV_MIN+2))" "$((PASV_MIN+3))" \
  --cpu 1 --memory 1.5 \
  --restart-policy Always \
  --environment-variables \
    "FTP_USER=$FTP_USER" \
    "FTP_PASS=$FTP_PASS" \
    "PASV_ADDRESS=$FQDN" \
    "PASV_ADDR_RESOLVE=YES" \
    "PASV_MIN_PORT=$PASV_MIN" \
    "PASV_MAX_PORT=$PASV_MAX" \
    "REVERSE_LOOKUP_ENABLE=NO" \
    "LOG_STDOUT=1" \
    "FILE_OPEN_MODE=0777" \
    "LOCAL_UMASK=000" \
  --azure-file-volume-account-name "$SA" \
  --azure-file-volume-account-key "$SA_KEY" \
  --azure-file-volume-share-name "$SHARE" \
  --azure-file-volume-mount-path "/home/vsftpd" \
  -o none

IP="$(az container show -g "$RG" -n "$ACI_NAME" --query ipAddress.ip -o tsv)"

# Save state for cleanup and reuse
cat > "$STATE_FILE" <<EOF
SUBSCRIPTION_ID=${SUBSCRIPTION_ID}
RG=${RG}
LOC=${LOC}
ACI_NAME=${ACI_NAME}
DNS_LABEL=${DNS_LABEL}
FQDN=${FQDN}
IP=${IP}
FTP_USER=${FTP_USER}
FTP_PASS=${FTP_PASS}
PASV_MIN=${PASV_MIN}
PASV_MAX=${PASV_MAX}
SA=${SA}
SHARE=${SHARE}
ACR=${ACR}
EOF

echo
echo "=========== FTP DESTINATION READY ==========="
echo "HOST (FQDN): $FQDN"
echo "HOST (IP):   $IP"
echo "PORT:        21"
echo "USER:        $FTP_USER"
echo "PASS:        $FTP_PASS"
echo "MODE:        Passive"
echo "PASV:        ${PASV_MIN}-${PASV_MAX}"
echo "PATH:        upload"
echo
echo "Test upload:"
echo "  echo hello > test.txt"
echo "  curl -v --ftp-pasv -T test.txt --user \"$FTP_USER:$FTP_PASS\" \"ftp://$IP/upload/test.txt\""
echo
echo "State saved to: $STATE_FILE"
echo "============================================"
