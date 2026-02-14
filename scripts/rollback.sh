#!/usr/bin/env bash
set -euo pipefail

# --- config ---
RG="${RG:-esendit}"
ACR_NAME="${ACR_NAME:-Esendit}"          # NOTE: ACR resource name is usually lowercase (e.g., "esendit")
REPO="${REPO:-esendit-backend}"

# Default apps (used if you just press Enter at the apps prompt)
DEFAULT_APPS=(backend esendit-media-worker esendit-preset-worker esendit-bulk-worker esendit-delivery-worker)

SHOW_LAST_N="${SHOW_LAST_N:-3}"          # show last N numeric tags (v1, v2, ...)
PIN_REPLICAS="${PIN_REPLICAS:-true}"
MIN_REPLICAS="${MIN_REPLICAS:-1}"
MAX_REPLICAS="${MAX_REPLICAS:-1}"

# --- helpers ---
die() { echo "ERROR: $*" >&2; exit 1; }

trim() {
  local s="$*"
  # shellcheck disable=SC2001
  echo "$s" | sed 's/^[[:space:]]*//; s/[[:space:]]*$//'
}

# --- resolve ACR login server ---
ACR_SERVER="$(az acr show -n "$ACR_NAME" --query loginServer -o tsv 2>/dev/null || true)"
[[ -n "${ACR_SERVER:-}" ]] || die "Cannot read ACR '$ACR_NAME'. Check ACR_NAME and your az login/subscription."

# --- list available container apps in RG ---
mapfile -t ALL_APPS < <(
  az containerapp list -g "$RG" --query "[].name" -o tsv 2>/dev/null | sort
)

if [[ "${#ALL_APPS[@]}" -eq 0 ]]; then
  die "No Container Apps found in resource group '$RG' (or you don't have access)."
fi

# If apps passed as args, use those; otherwise interactive selection.
APPS=()
if [[ $# -gt 0 ]]; then
  APPS=("$@")
else
  echo "Resource Group: $RG"
  echo "Available Container Apps:"
  for i in "${!ALL_APPS[@]}"; do
    printf "  %2d) %s\n" "$((i+1))" "${ALL_APPS[$i]}"
  done
  echo
  echo "Choose apps to rollback:"
  echo "  - Type 'all' to rollback ALL apps in this RG"
  echo "  - Or comma-separated numbers (e.g., 1,3,5)"
  echo "  - Or comma-separated names (e.g., backend,esendit-media-worker)"
  echo "  - Or press Enter to use defaults: ${DEFAULT_APPS[*]}"
  echo
  read -r -p "Apps: " APICK
  APICK="$(trim "${APICK:-}")"

  # Build a membership map for validation
  declare -A APP_SET=()
  for a in "${ALL_APPS[@]}"; do APP_SET["$a"]=1; done

  if [[ -z "$APICK" ]]; then
    # use defaults but only those that exist
    for a in "${DEFAULT_APPS[@]}"; do
      if [[ -n "${APP_SET[$a]:-}" ]]; then APPS+=("$a"); fi
    done
    [[ "${#APPS[@]}" -gt 0 ]] || die "None of the DEFAULT_APPS exist in RG '$RG'. Select from the list."
  elif [[ "$APICK" == "all" || "$APICK" == "ALL" ]]; then
    APPS=("${ALL_APPS[@]}")
  else
    # split by comma
    IFS=',' read -r -a TOKENS <<< "$APICK"

    for tok in "${TOKENS[@]}"; do
      tok="$(trim "$tok")"
      [[ -n "$tok" ]] || continue

      if [[ "$tok" =~ ^[0-9]+$ ]]; then
        idx=$((tok - 1))
        (( idx >= 0 && idx < ${#ALL_APPS[@]} )) || die "Invalid app number: $tok"
        APPS+=("${ALL_APPS[$idx]}")
      else
        [[ -n "${APP_SET[$tok]:-}" ]] || die "App name not found in RG '$RG': '$tok'"
        APPS+=("$tok")
      fi
    done

    [[ "${#APPS[@]}" -gt 0 ]] || die "No apps selected."
  fi
fi

# de-duplicate APPS (preserve order)
declare -A SEEN=()
SEL_APPS=()
for a in "${APPS[@]}"; do
  if [[ -z "${SEEN[$a]:-}" ]]; then
    SEEN["$a"]=1
    SEL_APPS+=("$a")
  fi
done
APPS=("${SEL_APPS[@]}")

echo
echo "Selected apps:"
for a in "${APPS[@]}"; do echo "  - $a"; done
echo

# --- collect latest tags (numeric vN) ---
mapfile -t TAGS < <(
  az acr repository show-tags -n "$ACR_NAME" --repository "$REPO" -o tsv \
    | grep -E '^v[0-9]+$' \
    | sed 's/^v//' \
    | sort -n \
    | tail -n "$SHOW_LAST_N" \
    | awk '{print "v"$1}'
)

[[ "${#TAGS[@]}" -gt 0 ]] || die "No numeric tags found in ACR repo '$REPO' (ACR: $ACR_NAME)."

echo "ACR:   $ACR_NAME ($ACR_SERVER)"
echo "Repo:  $REPO"
echo
echo "Last ${#TAGS[@]} available versions:"
i=1
for t in "${TAGS[@]}"; do
  echo "  $i) $t"
  ((i++))
done
echo

# --- user input (accept: number OR tag) ---
read -r -p "Enter version to rollback to (number or tag like v12): " PICK
PICK="$(trim "${PICK:-}")"
[[ -n "$PICK" ]] || die "No version entered."

TAG=""
if [[ "$PICK" =~ ^[0-9]+$ ]]; then
  idx=$((PICK - 1))
  (( idx >= 0 && idx < ${#TAGS[@]} )) || die "Invalid selection number."
  TAG="${TAGS[$idx]}"
else
  TAG="$PICK"
fi

# normalize tag
[[ "$TAG" =~ ^v[0-9]+$ ]] || die "Tag must look like v12. You entered: '$TAG'"

# --- sanity: ensure tag exists in ACR ---
FOUND_TAG="$(
  az acr repository show-tags -n "$ACR_NAME" --repository "$REPO" \
    --query "[?@=='$TAG'] | [0]" -o tsv
)"
[[ -n "${FOUND_TAG:-}" ]] || die "Tag '$TAG' not found in ACR repo '$REPO'."

IMAGE="$ACR_SERVER/$REPO:$TAG"

echo
echo "Rolling back selected apps to: $IMAGE"
echo

# --- deploy tag to selected apps ---
for APP in "${APPS[@]}"; do
  echo "== rollback $APP -> $TAG =="

  if [[ "$PIN_REPLICAS" == "true" ]]; then
    az containerapp update -g "$RG" -n "$APP" \
      --image "$IMAGE" \
      --min-replicas "$MIN_REPLICAS" --max-replicas "$MAX_REPLICAS"
  else
    az containerapp update -g "$RG" -n "$APP" \
      --image "$IMAGE"
  fi

  REV="$(az containerapp show -g "$RG" -n "$APP" --query properties.latestRevisionName -o tsv)"

  # These may not apply in all modes; ignore if unsupported.
  az containerapp revision activate -g "$RG" -n "$APP" --revision "$REV" >/dev/null 2>&1 || true
  az containerapp revision restart  -g "$RG" -n "$APP" --revision "$REV" >/dev/null 2>&1 || true

  echo "Activated revision: $REV"
  echo
done

echo "Done. Rolled back selected apps to $TAG"
