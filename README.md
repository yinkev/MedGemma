# MedASR Local

**Fully-local medical transcription + Q&A assistant** powered by MedASR, MedGemma 1.5, and Pocket-TTS.

## Features

- **Batch Transcription**: Right-click any audio/video file → timestamped transcript (.txt, .json, .vtt, .srt)
- **Live Assistant**: Speak questions → MedGemma answers → Pocket-TTS speaks back
- **Q&A Mode**: Ask questions about transcripts using MedGemma 1.5 (vision-capable model; current CLI uses text-only prompts)
- **Fully Local**: No cloud APIs, no Ollama, runs entirely on your Mac

## Architecture

```
┌─────────────────────────────────────────────────────────────────┐
│                         MedASR Local                             │
├─────────────────────────────────────────────────────────────────┤
│                                                                  │
│  ┌──────────────┐  ┌──────────────┐  ┌──────────────┐          │
│  │   Batch      │  │    Live      │  │     Q&A      │          │
│  │ Transcribe   │  │  Assistant   │  │     Mode     │          │
│  └──────┬───────┘  └──────┬───────┘  └──────┬───────┘          │
│         │                 │                  │                  │
│         └─────────────────┼──────────────────┘                  │
│                           │                                     │
│  ┌────────────────────────┴────────────────────────┐            │
│  │           Core Pipeline Components              │            │
│  ├──────────────────────────────────────────────────┤            │
│  │                                                  │            │
│  │  ┌─────────────┐  ┌─────────────┐  ┌──────────┐ │            │
│  │  │   MedASR    │  │  MedGemma   │  │  Pocket  │ │            │
│  │  │  + 6gLM     │  │    1.5      │  │   TTS    │ │            │
│  │  │  (CTC+KenLM)│  │  (4B-it)    │  │ (100M)   │ │            │
│  │  └─────────────┘  └─────────────┘  └──────────┘ │            │
│  │                                                  │            │
│  │  Python 3.11      Python 3.14     Python 3.14   │            │
│  │  (.venv)          (.venv314)      (.venv314)    │            │
│  └──────────────────────────────────────────────────┘            │
│                                                                  │
│  ┌──────────────────────────────────────────────────┐            │
│  │           Native macOS Components                │            │
│  ├──────────────────────────────────────────────────┤            │
│  │                                                  │            │
│  │  • ScreenCaptureKit audio capture (Swift)       │            │
│  │  • Finder Quick Action (.workflow)              │            │
│  │  • afplay audio playback                        │            │
│  │                                                  │            │
│  └──────────────────────────────────────────────────┘            │
│                                                                  │
└─────────────────────────────────────────────────────────────────┘
```

## Directory Structure

```
MedASR/
├── bin/                          # User-facing executables
│   ├── medasr-transcribe         # Batch transcription
│   ├── medasr-ask                # Q&A mode
│   ├── medasr-speak              # TTS test
│   └── medasr-assistant          # Live assistant
│
├── src/medasr_local/             # Core library (959 LOC)
│   ├── asr/                      # Speech recognition
│   │   ├── model.py              # Load MedASR model
│   │   ├── lm.py                 # KenLM decoder setup
│   │   ├── decode.py             # CTC+LM decoding
│   │   └── io.py                 # Audio I/O + VAD
│   ├── formats/                  # Output formats
│   │   ├── timestamps.py         # Segment dataclass + formatters
│   │   └── writers.py            # TXT/JSON/VTT/SRT writers
│   ├── qa/                       # Question answering
│   │   └── medgemma.py           # MedGemma 1.5 wrapper
│   ├── tts/                      # Text-to-speech
│   │   └── pocket.py             # Pocket-TTS wrapper
│   └── cli/                      # CLI entrypoints
│       ├── transcribe.py         # Batch transcription
│       ├── ask.py                # Q&A mode
│       ├── speak.py              # TTS test
│       └── assistant.py          # Live assistant
│
├── native/                       # macOS native code
│   ├── AudioCapture.swift        # ScreenCaptureKit audio tap
│   └── audiocapture              # Compiled binary (87KB)
│
├── workflows/                    # macOS automation
│   ├── install-quick-action.sh   # Quick Action installer
│   └── Install-Quick-Action.md   # Manual instructions
│
├── models/                       # Downloaded models
│   └── lm_6.kenlm                # 6-gram language model (704MB)
│
├── .venv/                        # Python 3.11 (ASR runtime)
│   └── ...                       # torch, pyctcdecode, kenlm
│
├── .venv314/                     # Python 3.14 (QA/TTS runtime)
│   └── ...                       # transformers, pocket-tts
│
├── config.yaml                   # Model paths + settings
├── setup.sh                      # One-command setup
└── README.md                     # This file
```

