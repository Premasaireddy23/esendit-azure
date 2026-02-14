#!/usr/bin/env bash
set -euo pipefail

# -------------------------
# Usage:
#   ./run_ffmpeg_preset_debug.sh -p <PRESET_ID> -i <INPUT_FILE> \
#     [-j <PRESETS_JSON>] [-o <OUTPUT_FILE>] \
#     [-t <IMAGE_TAG>] [-f <DOCKERFILE>] [-c <BUILD_CONTEXT>] \
#     [--no-build] [--timeout <SECONDS>] [--timecode <TC>] [--creation-time <ISO8601>]
# -------------------------

PRESET_ID=""
INPUT_FILE=""
PRESETS_JSON="./downloadPresets_linux_profiles.json"
OUTPUT_FILE=""
IMAGE_TAG="esendit-ffmpeg-debug:local"
DOCKERFILE="./Dockerfile"
BUILD_CONTEXT="."
NO_BUILD="false"
FFMPEG_TIMEOUT=""
TIMECODE="10:00:00:00"
CREATION_TIME=""

while [[ $# -gt 0 ]]; do
  case "$1" in
    -p) PRESET_ID="$2"; shift 2;;
    -i) INPUT_FILE="$2"; shift 2;;
    -j) PRESETS_JSON="$2"; shift 2;;
    -o) OUTPUT_FILE="$2"; shift 2;;
    -t) IMAGE_TAG="$2"; shift 2;;
    -f) DOCKERFILE="$2"; shift 2;;
    -c) BUILD_CONTEXT="$2"; shift 2;;
    --no-build) NO_BUILD="true"; shift 1;;
    --timeout) FFMPEG_TIMEOUT="$2"; shift 2;;
    --timecode) TIMECODE="$2"; shift 2;;
    --creation-time) CREATION_TIME="$2"; shift 2;;
    -h|--help)
      echo "Usage: $0 -p <PRESET_ID> -i <INPUT_FILE> [-j <PRESETS_JSON>] [-o <OUTPUT_FILE>] [-t <IMAGE_TAG>] [-f <DOCKERFILE>] [-c <BUILD_CONTEXT>] [--no-build] [--timeout <SECONDS>] [--timecode <TC>] [--creation-time <ISO8601>]"
      exit 0
      ;;
    *) echo "Unknown arg: $1"; exit 1;;
  esac
done

if [[ -z "${PRESET_ID}" || -z "${INPUT_FILE}" ]]; then
  echo "ERROR: -p <PRESET_ID> and -i <INPUT_FILE> are required"
  exit 1
fi
if [[ ! -f "${INPUT_FILE}" ]]; then
  echo "ERROR: input file not found: ${INPUT_FILE}"
  exit 1
fi
if [[ ! -f "${PRESETS_JSON}" ]]; then
  echo "ERROR: presets json not found: ${PRESETS_JSON}"
  exit 1
fi
if [[ -z "${CREATION_TIME}" ]]; then
  CREATION_TIME="$(date -u +%Y-%m-%dT%H:%M:%SZ)"
fi

ROOT_DIR="$(pwd)"
IN_DIR="${ROOT_DIR}/in"
OUT_DIR="${ROOT_DIR}/out"
LOG_DIR="${ROOT_DIR}/logs"
mkdir -p "${IN_DIR}" "${OUT_DIR}" "${LOG_DIR}"

# Copy input + presets into local workspace (stable mount)
INPUT_BASENAME="$(basename "${INPUT_FILE}")"
cp -f "${INPUT_FILE}" "${IN_DIR}/${INPUT_BASENAME}"
cp -f "${PRESETS_JSON}" "${ROOT_DIR}/presets.json"

# Default output name (ensure extension so muxer is selected)
if [[ -z "${OUTPUT_FILE}" ]]; then
  ext="out"
  case "${PRESET_ID}" in
    *mxf*) ext="mxf" ;;
    *mov*) ext="mov" ;;
    *mp4*) ext="mp4" ;;
  esac
  OUTPUT_FILE="${OUT_DIR}/${PRESET_ID}.out.${ext}"
