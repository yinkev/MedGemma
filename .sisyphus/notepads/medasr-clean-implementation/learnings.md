## Learnings

### 2026-01-17 - MedASR Clean Implementation

#### Python Runtime Strategy
- **Decision**: Dual-venv approach (.venv py3.11 + .venv314 py3.14)
- **Reason**: kenlm incompatible with CPython 3.14; pyctcdecode requires numpy<2; pocket-tts requires numpy>=2
- **Implementation**: Wrapper scripts in bin/ select correct venv automatically

#### CTC + KenLM Decoding
- **Critical Bug Fixed**: Legacy code used model.generate() which bypasses KenLM decoder entirely
- **Correct Pattern**: Extract logits via model(**inputs).logits, then decode with pyctcdecode decoder.decode(logits[0].cpu().numpy())
- **Vocab Ordering**: MUST sort tokenizer vocab by token ID before build_ctcdecoder(), not dict keys order
- **MedASR Decoder Invariants (Important)**:
  - The model config uses vocab_size=512, but the tokenizer vocab is larger; labels must be trimmed to vocab_size.
  - pyctcdecode expects the CTC blank label to be "" (empty string); MedASR uses <epsilon> at token id 0.
  - SentencePiece normalization for LM decoding: prefix each non-special token with "▁" and replace internal "▁" with "#".
  - Post-processing: remove spurious spaces, replace "#" with spaces, strip "</s>", map {period}/{comma}/{colon}/{new paragraph}.

#### Segment Timestamps
- **Approach**: VAD-based segmentation using RMS energy thresholds
- **Frame-to-Time**: seconds = frame_index / sample_rate
- **Output Formats**: TXT (default), JSON, VTT, SRT via separate writer functions

#### ScreenCaptureKit Audio Capture
- **Framework**: ScreenCaptureKit (macOS 14.4+)
- **Pattern**: SCStream + SCStreamDelegate + SCStreamOutput for audio samples
- **Resampling**: AVAudioConverter to convert 48kHz stereo → 16kHz mono PCM int16
- **Permission**: Requires Screen Recording permission in System Settings

#### Pocket-TTS Integration
- **API**: TTSModel.load_model() + get_state_for_audio_prompt(voice) + generate_audio(state, text)
- **Sample Rate**: 24kHz (model.sample_rate attribute)
- **Playback**: Write to temp WAV, play with afplay subprocess

#### Quick Action Installation
- **Structure**: .workflow bundle with Info.plist + document.wflow
- **Installer**: Shell script generates bundle programmatically, installs to ~/Library/Services/
- **Activation**: Requires enabling in System Settings → Extensions → Finder

#### Module Organization
- **src/medasr_local/asr/**: model loading, LM setup, decoding, audio I/O + VAD
- **src/medasr_local/formats/**: timestamp formatters + output writers
- **src/medasr_local/qa/**: MedGemma wrapper with context truncation
- **src/medasr_local/tts/**: Pocket-TTS wrapper with caching
- **src/medasr_local/cli/**: Entrypoints (transcribe, ask, speak, assistant)

#### Live Assistant Architecture
- **Audio Thread**: sounddevice InputStream → queue → rolling buffer
- **Processing Thread**: Overlapped chunk extraction → ASR → question detection → QA → TTS
- **Question Detection**: Heuristic (starts with what/how/why/etc or ends with ?)
- **Context Window**: Last 50 transcript segments for QA context

#### MedGemma 1.5 (Vision vs Current Integration)
- The default model id `google/medgemma-1.5-4b-it` is vision-capable (image-text-to-text), but current wrappers use text-only prompts via AutoModelForCausalLM + AutoTokenizer.
- A future upgrade can add an on-demand screenshot capture path and pass images through an AutoProcessor to MedGemma.
