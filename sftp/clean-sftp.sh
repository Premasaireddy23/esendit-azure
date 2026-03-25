#!/usr/bin/env bash
set -euo pipefail

STATE_FILE="${STATE_FILE:-.az-state/ftp-destination.env}"

if [[ ! -f "$STATE_FILE" ]]; then
  echo "State file not found: $STATE_FILE"
  echo "Nothing to clean (or you deleted the state)."
  exit 0
fi

# shellcheck disable=SC1090
source "$STATE_FILE"

if [[ -z "${RG:-}" ]]; then
  echo "RG not found in state file."
  exit 1
fi

if [[ -n "${SUBSCRIPTION_ID:-}" ]]; then
  az account set --subscription "$SUBSCRIPTION_ID" >/dev/null 2>&1 || true
fi

echo "[cleanup] Deleting resource group: $RG"
az group delete -n "$RG" -y

echo "[cleanup] Done."
