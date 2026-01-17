from __future__ import annotations

from typing import Any


def labels_from_tokenizer(tokenizer: Any) -> list[str]:
    vocab = tokenizer.get_vocab()
    if not vocab:
        raise ValueError("Tokenizer vocab is empty")

    max_id = max(vocab.values())
    labels: list[str | None] = [None] * (max_id + 1)

    for token, token_id in vocab.items():
        if token_id < 0 or token_id > max_id:
            raise ValueError(f"Invalid token id: {token_id}")
        if labels[token_id] is not None:
            raise ValueError(f"Duplicate token id in vocab: {token_id}")
        labels[token_id] = token

    missing = [i for i, v in enumerate(labels) if v is None]
    if missing:
        raise ValueError(f"Tokenizer vocab missing ids: {missing[:10]}")

    return [v for v in labels if v is not None]


def build_kenlm_decoder(processor: Any, model: Any, kenlm_model_path: str):
    from pyctcdecode import build_ctcdecoder

    vocab_size = model.config.vocab_size
    all_labels = labels_from_tokenizer(processor.tokenizer)
    labels = all_labels[:vocab_size]

    if len(labels) != vocab_size:
        raise ValueError(
            f"Label count mismatch: model expects {vocab_size} but got {len(labels)}"
        )

    labels[0] = ""

    for i in range(1, len(labels)):
        piece = labels[i]
        if not piece.startswith("<") and not piece.endswith(">"):
            piece = "\u2581" + piece.replace("\u2581", "#")
        labels[i] = piece

    return build_ctcdecoder(labels=labels, kenlm_model_path=kenlm_model_path)
