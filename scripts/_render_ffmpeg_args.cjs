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
