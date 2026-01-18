from __future__ import annotations

from dataclasses import dataclass
from pathlib import Path
import re

import torch


@dataclass(frozen=True)
class MedGemmaConfig:
    model_name: str
    device: str
    dtype: torch.dtype


_UNUSED_TOKEN_RE = re.compile(r"<unused\d+>")


def _clean_response(text: str) -> str:
    raw = _UNUSED_TOKEN_RE.sub("", text).strip()
    if not raw:
        return ""

    if raw.lower().startswith("thought"):
        lines = raw.splitlines()[1:]
        cleaned_lines: list[str] = []
        for line in lines:
            if re.match(r"^\s*(\d+\.|[-*])\s+", line):
                continue
            cleaned_lines.append(line)
        cleaned = "\n".join(cleaned_lines).strip()
        if cleaned:
            return cleaned

    return raw


def pick_device_dtype() -> tuple[str, torch.dtype]:
    if torch.cuda.is_available():
        return ("cuda", torch.bfloat16)
    if torch.backends.mps.is_available():
        return ("mps", torch.float32)
    return ("cpu", torch.float32)


class MedGemma:
    def __init__(self, model_name: str = "models/medgemma"):
        from transformers import AutoModelForCausalLM, AutoTokenizer

        device, dtype = pick_device_dtype()

        self.tokenizer = AutoTokenizer.from_pretrained(
            model_name, local_files_only=True
        )
        self.model = AutoModelForCausalLM.from_pretrained(
            model_name,
            torch_dtype=dtype,
            device_map="auto",
            local_files_only=True,
        )
        self.device = device
        self.dtype = dtype

    def ask(self, context: str, question: str, max_tokens: int = 512) -> str:
        system = (
            "You are a helpful medical education assistant. "
            "Answer questions based only on the provided context. "
            "If the context doesn't contain the answer, say so clearly. "
            "Output only a single line in the format: Answer: <text>. "
            "Do not include reasoning or analysis."
        )

        user_prompt = f"Context:\n\n{context}\n\n---\n\nQuestion: {question}"

        prompt = f"{system}\n\n{user_prompt}\n\nAnswer:"
        inputs = self.tokenizer(prompt, return_tensors="pt")
        input_ids = inputs["input_ids"].to(self.model.device)
        attention_mask = inputs.get("attention_mask")
        if attention_mask is not None:
            attention_mask = attention_mask.to(self.model.device)

        with torch.no_grad():
            outputs = self.model.generate(
                input_ids,
                attention_mask=attention_mask,
                max_new_tokens=max_tokens,
                do_sample=False,
                eos_token_id=self.tokenizer.eos_token_id,
                pad_token_id=self.tokenizer.eos_token_id,
            )

        response = self.tokenizer.decode(
            outputs[0][input_ids.shape[1] :],
            skip_special_tokens=True,
        )

        cleaned = _clean_response(response)
        return cleaned.strip() if cleaned else response.strip()


def load_transcript_text(path: Path, max_words: int | None = None) -> str:
    lines = path.read_text().strip().split("\n")
    text_lines = []

    for line in lines:
        if line.startswith("[") and "]" in line:
            line = line[line.index("]") + 1 :].strip()
        text_lines.append(line)

    full_text = " ".join(text_lines)

    if max_words is not None:
        words = full_text.split()
        if len(words) > max_words:
            words = words[-max_words:]
            return " ".join(words)

    return full_text
