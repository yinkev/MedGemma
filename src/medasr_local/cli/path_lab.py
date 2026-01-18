from __future__ import annotations

import argparse
import json
from pathlib import Path

from medasr_local.qa.medgemma_multimodal import MedGemmaMultimodal, load_images


_PATH_PROMPT = """You are MedGemma 1.5, a helpful medical imaging assistant.

Task: Given the provided pathology image, produce a structured, cautious interpretation.

Requirements:
- Use headings exactly: Findings, Impression, Differential, Confidence, Next steps.
- Be explicit about uncertainty and image limitations.
- Do not invent clinical history.
- Keep it concise.
"""


def main() -> None:
    parser = argparse.ArgumentParser(
        description="Pathology-style image interpretation using local MedGemma."
    )
    parser.add_argument(
        "image", type=Path, help="Path to an image file (jpg/png/tiff)."
    )
    parser.add_argument("--model", default="models/medgemma")
    parser.add_argument("--max-tokens", type=int, default=512)
    parser.add_argument(
        "--question", default="Describe the key morphology and likely diagnosis."
    )
    parser.add_argument("--json", action="store_true", help="Emit JSON output.")
    args = parser.parse_args()

    if not args.image.exists():
        raise SystemExit(f"Image not found: {args.image}")

    mm = MedGemmaMultimodal(model_name=args.model)
    imgs = load_images(args.image, max_tiles=4)
    content = [{"type": "image"} for _ in range(len(imgs))] + [
        {"type": "text", "text": args.question}
    ]

    messages = [
        {"role": "system", "content": _PATH_PROMPT},
        {
            "role": "user",
            "content": content,
        },
    ]

    text = mm.generate(messages=messages, images=imgs, max_new_tokens=args.max_tokens)

    if args.json:
        print(
            json.dumps(
                {
                    "image": str(args.image),
                    "question": args.question,
                    "answer": text,
                },
                ensure_ascii=False,
            )
        )
    else:
        print(text)


if __name__ == "__main__":
    main()
