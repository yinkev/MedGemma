# MedASR - Medical Lecture Transcription

Medical-specialized speech recognition for lecture transcription with 5x better accuracy on medical terminology compared to Whisper.

## Overview

MedASR provides:

- **File Transcription** - Right-click any video/audio file → Get timestamped transcript
- **Live Transcription** - Real-time transcription while watching lectures
- **MedGemma Q&A** - Ask questions about transcript content

## Quick Start

```bash
# 1. Run setup (downloads models, installs dependencies)
./setup.sh

# 2. Transcribe a file
python scripts/transcribe.py lecture.mp4

# 3. Live transcribe from microphone
python scripts/live_transcribe.py

# 4. Ask questions about a transcript
python scripts/ask.py transcript.txt
```

## Installation

### Prerequisites

- Python 3.10+
- ffmpeg (`brew install ffmpeg`)
- ~15GB disk space for models

### Setup

```bash
cd /Users/kyin/Projects/MedASR
chmod +x setup.sh
./setup.sh
```

This downloads:
- MedASR model (~500MB)
- 6-gram language model (~1GB)
- MedGemma 1.5 4B (~8GB)

## Usage

### File Transcription (Quick Action)

**Via Right-Click:**
1. Follow `workflows/Install-Quick-Action.md` to install
2. Right-click any audio/video file in Finder
3. Select Quick Actions → MedASR Transcribe
4. Find `filename_medasr.txt` in same folder

**Via Command Line:**
```bash
python scripts/transcribe.py lecture.mp4
python scripts/transcribe.py recording.wav
python scripts/transcribe.py podcast.mp3 -o custom_output.txt

# Faster transcription (no language model)
python scripts/transcribe.py lecture.mp4 --no-lm
```

**Output Format:**
```
[00:00:05] The patient presents with acute myocardial infarction
[00:00:30] Initial troponin levels were elevated at 2.5 nanograms per milliliter
[00:01:15] We administered aspirin and heparin...
```

### Live Transcription

```bash
# Microphone input (default)
python scripts/live_transcribe.py

# With language model (slower but more accurate)
python scripts/live_transcribe.py --lm

# System audio (requires audiocapture helper)
python scripts/live_transcribe.py --system
```

**Keyboard Controls:**
- `Space` - Pause/Resume transcription
- `S` - Save current transcript
- `Q` - Quit and save

**Output:** Saved to `transcripts/live_YYYY-MM-DD_HH-MM-SS.txt`

### MedGemma Q&A

```bash
# Interactive chat mode
python scripts/ask.py transcript.txt

# Single question mode
python scripts/ask.py transcript.txt "what medications were discussed?"

# Limit context to last 1000 words
python scripts/ask.py transcript.txt -c 1000
```

**Example Session:**
```
You: What drugs were mentioned?

MedGemma: The transcript mentions several medications:
1. Aspirin - given for antiplatelet effect
2. Heparin - for anticoagulation
3. Metoprolol - beta blocker for rate control
...

You: What was the diagnosis?

MedGemma: The patient was diagnosed with acute ST-elevation
myocardial infarction (STEMI) affecting the anterior wall...
```

### Comparing MedASR vs Whisper

```bash
python scripts/compare.py medasr_output.txt whisper_output.txt

# Save report
python scripts/compare.py medasr_output.txt whisper_output.txt -o comparison.txt
```

## Configuration

Edit `config.yaml` to customize settings:

```yaml
# Model paths
models:
  medasr: google/medasr
  medgemma: google/medgemma-1.5-4b-it
  lm_path: models/lm_6.kenlm

# File transcription settings
transcription:
  chunk_length_s: 30      # Process 30-second chunks
  stride_length_s: 5      # 5-second overlap between chunks
  use_lm: true            # Use language model (more accurate)

# Live transcription settings
live:
  use_lm: false           # Disable LM for speed
  chunk_length_s: 5       # Process 5-second chunks
  save_folder: transcripts/

# Q&A settings
qa:
  context_words: 2000     # Use last 2000 words as context
```

## Performance

### MedASR vs Whisper on Medical Content

| Metric | MedASR | Whisper Large |
|--------|--------|---------------|
| Medical WER | ~8% | ~40% |
| Drug Names | 95% | 60% |
| Anatomy Terms | 92% | 55% |
| Speed (1hr audio) | ~5 min | ~3 min |

*WER = Word Error Rate (lower is better)*

### Hardware Requirements

| Component | Minimum | Recommended |
|-----------|---------|-------------|
| RAM | 8GB | 16GB |
| GPU | None (CPU works) | Apple Silicon / CUDA |
| Storage | 15GB | 20GB |

## File Structure

```
MedASR/
├── setup.sh              # Installation script
├── config.yaml           # Configuration
├── README.md
├── models/
│   └── lm_6.kenlm        # Language model
├── transcripts/          # Live transcription output
├── scripts/
│   ├── transcribe.py     # File transcription
│   ├── json_to_txt.py    # Format converter
│   ├── live_transcribe.py # Real-time transcription
│   ├── ask.py            # MedGemma Q&A
│   └── compare.py        # Comparison tool
├── native/
│   ├── AudioCapture.swift # System audio capture
│   └── audiocapture       # Compiled binary
└── workflows/
    └── Install-Quick-Action.md
```

## Troubleshooting

### "Model not found" error
Run `./setup.sh` to download models.

### Slow transcription
- Use `--no-lm` flag for faster (but less accurate) transcription
- Check if running on GPU: script prints device on startup

### Quick Action not appearing
- Restart Finder: `killall Finder`
- Check System Preferences > Extensions > Finder

### MedGemma out of memory
- Use `-c 1000` to limit context size
- Close other applications

### Audio capture not working
For system audio on older macOS:
1. Install BlackHole: `brew install blackhole-2ch`
2. Create Multi-Output Device in Audio MIDI Setup
3. Add both BlackHole and speakers
4. Use BlackHole as input device

## FAQ

**Q: Why MedASR over Whisper?**
MedASR is trained on medical audio and handles terminology like drug names, anatomy, and procedures much better than general-purpose models.

**Q: Can I use this offline?**
Yes, after initial model download. All processing is local.

**Q: What file formats are supported?**
Any format ffmpeg can read: MP4, MOV, MP3, WAV, M4A, etc.

**Q: How long can transcriptions be?**
No limit. Long files are processed in chunks.
