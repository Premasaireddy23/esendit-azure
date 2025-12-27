#!/usr/bin/env bash
set -euo pipefail

ENVIRONMENT="${1:-}"
if [[ -z "${ENVIRONMENT}" || ( "${ENVIRONMENT}" != "dev" && "${ENVIRONMENT}" != "prod" ) ]]; then
  echo "Usage: $0 <dev|prod>"
  exit 1
fi

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
VALUES_DIR="${ROOT_DIR}/values/${ENVIRONMENT}"

# ---- configure per env ----
if [[ "${ENVIRONMENT}" == "dev" ]]; then
  SUB_ID="c824dfe2-906a-43cd-8c48-50f825e80036"
  RG_AKS="rg-esendit-dev-aks-ci"
  AKS_NAME="aks-esendit-dev-esendit000"
  EXPECTED_CTX_SUBSTR="aks-esendit-dev-esendit000"
else
  SUB_ID="f2676fa6-f639-4102-9865-f638f6b2c6c2"
  RG_AKS="rg-esendit-prod-aks-ci"
  AKS_NAME="aks-esendit-prod-esendit000"
  EXPECTED_CTX_SUBSTR="aks-esendit-prod-esendit000"
fi

echo ">>> env=${ENVIRONMENT}"
echo ">>> subscription=${SUB_ID}"
echo ">>> aks=${RG_AKS}/${AKS_NAME}"
echo ">>> values=${VALUES_DIR}"

az account set --subscription "${SUB_ID}"

# Pull credentials (admin optional; you can remove --admin if you prefer)
az aks get-credentials -g "${RG_AKS}" -n "${AKS_NAME}" --admin

# ---- Safety checks ----
CTX="$(kubectl config current-context)"
echo ">>> kubectl context: ${CTX}"

if [[ "${CTX}" != *"${EXPECTED_CTX_SUBSTR}"* ]]; then
  echo "ERROR: current kubectl context (${CTX}) does not match expected cluster (${EXPECTED_CTX_SUBSTR})."
  echo "Refusing to continue."
  exit 1
fi

kubectl cluster-info >/dev/null
kubectl get nodes >/dev/null

# ---- Helm repos ----
helm repo add ingress-nginx https://kubernetes.github.io/ingress-nginx >/dev/null 2>&1 || true
helm repo add jetstack https://charts.jetstack.io >/dev/null 2>&1 || true
helm repo add kedacore https://kedacore.github.io/charts >/dev/null 2>&1 || true
helm repo update >/dev/null

# ---- Namespaces ----
kubectl create ns ingress-nginx --dry-run=client -o yaml | kubectl apply -f -
kubectl create ns cert-manager  --dry-run=client -o yaml | kubectl apply -f -
kubectl create ns keda          --dry-run=client -o yaml | kubectl apply -f -

# ---- ingress-nginx ----
helm upgrade --install ingress-nginx ingress-nginx/ingress-nginx \
  -n ingress-nginx \
  -f "${VALUES_DIR}/ingress-nginx.yaml"

# ---- cert-manager ----
helm upgrade --install cert-manager jetstack/cert-manager \
  -n cert-manager \
  -f "${VALUES_DIR}/cert-manager.yaml"

# ---- KEDA ----
helm upgrade --install keda kedacore/keda \
  -n keda \
  -f "${VALUES_DIR}/keda.yaml"

echo ">>> Done."
kubectl get pods -n ingress-nginx
kubectl get pods -n cert-manager
kubectl get pods -n keda
kubectl get svc -n ingress-nginx
