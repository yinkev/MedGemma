#!/bin/zsh
set -euo pipefail

MEDASR_DIR="$(cd "$(dirname "$0")/.." && pwd)"

pass() { print "[PASS] $1" }
info() { print "[INFO] $1" }
skip() { print "[SKIP] $1" }
fail() { print "[FAIL] $1"; exit 1 }

run_quiet() {
  local label="$1"; shift
  if "$@" >/dev/null 2>&1; then
    pass "$label"
  else
    fail "$label"
  fi
}

info "Repo: $MEDASR_DIR"

if [[ -d "$MEDASR_DIR/models/medasr" ]]; then
  if [[ -n "$(find "$MEDASR_DIR/models/medasr" -type l -print -quit 2>/dev/null)" ]]; then
    fail "models/medasr contains symlinks"
  fi
fi

if [[ -d "$MEDASR_DIR/models/medgemma" ]]; then
  if [[ -n "$(find "$MEDASR_DIR/models/medgemma" -type l -print -quit 2>/dev/null)" ]]; then
    fail "models/medgemma contains symlinks"
  fi
  if [[ ! -f "$MEDASR_DIR/models/medgemma/processor_config.json" ]]; then
    fail "models/medgemma missing processor_config.json"
  fi
  if [[ ! -f "$MEDASR_DIR/models/medgemma/preprocessor_config.json" ]]; then
    fail "models/medgemma missing preprocessor_config.json"
  fi
fi

if ! command -v python3 >/dev/null 2>&1; then
  fail "python3 not found"
fi

if python3 - "$MEDASR_DIR/src" <<'PY' >/dev/null 2>&1
import ast
import pathlib
import sys

root = pathlib.Path(sys.argv[1])
errors = 0
for path in sorted(root.rglob('*.py')):
    try:
        ast.parse(path.read_text(encoding='utf-8'))
    except Exception as e:
        errors += 1
        print(f"{path}: {e}", file=sys.stderr)

if errors:
    raise SystemExit(1)
PY
then
  pass "python parse src"
else
  fail "python parse src"
fi

if [[ -x "$MEDASR_DIR/.venv/bin/python" ]]; then
  run_quiet "medasr-transcribe --help" "$MEDASR_DIR/bin/medasr-transcribe" --help
  run_quiet "medasr-stream --help" "$MEDASR_DIR/bin/medasr-stream" --help
  run_quiet "medasr-assistant --help" "$MEDASR_DIR/bin/medasr-assistant" --help
else
  skip ".venv missing (skipping ASR runtime checks)"
fi

if [[ -x "$MEDASR_DIR/.venv314/bin/python" ]]; then
  run_quiet "medasr-ask --help" "$MEDASR_DIR/bin/medasr-ask" --help
  run_quiet "medasr-speak --help" "$MEDASR_DIR/bin/medasr-speak" --help
  run_quiet "medasr-mm-service --help" "$MEDASR_DIR/bin/medasr-mm-service" --help
  run_quiet "medasr-pathlab --help" "$MEDASR_DIR/bin/medasr-pathlab" --help
  run_quiet "medasr-radtutor --help" "$MEDASR_DIR/bin/medasr-radtutor" --help
else
  skip ".venv314 missing (skipping QA/TTS runtime checks)"
fi

if [[ "${MEDASR_SMOKE_E2E:-0}" != "1" ]]; then
  skip "Set MEDASR_SMOKE_E2E=1 to run end-to-end transcribe"
  info "Smoke test complete."
  exit 0
fi

if [[ ! -d "$MEDASR_DIR/models/medasr" ]]; then
  fail "models/medasr missing (run ./setup.sh first)"
fi
if ! command -v ffmpeg >/dev/null 2>&1; then
  fail "ffmpeg not found"
fi
if [[ ! -f "$MEDASR_DIR/test_audio.wav" ]]; then
  fail "test_audio.wav missing"
fi

tmpdir="$(mktemp -d -t medasr_smoke)"
cleanup() { rm -rf "$tmpdir" }
trap cleanup EXIT

info "Running end-to-end transcribe into: $tmpdir"

HF_HUB_OFFLINE=1 TRANSFORMERS_OFFLINE=1 \
  "$MEDASR_DIR/bin/medasr-transcribe" \
  --no-lm \
  --txt \
  -o "$tmpdir" \
  "$MEDASR_DIR/test_audio.wav" >/dev/null

out_txt="$tmpdir/test_audio_medasr.txt"
if [[ -s "$out_txt" ]]; then
  pass "end-to-end transcribe produced text"
else
  fail "end-to-end transcribe missing output: $out_txt"
fi

info "Smoke test complete."
