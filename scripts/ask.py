#!/usr/bin/env python3
"""
MedGemma Q&A Script

Ask questions about transcript content using MedGemma 1.5 4B.

Usage:
    python ask.py transcript.txt                    # Interactive chat mode
    python ask.py transcript.txt "what drugs?"      # Single question mode
    python ask.py transcript.txt -c 1000            # Use last 1000 words as context
"""

import argparse
import sys
from pathlib import Path

import torch
import yaml
from transformers import AutoModelForCausalLM, AutoTokenizer

# Add parent directory to path
SCRIPT_DIR = Path(__file__).parent
PROJECT_DIR = SCRIPT_DIR.parent


def load_config() -> dict:
    """Load configuration from config.yaml."""
    config_path = PROJECT_DIR / "config.yaml"
    if config_path.exists():
        with open(config_path) as f:
            return yaml.safe_load(f)
    return {
        "models": {"medgemma": "google/medgemma-1.5-4b-it"},
        "qa": {"context_words": 2000},
    }


def load_transcript(path: str, max_words: int = 2000) -> str:
    """Load transcript and optionally truncate to last N words."""
    with open(path) as f:
        content = f.read()

    # Remove timestamps if present
    lines = content.strip().split("\n")
    text_lines = []
    for line in lines:
        # Remove [HH:MM:SS] prefix if present
        if line.startswith("[") and "]" in line:
            line = line[line.index("]") + 1:].strip()
        text_lines.append(line)

    full_text = " ".join(text_lines)

    # Truncate to last max_words words
    words = full_text.split()
    if len(words) > max_words:
        words = words[-max_words:]
        truncated_text = " ".join(words)
        return f"[...truncated to last {max_words} words...]\n\n{truncated_text}"

    return full_text


class MedGemmaQA:
    def __init__(self, model_name: str):
        print(f"Loading MedGemma model: {model_name}")
        print("This may take a moment...")

        self.tokenizer = AutoTokenizer.from_pretrained(model_name)
        self.model = AutoModelForCausalLM.from_pretrained(
            model_name,
            torch_dtype=torch.bfloat16 if torch.cuda.is_available() else torch.float32,
            device_map="auto",
        )

        # Determine device
        if torch.cuda.is_available():
            self.device = "cuda"
        elif torch.backends.mps.is_available():
            self.device = "mps"
        else:
            self.device = "cpu"

        print(f"Model loaded on: {self.device}")

    def ask(self, transcript: str, question: str) -> str:
        """Ask a question about the transcript."""
        # Build prompt
        system_prompt = """You are a helpful medical education assistant.
You are given a transcript from a medical lecture and must answer questions about it.
Base your answers only on the information in the transcript.
If the transcript doesn't contain the answer, say so clearly."""

        user_prompt = f"""Here is the transcript:

{transcript}

---

Question: {question}"""

        # Format for chat model
        messages = [
            {"role": "user", "content": f"{system_prompt}\n\n{user_prompt}"},
        ]

        # Tokenize
        input_ids = self.tokenizer.apply_chat_template(
            messages,
            add_generation_prompt=True,
            return_tensors="pt",
        ).to(self.model.device)

        # Generate
        with torch.no_grad():
            outputs = self.model.generate(
                input_ids,
                max_new_tokens=512,
                do_sample=True,
                temperature=0.7,
                top_p=0.9,
                pad_token_id=self.tokenizer.eos_token_id,
            )

        # Decode response (skip input tokens)
        response = self.tokenizer.decode(
            outputs[0][input_ids.shape[1]:],
            skip_special_tokens=True,
        )

        return response.strip()


def run_chat_mode(qa: MedGemmaQA, transcript: str):
    """Interactive chat mode."""
    print("\n=== MedGemma Q&A Chat ===")
    print("Type your questions about the transcript.")
    print("Type 'quit' or 'exit' to end.\n")

    while True:
        try:
            question = input("\nYou: ").strip()
            if not question:
                continue
            if question.lower() in ("quit", "exit", "q"):
                print("Goodbye!")
                break

            print("\nMedGemma: ", end="", flush=True)
            answer = qa.ask(transcript, question)
            print(answer)

        except KeyboardInterrupt:
            print("\n\nGoodbye!")
            break
        except EOFError:
            print("\n\nGoodbye!")
            break


def main():
    parser = argparse.ArgumentParser(
        description="Ask questions about transcript content using MedGemma"
    )
    parser.add_argument("transcript", help="Path to transcript file")
    parser.add_argument(
        "question",
        nargs="?",
        help="Single question to ask (optional, enters chat mode if not provided)",
    )
    parser.add_argument(
        "-c", "--context-words",
        type=int,
        help="Maximum number of words to use as context (default: from config)",
    )
    args = parser.parse_args()

    # Validate transcript file
    transcript_path = Path(args.transcript)
    if not transcript_path.exists():
        print(f"Error: Transcript file not found: {args.transcript}")
        sys.exit(1)

    # Load config
    config = load_config()
    context_words = args.context_words or config["qa"]["context_words"]

    # Load transcript
    print(f"Loading transcript: {args.transcript}")
    transcript = load_transcript(str(transcript_path), max_words=context_words)
    word_count = len(transcript.split())
    print(f"Transcript loaded ({word_count} words)")

    # Initialize QA model
    model_name = config["models"]["medgemma"]
    qa = MedGemmaQA(model_name)

    # Run mode
    if args.question:
        # Single question mode
        print(f"\nQuestion: {args.question}")
        print("\nMedGemma: ", end="", flush=True)
        answer = qa.ask(transcript, args.question)
        print(answer)
    else:
        # Chat mode
        run_chat_mode(qa, transcript)


if __name__ == "__main__":
    main()
