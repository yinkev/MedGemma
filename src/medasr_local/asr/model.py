from __future__ import annotations

from dataclasses import dataclass

import torch
from transformers import AutoModelForCTC, AutoProcessor


@dataclass(frozen=True)
class AsrBundle:
    model: torch.nn.Module
    processor: object
    device: str


def pick_device(explicit: str | None) -> str:
    if explicit:
        return explicit
    if torch.cuda.is_available():
        return "cuda"
    if torch.backends.mps.is_available():
        return "mps"
    return "cpu"


def load_asr(model_name: str, device: str | None = None) -> AsrBundle:
    kwargs = {"local_files_only": True}
    processor = AutoProcessor.from_pretrained(model_name, **kwargs)
    model = AutoModelForCTC.from_pretrained(model_name, **kwargs)

    chosen = pick_device(device)
    model = model.to(chosen)
    model.eval()

    return AsrBundle(model=model, processor=processor, device=chosen)
