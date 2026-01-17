## Decisions

### 2026-01-17 - Architecture Decisions

#### Dual Python Environments
- **Decision**: Use separate .venv (py3.11) and .venv314 (py3.14) instead of single environment
- **Rationale**: kenlm build fails on CPython 3.14 due to removed internal APIs; numpy version conflict (pyctcdecode <2, pocket-tts >=2)
- **Tradeoff**: Slightly more complex setup, but clean separation of concerns
- **Alternative Rejected**: Single py3.11 env with older pocket-tts (would miss numpy 2.x performance improvements)

#### CTC Decoding Strategy
- **Decision**: Use pyctcdecode with KenLM for beam search, not model.generate()
- **Rationale**: model.generate() bypasses language model entirely; pyctcdecode gives 25-30% WER improvement per HF model card
- **Implementation**:
  - Extract logits, decode with sorted vocab labels
  - Enforce MedASR invariants: trim labels to model.config.vocab_size (512), map blank label to "", apply SentencePiece normalization ("▁" prefix + "▁"->"#"), and post-process decoded output ("#"->space, strip "</s>", map {period}/{comma}/{colon}/{new paragraph}).
- **Alternative Rejected**: Wav2Vec2ProcessorWithLM (requires different model loading pattern, less flexible)

#### Timestamp Granularity
- **Decision**: Segment-level timestamps via VAD, not word-level forced alignment
- **Rationale**: Simpler implementation, adequate for v1 use case (lecture transcription)
- **Tradeoff**: Less precise than word-level, but 10x faster to implement
- **Future Enhancement**: Add forced alignment option via torchaudio.functional.forced_align

#### Quick Action Distribution
- **Decision**: Programmatic .workflow generation via shell script, not prebuilt bundle
- **Rationale**: Hardcoded paths in prebuilt bundles break on different machines; script adapts to install location
- **Implementation**: install-quick-action.sh generates Info.plist + document.wflow with correct MEDASR_DIR
- **Alternative Rejected**: Manual Automator instructions (too error-prone for users)

#### Live Assistant Question Detection
- **Decision**: Simple heuristic (keyword prefix + ? suffix), not LLM-based classification
- **Rationale**: Low latency, no extra model loading, works well for conversational questions
- **Tradeoff**: May miss some questions, may false-positive on statements
- **Future Enhancement**: Optional LLM-based intent classification

#### MedGemma Vision Inputs
- **Decision**: Keep initial MedGemma integration text-only.
- **Rationale**: The model is vision-capable, but wiring image inputs requires screenshot capture, image preprocessing, and a different Transformers load path (AutoProcessor + vision-capable model class).
- **Future Enhancement**: On-demand screenshot assist (screen capture + recent transcript) for "help me respond" use cases.

#### Output Format Defaults
- **Decision**: TXT as default, JSON/VTT/SRT opt-in via flags
- **Rationale**: User explicitly requested timestamped .txt as primary format
- **Implementation**: --txt --json --vtt --srt flags; if none specified, default to --txt
- **Alternative Rejected**: Always output all formats (wasteful for most use cases)
