from __future__ import annotations

import argparse
import os
import subprocess
from pathlib import Path

from medasr_local.tts.pocket import synth_to_temp_wav


def main() -> None:
    parser = argparse.ArgumentParser()
    parser.add_argument("text", nargs="+", help="Text to speak")
    parser.add_argument("--voice", default="alba")
    parser.add_argument("--no-play", action="store_true")
    parser.add_argument("--out", help="Write wav to this path")
    args = parser.parse_args()

    text = " ".join(args.text).strip()
    if not text:
        raise SystemExit(2)

    tmp_wav: Path | None = None
    try:
        tmp_wav, _ = synth_to_temp_wav(text=text, voice=args.voice)

        if args.out:
            out = Path(args.out)
            out.write_bytes(tmp_wav.read_bytes())

        if not args.no_play:
            subprocess.run(["afplay", str(tmp_wav)], check=False)

    finally:
        if tmp_wav is not None and tmp_wav.exists():
            try:
                os.remove(tmp_wav)
            except OSError:
                pass


if __name__ == "__main__":
    main()
