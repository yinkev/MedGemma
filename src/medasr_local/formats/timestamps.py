from __future__ import annotations

from dataclasses import dataclass


@dataclass(frozen=True)
class Segment:
    start_s: float
    end_s: float
    text: str


def hms(seconds: float) -> str:
    whole = int(seconds)
    hours = whole // 3600
    minutes = (whole % 3600) // 60
    secs = whole % 60
    return f"{hours:02d}:{minutes:02d}:{secs:02d}"


def vtt_ts(seconds: float) -> str:
    ms_total = int(round(seconds * 1000.0))
    hours = ms_total // 3_600_000
    minutes = (ms_total % 3_600_000) // 60_000
    secs = (ms_total % 60_000) // 1000
    ms = ms_total % 1000
    return f"{hours:02d}:{minutes:02d}:{secs:02d}.{ms:03d}"


def srt_ts(seconds: float) -> str:
    ms_total = int(round(seconds * 1000.0))
    hours = ms_total // 3_600_000
    minutes = (ms_total % 3_600_000) // 60_000
    secs = (ms_total % 60_000) // 1000
    ms = ms_total % 1000
    return f"{hours:02d}:{minutes:02d}:{secs:02d},{ms:03d}"
