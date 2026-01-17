from __future__ import annotations

from dataclasses import dataclass
from pathlib import Path

import torch


@dataclass(frozen=True)
class MedGemmaConfig:
    model_name: str
    device: str
    dtype: torch.dtype


def pick_device_dtype() -> tuple[str, torch.dtype]:
    if torch.cuda.is_available():
        return ("cuda", torch.bfloat16)
    if torch.backends.mps.is_available():
        return ("mps", torch.float32)
    return ("cpu", torch.float32)


class MedGemma:
    def __init__(self, model_name: str = "google/medgemma-1.5-4b-it"):
        from transformers import AutoModelForCausalLM, AutoTokenizer

        device, dtype = pick_device_dtype()

        self.tokenizer = AutoTokenizer.from_pretrained(model_name)
        self.model = AutoModelForCausalLM.from_pretrained(
            model_name,
            torch_dtype=dtype,
            device_map="auto",
        )
        self.device = device
        self.dtype = dtype

    def ask(self, context: str, question: str, max_tokens: int = 512) -> str:
        system = (
            "You are a helpful medical education assistant. "
            "Answer questions based only on the provided context. "
            "If the context doesn't contain the answer, say so clearly."
        )

        user_prompt = f"Context:\n\n{context}\n\n---\n\nQuestion: {question}"

        messages = [{"role": "user", "content": f"{system}\n\n{user_prompt}"}]

        input_ids = self.tokenizer.apply_chat_template(
            messages,
            add_generation_prompt=True,
            return_tensors="pt",
        ).to(self.model.device)

        with torch.no_grad():
            outputs = self.model.generate(
                input_ids,
                max_new_tokens=max_tokens,
                do_sample=True,
                temperature=0.7,
                top_p=0.9,
                pad_token_id=self.tokenizer.eos_token_id,
            )

        response = self.tokenizer.decode(
            outputs[0][input_ids.shape[1] :],
            skip_special_tokens=True,
        )

        return response.strip()


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
