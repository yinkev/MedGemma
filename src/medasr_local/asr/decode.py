from __future__ import annotations

from dataclasses import dataclass
from typing import Any

import numpy as np
import torch

from medasr_local.formats.timestamps import Segment


@dataclass(frozen=True)
class DecodeConfig:
    use_lm: bool


def _restore_text(text: str) -> str:
    text = text.replace(" ", "").replace("#", " ").replace("</s>", "").strip()
    text = text.replace("{period}", ".").replace("{comma}", ",")
    text = text.replace("{colon}", ":").replace("{new paragraph}", "\n\n")
    return text


def _decode_with_lm(decoder: Any, logits: np.ndarray) -> str:
    text = decoder.decode(logits)
    return _restore_text(text)


def _decode_greedy(processor: Any, logits: torch.Tensor) -> str:
    pred_ids = torch.argmax(logits, dim=-1)
    text = processor.batch_decode(pred_ids)[0]
    return _restore_text(text)


def transcribe_audio(
    audio: np.ndarray,
    sample_rate: int,
    bundle: Any,
    decoder: Any | None,
) -> str:
    processor = bundle.processor
    model = bundle.model
    device = bundle.device

    inputs = processor(
        audio,
        sampling_rate=sample_rate,
        return_tensors="pt",
        padding=True,
    ).to(device)

    with torch.no_grad():
        out = model(**inputs)
        logits = out.logits

    if decoder is not None:
        return _decode_with_lm(decoder, logits[0].detach().to("cpu").numpy())

    return _decode_greedy(processor, logits)


def transcribe_segments(
    samples: np.ndarray,
    sample_rate: int,
    segments: list[tuple[int, int]],
    bundle: Any,
    decoder: Any | None,
) -> list[Segment]:
    out: list[Segment] = []

    for s, e in segments:
        if e <= s:
            continue
        chunk = samples[s:e]
        if chunk.size < int(sample_rate * 0.15):
            continue
        text = transcribe_audio(chunk, sample_rate, bundle, decoder)
        if not text:
            continue
        out.append(Segment(start_s=s / sample_rate, end_s=e / sample_rate, text=text))

    return out
