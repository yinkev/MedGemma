from __future__ import annotations

import argparse
from pathlib import Path

from medasr_local.qa.medgemma import MedGemma, load_transcript_text


def main() -> None:
    parser = argparse.ArgumentParser()
    parser.add_argument("transcript", help="Transcript file path")
    parser.add_argument(
        "question", nargs="?", help="Question (optional, enters chat mode if omitted)"
    )
    parser.add_argument("-c", "--context-words", type=int, default=2000)
    args = parser.parse_args()

    transcript_path = Path(args.transcript)
    if not transcript_path.exists():
        raise SystemExit(f"Transcript not found: {args.transcript}")

    context = load_transcript_text(transcript_path, max_words=args.context_words)
    word_count = len(context.split())

    print(f"Loaded transcript ({word_count} words)")
    print("Loading MedGemma...")

    qa = MedGemma()

    if args.question:
        print(f"\nQuestion: {args.question}")
        print("\nMedGemma: ", end="", flush=True)
        answer = qa.ask(context, args.question)
        print(answer)
    else:
        print("\n=== MedGemma Q&A Chat ===")
        print("Type your questions. Type 'quit' or 'exit' to end.\n")

        while True:
            try:
                question = input("\nYou: ").strip()
                if not question:
                    continue
                if question.lower() in ("quit", "exit", "q"):
                    print("Goodbye!")
                    break

                print("\nMedGemma: ", end="", flush=True)
                answer = qa.ask(context, question)
                print(answer)

            except (KeyboardInterrupt, EOFError):
                print("\n\nGoodbye!")
                break


if __name__ == "__main__":
    main()
