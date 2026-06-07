#!/usr/bin/env bash
# Transcribe voice samples for Phase-6 parser tuning.
#
# Usage:
#   1. Drop recordings (any format ffmpeg reads) into Samples/raw/
#   2. ./Scripts/transcribe-samples.sh
#
# Converts each clip to 16 kHz mono WAV (Samples/wav/) and prints an on-device
# whisper.cpp transcript. The clips themselves live under Samples/ which is
# gitignored — they are a minor's private voice data and must not be committed.
set -euo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
MODEL="${WHISPER_MODEL:-$ROOT/Samples/ggml-small.en.bin}"

# Locate the whisper.cpp CLI (brew installs it as whisper-cli; older as 'whisper-cpp').
WHISPER_BIN="$(command -v whisper-cli || command -v whisper-cpp || true)"
if [[ -z "$WHISPER_BIN" ]]; then
  echo "whisper.cpp not found. Install: brew install whisper-cpp" >&2
  exit 1
fi
if [[ ! -f "$MODEL" ]]; then
  echo "Model not found at $MODEL" >&2
  echo "Download: curl -L -o '$MODEL' https://huggingface.co/ggerganov/whisper.cpp/resolve/main/ggml-small.en.bin" >&2
  exit 1
fi

mkdir -p "$ROOT/Samples/wav"
shopt -s nullglob
found=0
for raw in "$ROOT"/Samples/raw/*; do
  found=1
  base="$(basename "${raw%.*}")"
  wav="$ROOT/Samples/wav/$base.wav"
  ffmpeg -y -loglevel error -i "$raw" -ar 16000 -ac 1 -c:a pcm_s16le "$wav"
  echo "──────────────────────────────────────────────"
  echo "▶ $base"
  "$WHISPER_BIN" -m "$MODEL" -f "$wav" -nt -l en 2>/dev/null | sed 's/^[[:space:]]*//'
done
[[ $found -eq 1 ]] || { echo "No files in Samples/raw/"; exit 1; }
echo "──────────────────────────────────────────────"
