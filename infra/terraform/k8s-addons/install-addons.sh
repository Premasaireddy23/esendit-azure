#!/usr/bin/env bash
set -euo pipefail

ENVIRONMENT="${1:-}"
if [[ -z "${ENVIRONMENT}" || ( "${ENVIRONMENT}" != "dev" && "${ENVIRONMENT}" != "prod" ) ]]; then
  echo "Usage: $0 <dev|prod>"
  exit 1
fi

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
VALUES_DIR="${ROOT_DIR}/values/${ENVIRONMENT}"
MANIFESTS_DIR="${ROOT_DIR}/manifests"

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
echo ">>> manifests=${MANIFESTS_DIR}"

az account set --subscription "${SUB_ID}"

# Pull credentials (admin used for reliability)
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
helm repo add prometheus-community https://prometheus-community.github.io/helm-charts >/dev/null 2>&1 || true
helm repo update >/dev/null

# ---- Namespaces ----
kubectl create ns ingress-nginx --dry-run=client -o yaml | kubectl apply -f -
kubectl create ns cert-manager  --dry-run=client -o yaml | kubectl apply -f -
kubectl create ns keda          --dry-run=client -o yaml | kubectl apply -f -
kubectl create ns monitoring    --dry-run=client -o yaml | kubectl apply -f -

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

# ---- Monitoring (kube-prometheus-stack) ----
if [[ -f "${VALUES_DIR}/monitoring.yaml" ]]; then
  helm upgrade --install monitoring prometheus-community/kube-prometheus-stack \
    -n monitoring \
    -f "${VALUES_DIR}/monitoring.yaml"

  # Wait for CRDs needed for ServiceMonitor/PrometheusRule
  kubectl wait --for=condition=Established --timeout=120s crd/servicemonitors.monitoring.coreos.com >/dev/null 2>&1 || true
  kubectl wait --for=condition=Established --timeout=120s crd/prometheusrules.monitoring.coreos.com >/dev/null 2>&1 || true

  # Ensure backend service has label + named port for ServiceMonitor
  kubectl -n esendit label svc esendit-backend monitor=esendit --overwrite

  # Add/replace port name to "http"
  kubectl -n esendit patch svc esendit-backend --type='json' \
    -p='[{"op":"add","path":"/spec/ports/0/name","value":"http"}]' \
    >/dev/null 2>&1 || \
  kubectl -n esendit patch svc esendit-backend --type='json' \
    -p='[{"op":"replace","path":"/spec/ports/0/name","value":"http"}]' \
    >/dev/null

  # Apply ServiceMonitor + alerts
  if [[ -f "${MANIFESTS_DIR}/monitoring/esendit-servicemonitor.yaml" ]]; then
    kubectl apply -f "${MANIFESTS_DIR}/monitoring/esendit-servicemonitor.yaml"
  fi

  if [[ -f "${MANIFESTS_DIR}/monitoring/esendit-alerts.yaml" ]]; then
    kubectl apply -f "${MANIFESTS_DIR}/monitoring/esendit-alerts.yaml"
  fi
else
  echo ">>> monitoring.yaml not found at ${VALUES_DIR}/monitoring.yaml; skipping monitoring install."
fi

echo ">>> Done."
kubectl get pods -n ingress-nginx
kubectl get pods -n cert-manager
kubectl get pods -n keda
kubectl get pods -n monitoring || true
kubectl get svc -n ingress-nginx
