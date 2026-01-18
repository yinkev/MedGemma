from __future__ import annotations

import argparse
import json
import sys

from medasr_local.qa.medgemma import MedGemma


def main() -> None:
    parser = argparse.ArgumentParser()
    parser.add_argument("--model", default="models/medgemma")
    parser.add_argument("--max-tokens", type=int, default=256)
    args = parser.parse_args()

    raw = sys.stdin.read()
    if not raw.strip():
        raise SystemExit(2)

    payload = json.loads(raw)
    context = str(payload.get("context", ""))
    question = str(payload.get("question", ""))

    if not question.strip():
        raise SystemExit(2)

    qa = MedGemma(model_name=args.model)
    answer = qa.ask(context, question, max_tokens=args.max_tokens)
    print(answer)


if __name__ == "__main__":
    main()
