from __future__ import annotations

import subprocess
import tempfile
from dataclasses import dataclass
from pathlib import Path

import numpy as np
from scipy.io import wavfile


@dataclass(frozen=True)
class AudioData:
    sample_rate: int
    samples: np.ndarray


def extract_to_wav(input_path: Path) -> Path:
    tmp = tempfile.NamedTemporaryFile(suffix=".wav", delete=False)
    tmp_path = Path(tmp.name)
    tmp.close()

    cmd = [
        "ffmpeg",
        "-i",
        str(input_path),
        "-ar",
        "16000",
        "-ac",
        "1",
        "-f",
        "wav",
        "-y",
        str(tmp_path),
    ]
    subprocess.run(cmd, check=True, capture_output=True)
    return tmp_path


def read_wav(path: Path) -> AudioData:
    sample_rate, audio = wavfile.read(str(path))

    if audio.ndim > 1:
        audio = audio[:, 0]

    if audio.dtype == np.int16:
        samples = audio.astype(np.float32) / 32768.0
    elif audio.dtype == np.int32:
        samples = audio.astype(np.float32) / 2147483648.0
    elif audio.dtype == np.float32:
        samples = audio
    else:
        samples = audio.astype(np.float32)

    return AudioData(sample_rate=int(sample_rate), samples=samples)


def _frame_rms(samples: np.ndarray, frame_len: int) -> np.ndarray:
    if len(samples) < frame_len:
        return np.array([], dtype=np.float32)
    n = len(samples) // frame_len
    trimmed = samples[: n * frame_len]
    frames = trimmed.reshape(n, frame_len)
    return np.sqrt(np.mean(frames * frames, axis=1)).astype(np.float32)


def vad_segments(
    samples: np.ndarray,
    sample_rate: int,
    frame_ms: int = 30,
    rms_threshold: float = 0.012,
    min_speech_ms: int = 240,
    min_silence_ms: int = 450,
    max_segment_s: float = 18.0,
) -> list[tuple[int, int]]:
    frame_len = int(sample_rate * frame_ms / 1000)
    if frame_len <= 0:
        raise ValueError("frame_ms too small")

    rms = _frame_rms(samples, frame_len)
    if rms.size == 0:
        return []

    speech = rms >= rms_threshold

    min_speech_frames = max(1, int(min_speech_ms / frame_ms))
    min_silence_frames = max(1, int(min_silence_ms / frame_ms))
    max_segment_frames = max(1, int(max_segment_s * 1000 / frame_ms))

    segments: list[tuple[int, int]] = []

    i = 0
    n = len(speech)
    while i < n:
        while i < n and not speech[i]:
            i += 1
        if i >= n:
            break

        start = i
        silence = 0
        end = i

        while end < n:
            if speech[end]:
                silence = 0
            else:
                silence += 1
                if silence >= min_silence_frames:
                    break
            if (end - start) >= max_segment_frames:
                break
            end += 1

        seg_len = end - start
        if seg_len >= min_speech_frames:
            s = start * frame_len
            e = min(len(samples), end * frame_len)
            segments.append((s, e))

        i = end + 1

    merged: list[tuple[int, int]] = []
    for s, e in segments:
        if not merged:
            merged.append((s, e))
            continue
        ps, pe = merged[-1]
        gap = s - pe
        if gap <= int(0.15 * sample_rate):
            merged[-1] = (ps, max(pe, e))
        else:
            merged.append((s, e))

    return merged
