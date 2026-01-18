from __future__ import annotations

import argparse
import json
import sys
from pathlib import Path

from medasr_local.qa.medgemma_multimodal import MedGemmaMultimodal, load_images


_TUTOR_SYSTEM = """You are a radiology learning companion.

You will tutor the user using Socratic questions based on the provided medical image.
Rules:
- Ask one question at a time.
- Prefer multiple-choice questions with 4 options (A-D).
- If the user answers, give feedback and a short explanation.
- Do not reveal the final diagnosis unless the user asks to reveal.
- Keep the conversation educational and concise.
"""


def _history_text(history: list[tuple[str, str, str]]) -> str:
    if not history:
        return ""
    lines: list[str] = []
    for idx, (question, user_answer, feedback) in enumerate(history[-6:], start=1):
        lines.append(f"Q{idx}: {question}")
        lines.append(f"A{idx}: {user_answer}")
        lines.append(f"F{idx}: {feedback}")
        lines.append("")
    return "\n".join(lines).strip()


def _tutor_next_prompt(topic: str | None, history: list[tuple[str, str, str]]) -> str:
    intro = (
        f"Generate the next teaching question about: {topic}"
        if topic
        else "Generate the next teaching question about the image."
    )

    prev = _history_text(history)
    if not prev:
        return intro

    return (
        intro
        + "\n\n"
        + "Session so far:\n"
        + prev
        + "\n\n"
        + "Now ask the next question."
    )


def _grade_prompt(question: str, user_answer: str) -> str:
    return (
        "Given the image and the question, evaluate the user's answer. "
        "Respond with: Verdict: <Correct/Partially correct/Incorrect>\n"
        "Feedback: <one paragraph>\n"
        "Key points: <3 bullets>\n\n"
        f"Question: {question}\n"
        f"User answer: {user_answer}"
    )


def _reveal_prompt(history: list[tuple[str, str, str]]) -> str:
    prev = _history_text(history)
    if prev:
        prev = "\n\nSession so far:\n" + prev

    return (
        "Reveal your best-effort interpretation and likely diagnosis for the image. "
        "Be explicit about uncertainty and limitations. Keep it concise." + prev
    )


def _generate_one(mm: MedGemmaMultimodal, imgs, prompt: str, max_tokens: int) -> str:
    content = [{"type": "image"} for _ in range(len(imgs))] + [
        {"type": "text", "text": prompt}
    ]
    messages = [
        {"role": "system", "content": _TUTOR_SYSTEM},
        {"role": "user", "content": content},
    ]
    return mm.generate(messages=messages, images=imgs, max_new_tokens=max_tokens)


def interactive_session(
    mm: MedGemmaMultimodal, imgs, topic: str | None, max_tokens: int
) -> None:
    history: list[tuple[str, str, str]] = []

    print("Type your answer and press Enter.")
    print("Commands: /reveal, /skip, /quit")
    print("")

    while True:
        q = _generate_one(
            mm, imgs, _tutor_next_prompt(topic, history), max_tokens=max_tokens
        )
        print("Question:")
        print(q)
        print("")

        user_answer = sys.stdin.readline()
        if not user_answer:
            break
        user_answer = user_answer.strip()

        if user_answer == "/quit":
            break
        if user_answer == "/skip":
            history.append((q, "(skipped)", ""))
            print("")
            continue
        if user_answer == "/reveal":
            reveal = _generate_one(
                mm, imgs, _reveal_prompt(history), max_tokens=max_tokens
            )
            print("Reveal:")
            print(reveal)
            print("")
            break

        feedback = _generate_one(
            mm, imgs, _grade_prompt(q, user_answer), max_tokens=max_tokens
        )
        history.append((q, user_answer, feedback))

        print("Feedback:")
        print(feedback)
        print("")


def main() -> None:
    parser = argparse.ArgumentParser(
        description="Radiology learning companion using local MedGemma."
    )
    parser.add_argument("image", type=Path, help="Path to an image file (e.g., CXR).")
    parser.add_argument("--model", default="models/medgemma")
    parser.add_argument("--max-tokens", type=int, default=256)
    parser.add_argument(
        "--topic", default=None, help="Optional topic focus (e.g., pneumothorax)."
    )
    parser.add_argument(
        "--json", action="store_true", help="Emit JSON output (one question only)."
    )
    parser.add_argument(
        "--interactive",
        action="store_true",
        help="Run an interactive tutoring session.",
    )
    args = parser.parse_args()

    if not args.image.exists():
        raise SystemExit(f"Image not found: {args.image}")

    mm = MedGemmaMultimodal(model_name=args.model)
    imgs = load_images(args.image, max_tiles=1)

    if args.interactive:
        interactive_session(mm, imgs, topic=args.topic, max_tokens=args.max_tokens)
        return

    prompt = _tutor_next_prompt(args.topic, history=[])
    question = _generate_one(mm, imgs, prompt, max_tokens=args.max_tokens)

    if args.json:
        print(
            json.dumps(
                {"image": str(args.image), "question": question}, ensure_ascii=False
            )
        )
        return

    print(question)


if __name__ == "__main__":
    main()
