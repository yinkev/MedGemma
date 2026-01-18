#!/bin/bash

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
cd "$SCRIPT_DIR"

echo "=== MedASR Setup ==="
echo ""

echo "Checking prerequisites..."

if ! command -v python3 &> /dev/null; then
    echo "Error: Python 3 is required."
    exit 1
fi

if ! command -v ffmpeg &> /dev/null; then
    echo "Error: ffmpeg is required. Install with: brew install ffmpeg"
    exit 1
fi

if ! command -v uv &> /dev/null; then
    echo "Installing uv package manager..."
    curl -LsSf https://astral.sh/uv/install.sh | sh
    export PATH="$HOME/.local/bin:$PATH"
fi

echo ""
echo "Gated models: accept license + auth once to download."

echo ""
echo "Creating virtual environments..."

if [ ! -d ".venv" ]; then
    uv venv .venv --python 3.11
fi

if [ ! -d ".venv314" ]; then
    uv venv .venv314 --python 3.14
fi

echo ""
echo "Installing ASR dependencies (Python 3.11)..."
( source .venv/bin/activate; uv pip install torch torchaudio scipy tqdm sounddevice pyyaml pyctcdecode kenlm accelerate )
( source .venv/bin/activate; uv pip install git+https://github.com/huggingface/transformers.git@65dc261512cbdb1ee72b88ae5b222f2605aad8e5 )

echo ""
echo "Installing QA/TTS dependencies (Python 3.14)..."
( source .venv314/bin/activate; uv pip install torch transformers accelerate pyyaml scipy pocket-tts protobuf sentencepiece )

if [ ! -d "models/medasr" ]; then
  echo ""
  echo "Pre-downloading MedASR model..."
  .venv/bin/python -c "
from transformers import AutoProcessor, AutoModelForCTC
print('Downloading google/medasr model...')
AutoProcessor.from_pretrained('google/medasr')
AutoModelForCTC.from_pretrained('google/medasr')
print('MedASR model downloaded successfully!')
"

  echo ""
  echo "Materializing MedASR model to models/medasr (no symlinks)..."
  .venv/bin/python scripts/materialize_medasr_model.py --out models/medasr
fi

echo ""
echo "Downloading 6-gram language model..."
LM_PATH="models/lm_6.kenlm"
if [ ! -f "$LM_PATH" ]; then
    .venv/bin/python -c "
from huggingface_hub import hf_hub_download
print('Downloading 6-gram LM from HuggingFace...')
hf_hub_download(
    repo_id='google/medasr',
    filename='lm_6.kenlm',
    local_dir='models',
    local_dir_use_symlinks=False,
)
print('Language model saved to: models/lm_6.kenlm')
"
else
    echo "Language model already exists at $LM_PATH"
fi

if [ ! -d "models/medgemma" ]; then
  echo ""
  echo "Pre-downloading MedGemma model..."
  .venv314/bin/python -c "
from transformers import AutoModelForCausalLM, AutoTokenizer
print('Downloading google/medgemma-1.5-4b-it model...')
AutoTokenizer.from_pretrained('google/medgemma-1.5-4b-it')
AutoModelForCausalLM.from_pretrained('google/medgemma-1.5-4b-it')
print('MedGemma model downloaded successfully!')
"

  echo ""
  echo "Materializing MedGemma model to models/medgemma (no symlinks)..."
  .venv314/bin/python scripts/materialize_medgemma_model.py --out models/medgemma
fi

echo ""
echo "Compiling Swift audio capture helper..."
if [ -f "native/AudioCapture.swift" ]; then
    swiftc -O -o native/audiocapture native/AudioCapture.swift \
        -framework CoreAudio \
        -framework AudioToolbox \
        -framework Foundation
    chmod +x native/audiocapture
    echo "Audio capture helper compiled successfully!"
else
    echo "Warning: native/AudioCapture.swift not found. System audio capture won't be available."
fi

mkdir -p transcripts

echo ""
echo "=== Setup Complete ==="
echo ""
echo "Usage:"
echo "  File transcription:  bin/medasr-transcribe <audio_or_video_file>"
echo "  Live assistant (mic): bin/medasr-assistant"
echo "  Q&A on transcript:   bin/medasr-ask <transcript.txt> \"<question>\""
echo "  Speak text:          bin/medasr-speak \"<text>\""
echo ""
echo "For Quick Action, install the workflow from the workflows/ folder."
