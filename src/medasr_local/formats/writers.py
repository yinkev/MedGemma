from __future__ import annotations

import json
from pathlib import Path

from medasr_local.formats.timestamps import Segment, hms, srt_ts, vtt_ts


def write_json(segments: list[Segment], path: Path) -> None:
    payload = {
        "segments": [
            {"start": s.start_s, "end": s.end_s, "text": s.text}
            for s in segments
            if s.text
        ]
    }
    path.write_text(json.dumps(payload, indent=2) + "\n")


def write_txt(segments: list[Segment], path: Path) -> None:
    lines = [f"[{hms(s.start_s)}] {s.text}" for s in segments if s.text]
    path.write_text("\n".join(lines) + ("\n" if lines else ""))


def write_vtt(segments: list[Segment], path: Path) -> None:
    lines: list[str] = ["WEBVTT", ""]
    for s in segments:
        if not s.text:
            continue
        lines.append(f"{vtt_ts(s.start_s)} --> {vtt_ts(s.end_s)}")
        lines.append(s.text)
        lines.append("")
    path.write_text("\n".join(lines).rstrip() + "\n")


def write_srt(segments: list[Segment], path: Path) -> None:
    lines: list[str] = []
    idx = 1
    for s in segments:
        if not s.text:
            continue
        lines.append(str(idx))
        lines.append(f"{srt_ts(s.start_s)} --> {srt_ts(s.end_s)}")
        lines.append(s.text)
        lines.append("")
        idx += 1
    path.write_text("\n".join(lines).rstrip() + "\n")