## Installation

### Prerequisites

- macOS 14.4+ (for ScreenCaptureKit system audio)
- Python 3.11 and 3.14
- [uv](https://github.com/astral-sh/uv) package manager
- Xcode Command Line Tools (`xcode-select --install`)
- ffmpeg (`brew install ffmpeg`)

### Setup

```bash
./setup.sh
```

This will:
1. Create dual Python environments (.venv + .venv314)
2. Install dependencies (torch, transformers, pyctcdecode, kenlm, pocket-tts)
3. Download MedASR model + 6gLM (~1.5GB)
4. Download MedGemma tokenizer
5. Compile native audio capture helper

### Install Finder Quick Action

```bash
./workflows/install-quick-action.sh
```

Then enable in **System Settings → Extensions → Finder → MedASR Transcribe**.

## Usage

### 1. Batch Transcription

**Via Finder Quick Action:**
1. Right-click any audio/video file
2. Select **Quick Actions → MedASR Transcribe**
3. Wait for notification
4. Find `filename_medasr.txt` in same folder

**Via CLI:**

```bash
# Default: timestamped .txt
bin/medasr-transcribe lecture.mp4

# Multiple formats
bin/medasr-transcribe lecture.mp4 --txt --json --vtt --srt

# Custom output location
bin/medasr-transcribe lecture.mp4 -o ~/Desktop/transcript

# Disable language model (faster, less accurate)
bin/medasr-transcribe lecture.mp4 --no-lm
```

**Output formats:**
- `.txt`: Timestamped transcript `[HH:MM:SS] text`
- `.json`: Structured segments with start/end times
- `.vtt`: WebVTT subtitles (video players)
- `.srt`: SubRip subtitles (video players)

### 2. Q&A Mode

Ask questions about a transcript using MedGemma 1.5.

Note: `src/medasr_local/qa/medgemma.py` currently uses text-only prompts (no image inputs wired yet).

```bash
# Single question
bin/medasr-ask lecture_medasr.txt "What is the mechanism of action?"

# Interactive chat mode
bin/medasr-ask lecture_medasr.txt
```

### 3. Live Assistant

Chunked live voice assistant with question detection (not true streaming captions):

```bash
bin/medasr-assistant
```

- Speak naturally into your mic
- Questions are auto-detected (starts with what/how/why/etc or ends with ?)
- MedGemma answers based on recent context
- Pocket-TTS speaks the answer
- Press Ctrl+C to stop

**Options:**
```bash
bin/medasr-assistant --no-lm          # Faster ASR (less accurate)
bin/medasr-assistant --voice alba     # Change TTS voice
bin/medasr-assistant --chunk-s 3.0    # Shorter ASR chunks (more responsive)
```

### 4. TTS Test

Test Pocket-TTS voices:

```bash
bin/medasr-speak "Hello world"
bin/medasr-speak "This is a test" --voice alba
bin/medasr-speak "Save to file" --out test.wav --no-play
```

## Technical Details

### Dual Python Environments

This project uses **two separate Python environments** due to dependency conflicts:

| Environment | Python | Purpose | Key Deps |
|-------------|--------|---------|----------|
| `.venv` | 3.11 | ASR (MedASR + KenLM) | pyctcdecode, kenlm, numpy<2 |
| `.venv314` | 3.14 | QA + TTS (MedGemma + Pocket-TTS) | transformers, pocket-tts, numpy>=2 |

**Why?**
- `kenlm` Python package is not compatible with CPython 3.14
- `pyctcdecode` requires `numpy<2`
- `pocket-tts` requires `numpy>=2`

The `bin/medasr-*` wrapper scripts automatically select the correct environment.

### CTC + KenLM Decoding

**Previous implementation (WRONG):**
```python
outputs = model.generate(**inputs)
text = processor.batch_decode(outputs)
```

**New implementation (CORRECT):**
```python
logits = model(**inputs).logits
text = lm_decoder.decode(logits[0].cpu().numpy())
text = restore_text(text)
```

MedASR-specific decoder invariants (easy to break):
- Decoder label list must match `model.config.vocab_size` (MedASR config uses 512; tokenizer vocab is larger)
- CTC blank token must be `""` (MedASR tokenizer uses `<epsilon>` at id 0)
- SentencePiece normalization for pyctcdecode: prefix each non-special token with `\u2581` and replace internal `\u2581` with `#`
- Post-process decoded output: remove spurious spaces, replace `#` with real spaces, strip `</s>`, and map `{period}/{comma}/{colon}/{new paragraph}`

The 6-gram language model improves medical terminology accuracy by 25-30% (per HuggingFace model card).

### Segment Timestamps

Timestamps are generated via:
1. **VAD (Voice Activity Detection)**: Detect speech segments using RMS energy
2. **CTC Alignment**: Map logits frames to segment boundaries
3. **Time Conversion**: `seconds = frame_index / sample_rate`

**Not word-level** (future enhancement would use forced alignment).

### System Audio Capture

`native/AudioCapture.swift` uses **ScreenCaptureKit** (macOS 14.4+) to capture system audio:

- Captures at 48kHz stereo
- Resamples to 16kHz mono via AVAudioConverter
- Outputs PCM int16 to stdout
- Requires **Screen Recording permission** (System Settings → Privacy & Security)

**Alternative:** Use [BlackHole](https://github.com/ExistentialAudio/BlackHole) virtual audio device for older macOS versions.

## Configuration

Edit `config.yaml` to customize:

```yaml
models:
  medasr: google/medasr
  medgemma: google/medgemma-1.5-4b-it
  lm_path: models/lm_6.kenlm

transcription:
  chunk_length_s: 30
  stride_length_s: 5
  use_lm: true

live:
  use_lm: false
  chunk_length_s: 5

qa:
  context_words: 2000
```

## Troubleshooting

### Quick Action doesn't appear

1. Check **System Settings → Extensions → Finder**
2. Enable **MedASR Transcribe**
3. Restart Finder: `killall Finder`

### System audio capture fails

1. Grant **Screen Recording** permission:
   - System Settings → Privacy & Security → Screen Recording
   - Enable Terminal (or your terminal app)
2. Verify macOS version: `sw_vers` (need 14.4+)
3. Test manually: `native/audiocapture | head -c 1000 | xxd`

### Import errors

```bash
# Verify environments
.venv/bin/python -c "import pyctcdecode, kenlm; print('ASR OK')"
.venv314/bin/python -c "import pocket_tts; print('TTS OK')"
```

### Out of memory

- Reduce `chunk_length_s` in config.yaml
- Use `--no-lm` flag for faster/lighter processing
- Close other applications

## Roadmap (Not Implemented Yet)

- True streaming captions (stable prefix + editable tail) for mic and system audio
- On-demand assist mode: generate short reply suggestions from recent transcript context
- On-demand screen context: capture a screenshot and include it as an image input to MedGemma 1.5
- Optional diarization for multi-speaker audio

## Performance

**Batch Transcription:**
- ~2-3x real-time on M1 Mac (30min lecture → 10-15min)
- With LM: +30% accuracy, +20% slower
- Memory: ~4GB peak

**Live Assistant:**
- Latency: 2-5 seconds (ASR + QA + TTS)
- Memory: ~6GB (all models loaded)
- CPU-only on M-series Macs (MPS for MedGemma)

## License

This project integrates:
- **MedASR**: Apache 2.0 (Google)
- **MedGemma**: Gemma Terms of Use (Google)
- **Pocket-TTS**: CC-BY-4.0 (Kyutai)

See individual model cards for details.

## Credits

- **MedASR**: [google/medasr](https://huggingface.co/google/medasr)
- **MedGemma**: [google/medgemma-1.5-4b-it](https://huggingface.co/google/medgemma-1.5-4b-it)
- **Pocket-TTS**: [kyutai/pocket-tts](https://huggingface.co/kyutai/pocket-tts)
- **pyctcdecode**: [kensho-technologies/pyctcdecode](https://github.com/kensho-technologies/pyctcdecode)

## Contributing

This is a personal project. Feel free to fork and adapt for your needs.

## Support

For issues with:
- **MedASR model**: See [HuggingFace model card](https://huggingface.co/google/medasr)
- **MedGemma model**: See [HuggingFace model card](https://huggingface.co/google/medgemma-1.5-4b-it)
- **Pocket-TTS**: See [GitHub repo](https://github.com/kyutai-labs/pocket-tts)
- **This integration**: Open an issue on GitHub
# MedGemma
