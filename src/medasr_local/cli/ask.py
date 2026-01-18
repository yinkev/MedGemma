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
    parser.add_argument("--max-tokens", type=int, default=256)
    args = parser.parse_args()

    transcript_path = Path(args.transcript)
    if not transcript_path.exists():
        raise SystemExit(f"Transcript not found: {args.transcript}")

    context = load_transcript_text(transcript_path, max_words=args.context_words)
    word_count = len(context.split())

    print(f"Loaded transcript ({word_count} words)")
    print("Loading MedGemma...")

    model_name = "models/medgemma"
    config_path = Path(__file__).resolve().parents[3] / "config.yaml"
    if config_path.exists():
        try:
            import yaml

            cfg = yaml.safe_load(config_path.read_text())
            model_name = cfg.get("models", {}).get("medgemma", model_name)
        except Exception:
            pass

    project = Path(__file__).resolve().parents[3]
    if (project / model_name).exists():
        model_name = str((project / model_name).resolve())

    if not Path(model_name).exists():
        raise SystemExit(
            "MedGemma model not found locally. Run: .venv314/bin/python scripts/materialize_medgemma_model.py --out models/medgemma"
        )

    qa = MedGemma(model_name=model_name)

    if args.question:
        print(f"\nQuestion: {args.question}")
        print("\nMedGemma: ", end="", flush=True)
        answer = qa.ask(context, args.question, max_tokens=args.max_tokens)
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
                answer = qa.ask(context, question, max_tokens=args.max_tokens)
                print(answer)

            except (KeyboardInterrupt, EOFError):
                print("\n\nGoodbye!")
                break


if __name__ == "__main__":
    main()