else
  [[ "${OUTPUT_FILE}" != /* ]] && OUTPUT_FILE="${OUT_DIR}/${OUTPUT_FILE}"
fi

# Build image (unless --no-build)
if [[ "${NO_BUILD}" != "true" ]]; then
  echo "[build] docker build -t ${IMAGE_TAG} -f ${DOCKERFILE} ${BUILD_CONTEXT}"
  docker build -t "${IMAGE_TAG}" -f "${DOCKERFILE}" "${BUILD_CONTEXT}"
fi

# Node helper: render preset args -> one arg per line
RENDER_JS="${ROOT_DIR}/_render_ffmpeg_args.cjs"
cat > "${RENDER_JS}" <<'JS'
const fs = require("fs");

const presetId = process.env.PRESET_ID;
const IN = process.env.IN;
const OUT = process.env.OUT;

const presets = JSON.parse(fs.readFileSync("/work/presets.json", "utf8"));

function findPreset(p) {
  if (Array.isArray(p)) return p.find(x => (x?.id || x?.key || x?.name) === presetId) || null;
  if (p && typeof p === "object") {
    if (p[presetId]) return p[presetId];
    for (const k of Object.keys(p)) {
      const v = p[k];
      if (v && typeof v === "object" && (v.id || v.key || v.name) === presetId) return v;
    }
  }
  return null;
}

function replaceStr(s) {
  return String(s)
    .replaceAll("{input}", IN).replaceAll("{output}", OUT)
    .replaceAll("$IN", IN).replaceAll("$OUT", OUT)
    .replaceAll("$INPUT", IN).replaceAll("$OUTPUT", OUT)
    .replaceAll("__INPUT__", IN).replaceAll("__OUTPUT__", OUT);
}

// Minimal shell-like splitter for command strings
function splitShell(str) {
  const out = [];
  let cur = "";
  let q = null;
  for (let i = 0; i < str.length; i++) {
    const ch = str[i];
    if (q) {
      if (ch === q) { q = null; continue; }
      if (ch === "\\" && q === '"' && i + 1 < str.length) { cur += str[++i]; continue; }
      cur += ch;
      continue;
    }
    if (ch === "'" || ch === '"') { q = ch; continue; }
    if (ch === "\\") { if (i + 1 < str.length) cur += str[++i]; continue; }
    if (/\s/.test(ch)) { if (cur) { out.push(cur); cur = ""; } continue; }
    cur += ch;
  }
  if (cur) out.push(cur);
  return out;
}

const pr = findPreset(presets);
if (!pr) { console.error("Preset not found:", presetId); process.exit(2); }

const fields = ["ffmpegArgs","args","command","ffmpeg","cmd"];
let args = null;
for (const f of fields) { if (pr[f] != null) { args = pr[f]; break; } }
if (args == null) { console.error("No ffmpeg args field found. Keys:", Object.keys(pr)); process.exit(3); }

let argv;
if (Array.isArray(args)) {
  argv = args.map(replaceStr);
  if (argv[0] === "ffmpeg") argv = argv.slice(1);
} else if (typeof args === "string") {
  argv = splitShell(replaceStr(args.trim()));
  if (argv[0] === "ffmpeg") argv = argv.slice(1);
} else {
  console.error("Unsupported args type:", typeof args);
  process.exit(4);
}

for (const a of argv) process.stdout.write(a + "\n");
JS

CONTAINER_NAME="ffmpeg-debug-${PRESET_ID}-$$"

echo "[run] preset=${PRESET_ID}"
echo "[run] input=${IN_DIR}/${INPUT_BASENAME}"
echo "[run] output=${OUTPUT_FILE}"
echo "[run] logs=${LOG_DIR}/${PRESET_ID}.ffmpeg.log"

docker run --rm --name "${CONTAINER_NAME}" \
  -v "${ROOT_DIR}:/work" -w /work \
  -e PRESET_ID="${PRESET_ID}" \
  -e IN="/work/in/${INPUT_BASENAME}" \
  -e OUT="/work/out/$(basename "${OUTPUT_FILE}")" \
  -e TIMECODE="${TIMECODE}" \
  -e CREATION_TIME="${CREATION_TIME}" \
  -e FFMPEG_TIMEOUT="${FFMPEG_TIMEOUT}" \
  "${IMAGE_TAG}" bash -lc '
set -euo pipefail

echo "[container] ffmpeg=$(ffmpeg -version | head -n 1)"
mkdir -p /work/logs /work/out

# probe input
ffprobe -hide_banner -v error \
  -show_entries format:stream=index,codec_type,codec_name,channels,channel_layout:stream_tags=timecode \
  -of json "$IN" > "/work/logs/${PRESET_ID}.ffprobe.input.json" || true

# render args
node /work/_render_ffmpeg_args.cjs > "/work/logs/${PRESET_ID}.args.txt"
mapfile -t ARGS < "/work/logs/${PRESET_ID}.args.txt"

# replace placeholders
for i in "${!ARGS[@]}"; do
  ARGS[$i]="${ARGS[$i]//\{\{TIMECODE\}\}/$TIMECODE}"
  ARGS[$i]="${ARGS[$i]//\{\{CREATION_TIME\}\}/$CREATION_TIME}"
done

# detect if preset already contains -i and/or an output path
HAS_I=0
for a in "${ARGS[@]}"; do [[ "$a" == "-i" ]] && HAS_I=1; done

HAS_OUT=0
for a in "${ARGS[@]}"; do [[ "$a" == "$OUT" ]] && HAS_OUT=1; done

# build final command as an array (no eval)
CMD=(ffmpeg -hide_banner -y -loglevel debug)
if [[ "$HAS_I" -eq 0 ]]; then
  CMD+=(-i "$IN")
fi
CMD+=("${ARGS[@]}")
if [[ "$HAS_OUT" -eq 0 ]]; then
  CMD+=("$OUT")
fi

# write printable cmd.txt
{
  for i in "${!CMD[@]}"; do printf "%q " "${CMD[$i]}"; done
  echo
} > "/work/logs/${PRESET_ID}.cmd.txt"

echo "[container] RUN: $(cat /work/logs/${PRESET_ID}.cmd.txt)" | tee "/work/logs/${PRESET_ID}.run.txt"
echo "[container] OUT=$OUT" | tee -a "/work/logs/${PRESET_ID}.run.txt"
[[ -n "${FFMPEG_TIMEOUT:-}" ]] && echo "[container] timeout=${FFMPEG_TIMEOUT}s" | tee -a "/work/logs/${PRESET_ID}.run.txt"

# execute
if [[ -n "${FFMPEG_TIMEOUT:-}" ]]; then
  timeout "${FFMPEG_TIMEOUT}s" "${CMD[@]}" > "/work/logs/${PRESET_ID}.ffmpeg.log" 2>&1 || true
else
  "${CMD[@]}" > "/work/logs/${PRESET_ID}.ffmpeg.log" 2>&1 || true
fi

# probe output if created
if [[ -f "$OUT" ]]; then
  ffprobe -hide_banner -v error \
    -show_entries format:stream=index,codec_type,codec_name,channels,channel_layout:stream_tags=timecode \
    -of json "$OUT" > "/work/logs/${PRESET_ID}.ffprobe.output.json" || true
fi

echo "[container] Done. Logs in /work/logs, output in /work/out"
'

echo
echo "DONE."
echo "  Output: ${OUT_DIR}/$(basename "${OUTPUT_FILE}")"
echo "  Cmd:    ${LOG_DIR}/${PRESET_ID}.cmd.txt"
echo "  Log:    ${LOG_DIR}/${PRESET_ID}.ffmpeg.log"
echo "  Probe:  ${LOG_DIR}/${PRESET_ID}.ffprobe.input.json"
