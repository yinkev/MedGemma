# MedASR Clean Implementation (MedASR + 6gLM + MedGemma + Pocket-TTS)

## Goals
- Batch video transcription via Finder Quick Action: MedASR + 6gLM + timestamped .txt (primary), optional .vtt/.srt.
- Pseudo-live mode: mic/system-audio -> rolling transcript -> ask MedGemma -> speak via pocket-tts.
- Fully local on macOS.

## Constraints
- No Ollama / no hosted services.
- Prefer clean module boundaries over monolithic scripts.
- Segment-level timestamps are acceptable for v1; make word-level an optional future upgrade.

## Work Items
- [x] Verify Python runtime choice (3.14 vs 3.11) based on torch/transformers compatibility.
- [x] Implement ASR core that actually uses CTC logits + KenLM (pyctcdecode), with correct vocab ordering.
- [x] Implement segment timestamping (VAD-based) and outputs: .txt (default), .vtt/.srt (optional flags).
- [x] Batch CLI: transcribe files (audio/video) with deterministic outputs.
- [x] Finder Quick Action: ship a prebuilt .workflow + installer script.
- [x] Pseudo-live mic mode: rolling transcription + hotkey-based question -> MedGemma answer.
- [x] Pocket-TTS integration: cached model/voice state + low-latency playback.
- [x] System audio capture: replace silent placeholder with real ScreenCaptureKit audio capture.
- [x] Verification: end-to-end demos + smoke tests.
