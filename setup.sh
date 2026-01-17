#!/bin/bash
# MedASR Setup Script
# Installs dependencies, downloads models, and compiles Swift helper

set -e

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
cd "$SCRIPT_DIR"

echo "=== MedASR Setup ==="
echo ""

# Check prerequisites
echo "Checking prerequisites..."

if ! command -v python3 &> /dev/null; then
    echo "Error: Python 3 is required. Install with: brew install python@3.11"
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

# Check HuggingFace authentication
echo ""
echo "Checking HuggingFace authentication..."
echo "Note: MedASR and MedGemma are gated models requiring:"
echo "  1. Accept license at https://huggingface.co/google/medasr"
echo "  2. Accept license at https://huggingface.co/google/medgemma-1.5-4b-it"
echo "  3. Login with: huggingface-cli login"
echo ""

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
uv pip --python .venv/bin/python install torch torchaudio scipy tqdm sounddevice pyyaml pyctcdecode kenlm accelerate
uv pip --python .venv/bin/python install git+https://github.com/huggingface/transformers.git@65dc261512cbdb1ee72b88ae5b222f2605aad8e5

echo ""
echo "Installing QA/TTS dependencies (Python 3.14)..."
uv pip --python .venv314/bin/python install torch transformers accelerate pyyaml scipy pocket-tts

source .venv/bin/activate

# Download MedASR model (caches in HuggingFace cache)
echo ""
echo "Pre-downloading MedASR model..."
python3 -c "
from transformers import AutoProcessor, AutoModelForCTC
print('Downloading google/medasr model...')
processor = AutoProcessor.from_pretrained('google/medasr')
model = AutoModelForCTC.from_pretrained('google/medasr')
print('MedASR model downloaded successfully!')
"

# Download 6-gram language model
echo ""
echo "Downloading 6-gram language model..."
LM_PATH="models/lm_6.kenlm"
if [ ! -f "$LM_PATH" ]; then
    python3 -c "
from huggingface_hub import hf_hub_download
print('Downloading 6-gram LM from HuggingFace...')
lm_file = hf_hub_download(
    repo_id='google/medasr',
    filename='lm_6.kenlm',
    local_dir='models',
    local_dir_use_symlinks=False
)
print('Language model saved to: models/lm_6.kenlm')
"
else
    echo "Language model already exists at $LM_PATH"
fi

# Download MedGemma tokenizer only (model downloads on first use of ask.py)
echo ""
echo "Pre-downloading MedGemma tokenizer..."
python3 -c "
from transformers import AutoTokenizer
print('Downloading google/medgemma-1.5-4b-it tokenizer...')
tokenizer = AutoTokenizer.from_pretrained('google/medgemma-1.5-4b-it')
print('MedGemma tokenizer downloaded. Model will download on first use of ask.py')
"

# Compile Swift audio capture helper
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

# Create transcripts directory
mkdir -p transcripts

echo ""
echo "=== Setup Complete ==="
echo ""
echo "Usage:"
echo "  File transcription:  python scripts/transcribe.py <audio_or_video_file>"
echo "  Live transcription:  python scripts/live_transcribe.py"
echo "  Q&A on transcript:   python scripts/ask.py <transcript.txt>"
echo ""
echo "For Quick Action, install the workflow from the workflows/ folder."
