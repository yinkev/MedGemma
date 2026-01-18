from __future__ import annotations

from dataclasses import dataclass
from pathlib import Path
import math
import os

import torch

from medasr_local.qa.medgemma import _clean_response, pick_device_dtype


@dataclass(frozen=True)
class MedGemmaMultimodalConfig:
    model_name: str
    device: str
    dtype: torch.dtype


class MedGemmaMultimodal:
    def __init__(self, model_name: str = "models/medgemma"):
        from transformers import AutoProcessor, Gemma3ForConditionalGeneration

        os.environ.setdefault("TOKENIZERS_PARALLELISM", "false")
        os.environ.setdefault("HF_HUB_DISABLE_TELEMETRY", "1")
        os.environ.setdefault("TRANSFORMERS_VERBOSITY", "error")
        os.environ.setdefault("HF_HUB_OFFLINE", "1")
        os.environ.setdefault("TRANSFORMERS_OFFLINE", "1")

        device, dtype = pick_device_dtype()
        self.config = MedGemmaMultimodalConfig(
            model_name=model_name, device=device, dtype=dtype
        )

        self.processor = AutoProcessor.from_pretrained(
            model_name,
            local_files_only=True,
        )

        if device == "cuda":
            self.model = Gemma3ForConditionalGeneration.from_pretrained(
                model_name,
                torch_dtype=dtype,
                device_map="auto",
                local_files_only=True,
            )
        else:
            self.model = Gemma3ForConditionalGeneration.from_pretrained(
                model_name,
                torch_dtype=dtype,
                local_files_only=True,
            )
            self.model.to(device)

        self.model.eval()

    def _tokenizer_eos(self) -> int | None:
        tok = getattr(self.processor, "tokenizer", None)
        if tok is None:
            return None
        return getattr(tok, "eos_token_id", None)

    def generate(
        self,
        messages: list[dict],
        images: list[object],
        max_new_tokens: int = 512,
    ) -> str:
        prompt = self.processor.apply_chat_template(
            messages,
            add_generation_prompt=True,
            tokenize=False,
        )

        inputs = self.processor(
            text=prompt,
            images=images,
            return_tensors="pt",
            padding=True,
        )

        device = self.model.device
        for key, value in list(inputs.items()):
            if hasattr(value, "to"):
                inputs[key] = value.to(device)

        eos = self._tokenizer_eos()

        with torch.no_grad():
            outputs = self.model.generate(
                **inputs,
                max_new_tokens=max_new_tokens,
                do_sample=False,
                eos_token_id=eos,
                pad_token_id=eos,
            )

        if "input_ids" in inputs:
            generated = outputs[0][inputs["input_ids"].shape[1] :]
        else:
            generated = outputs[0]

        tokenizer = getattr(self.processor, "tokenizer", None)
        if tokenizer is None:
            raise RuntimeError("processor.tokenizer is missing")

        text = tokenizer.decode(generated, skip_special_tokens=True)
        cleaned = _clean_response(text)
        return cleaned.strip() if cleaned else text.strip()


def load_images(
    path: Path,
    *,
    max_tiles: int = 1,
    max_side_px: int = 2048,
) -> list[object]:
    from PIL import Image

    img = Image.open(path).convert("RGB")

    w, h = img.size
    max_side = max(w, h)
    if max_side > max_side_px and max_side_px > 0:
        scale = max_side_px / float(max_side)
        img = img.resize((int(w * scale), int(h * scale)))

    if max_tiles <= 1:
        return [img]

    grid = int(math.ceil(math.sqrt(max_tiles)))
    w, h = img.size

    tiles: list[object] = []
    for r in range(grid):
        for c in range(grid):
            if len(tiles) >= max_tiles:
                break
            left = int(c * w / grid)
            right = int((c + 1) * w / grid)
            top = int(r * h / grid)
            bottom = int((r + 1) * h / grid)
            tiles.append(img.crop((left, top, right, bottom)))
    return tiles
