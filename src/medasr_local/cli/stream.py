from __future__ import annotations

import argparse
import sys
import time
from pathlib import Path

import numpy as np

from medasr_local.asr.decode import transcribe_audio
from medasr_local.asr.model import load_asr
from medasr_local.cli.ipc import emit, emit_error, emit_status


def _iter_pcm16le_frames(stream, bytes_per_read: int):
    while True:
        chunk = stream.read(bytes_per_read)
        if not chunk:
            return
        if len(chunk) % 2 != 0:
            chunk = chunk[:-1]
        if not chunk:
            continue
        yield np.frombuffer(chunk, dtype=np.int16)


def main() -> None:
    parser = argparse.ArgumentParser()
    parser.add_argument(
        "--model",
        default="models/medasr",
        help="Model id or local path (default: models/medasr)",
    )
    parser.add_argument("--kenlm", default=None, help="KenLM path")
    parser.add_argument("--lm", action="store_true", help="Enable KenLM decoding")
    parser.add_argument("--no-lm", action="store_true", help="Disable KenLM decoding")
    parser.add_argument("--chunk-s", type=float, default=5.0)
    parser.add_argument(
        "--overlap",
        type=float,
        default=0.5,
        help="Chunk overlap fraction (0..0.9)",
    )
    parser.add_argument(
        "--sample-rate",
        type=int,
        default=16000,
        help="Input PCM sample rate (must match source)",
    )
    parser.add_argument(
        "--format",
        choices=["jsonl"],
        default="jsonl",
        help="Output format (stdout)",
    )
    args = parser.parse_args()

    if args.chunk_s <= 0:
        raise SystemExit("--chunk-s must be > 0")
    if not (0.0 <= args.overlap < 0.9):
        raise SystemExit("--overlap must be in [0, 0.9)")

    model_name = args.model
    model_path = Path(model_name)
    if model_path.exists():
        model_name = str(model_path.resolve())

    kenlm_path = Path(args.kenlm) if args.kenlm else Path("models/lm_6.kenlm")
    if kenlm_path.exists():
        kenlm_path = kenlm_path.resolve()

    use_lm = bool(args.lm and not args.no_lm)

    emit_status("loading_asr", model=model_name)
    try:
        bundle = load_asr(model_name)
    except Exception as e:
        emit_error(
            "model_load_failed",
            detail=str(e),
            hint="Expected a local model directory. If needed, run: .venv/bin/python scripts/materialize_medasr_model.py --out models/medasr",
        )
        raise SystemExit(2) from e

    decoder = None
    if use_lm:
        emit_status("loading_lm", kenlm=str(kenlm_path))
        try:
            from medasr_local.asr.lm import build_kenlm_decoder

            decoder = build_kenlm_decoder(
                bundle.processor, bundle.model, str(kenlm_path)
            )
        except ModuleNotFoundError as e:
            emit_error(
                "lm_dependencies_missing",
                detail="pyctcdecode+kenlm not available; install kenlm+pyctcdecode",
            )
            raise SystemExit(2) from e
        except Exception as e:
            emit_error("lm_load_failed", detail=str(e))
            raise SystemExit(2) from e

    sample_rate = int(args.sample_rate)
    chunk_samples = int(sample_rate * float(args.chunk_s))
    hop_samples = max(1, int(chunk_samples * (1.0 - float(args.overlap))))

    emit_status(
        "ready",
        sample_rate=sample_rate,
        chunk_s=float(args.chunk_s),
        overlap=float(args.overlap),
        use_lm=use_lm,
    )

    audio_buf = np.array([], dtype=np.float32)

    stdin = getattr(sys.stdin, "buffer", sys.stdin)
    bytes_per_read = sample_rate * 2

    last_emit_ts = 0.0
    for frame_i16 in _iter_pcm16le_frames(stdin, bytes_per_read=bytes_per_read):
        audio = frame_i16.astype(np.float32) / 32768.0
        audio_buf = np.concatenate([audio_buf, audio])

        while audio_buf.size >= chunk_samples:
            chunk = audio_buf[:chunk_samples]
            audio_buf = audio_buf[hop_samples:]

            t0 = time.perf_counter()
            try:
                text = transcribe_audio(chunk, sample_rate, bundle, decoder)
            except Exception as e:
                emit_error("transcribe_failed", detail=str(e))
                continue
            dt = time.perf_counter() - t0

            text = (text or "").strip()
            now = time.time()

            if text:
                emit(
                    {
                        "type": "asr",
                        "ts": now,
                        "text": text,
                        "chunk_s": float(args.chunk_s),
                        "rtf": float(dt) / float(args.chunk_s),
                    }
                )
            elif now - last_emit_ts > 2.0:
                emit_status("idle")
                last_emit_ts = now


if __name__ == "__main__":
    main()
