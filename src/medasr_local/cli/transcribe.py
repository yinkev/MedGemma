from __future__ import annotations

import argparse
import os
import tempfile
from pathlib import Path

from medasr_local.asr.decode import transcribe_segments
from medasr_local.asr.io import extract_to_wav, read_wav, vad_segments
from medasr_local.asr.lm import build_kenlm_decoder
from medasr_local.asr.model import load_asr
from medasr_local.formats.writers import write_json, write_srt, write_txt, write_vtt


def _base_output(input_path: Path, output: str | None) -> Path:
    if output is None:
        return input_path.parent / f"{input_path.stem}_medasr"
    out = Path(output)
    if out.is_dir():
        return out / f"{input_path.stem}_medasr"
    return out.with_suffix("")


def _transcribe_one(
    input_path: Path,
    model_name: str,
    kenlm_path: Path,
    use_lm: bool,
    txt: bool,
    json_out: bool,
    vtt: bool,
    srt: bool,
    output: str | None,
) -> None:
    tmp_wav: Path | None = None
    try:
        tmp_wav = extract_to_wav(input_path)
        audio = read_wav(tmp_wav)
        if audio.sample_rate != 16000:
            raise RuntimeError(f"Expected 16kHz audio, got {audio.sample_rate}")

        segments_idx = vad_segments(audio.samples, audio.sample_rate)
        if not segments_idx:
            segments_idx = [(0, len(audio.samples))]

        bundle = load_asr(model_name)

        decoder = None
        if use_lm:
            decoder = build_kenlm_decoder(
                bundle.processor, bundle.model, str(kenlm_path)
            )

        segments = transcribe_segments(
            audio.samples,
            audio.sample_rate,
            segments_idx,
            bundle,
            decoder,
        )

        base = _base_output(input_path, output)

        if json_out:
            write_json(segments, base.with_suffix(".json"))
        if txt:
            write_txt(segments, base.with_suffix(".txt"))
        if vtt:
            write_vtt(segments, base.with_suffix(".vtt"))
        if srt:
            write_srt(segments, base.with_suffix(".srt"))

    finally:
        if tmp_wav is not None and tmp_wav.exists():
            try:
                os.remove(tmp_wav)
            except OSError:
                pass


def main() -> None:
    parser = argparse.ArgumentParser()
    parser.add_argument("input", nargs="+", help="Audio/video file(s)")
    parser.add_argument("-o", "--output", help="Output base file or directory")
    parser.add_argument("--no-lm", action="store_true")
    parser.add_argument("--txt", action="store_true")
    parser.add_argument("--json", action="store_true")
    parser.add_argument("--vtt", action="store_true")
    parser.add_argument("--srt", action="store_true")
    args = parser.parse_args()

    project = Path(__file__).resolve().parents[3]
    config_path = project / "config.yaml"

    model_name = "google/medasr"
    kenlm_path = project / "models" / "lm_6.kenlm"

    if config_path.exists():
        import yaml

        cfg = yaml.safe_load(config_path.read_text())
        model_name = cfg.get("models", {}).get("medasr", model_name)
        lm_rel = cfg.get("models", {}).get("lm_path", "models/lm_6.kenlm")
        kenlm_path = project / lm_rel

    txt = True if not (args.json or args.vtt or args.srt or args.txt) else args.txt
    json_out = args.json
    vtt = args.vtt
    srt = args.srt

    for p in args.input:
        input_path = Path(p)
        if not input_path.exists():
            raise SystemExit(f"File not found: {p}")
        _transcribe_one(
            input_path,
            model_name=model_name,
            kenlm_path=kenlm_path,
            use_lm=(not args.no_lm),
            txt=txt,
            json_out=json_out,
            vtt=vtt,
            srt=srt,
            output=args.output,
        )


if __name__ == "__main__":
    main()
