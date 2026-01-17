#!/usr/bin/env python3
"""
Convert MedASR JSON output to timestamped TXT format.

Usage:
    python json_to_txt.py <input.json> [output.txt]
"""

import argparse
import json
import sys
from pathlib import Path


def format_timestamp(seconds: float) -> str:
    """Format seconds as HH:MM:SS."""
    hours = int(seconds // 3600)
    minutes = int((seconds % 3600) // 60)
    secs = int(seconds % 60)
    return f"{hours:02d}:{minutes:02d}:{secs:02d}"


def convert_json_to_txt(json_path: str, txt_path: str) -> None:
    """Convert JSON transcript to timestamped TXT."""
    with open(json_path) as f:
        data = json.load(f)

    segments = data.get("segments", [])

    with open(txt_path, "w") as f:
        for seg in segments:
            start = seg.get("start", 0)
            text = seg.get("text", "").strip()
            if text:
                timestamp = format_timestamp(start)
                f.write(f"[{timestamp}] {text}\n")

    print(f"Converted {len(segments)} segments to: {txt_path}")


def main():
    parser = argparse.ArgumentParser(
        description="Convert MedASR JSON to timestamped TXT"
    )
    parser.add_argument("input_json", help="Input JSON file")
    parser.add_argument(
        "output_txt",
        nargs="?",
        help="Output TXT file (default: same name with .txt extension)",
    )
    args = parser.parse_args()

    input_path = Path(args.input_json)
    if not input_path.exists():
        print(f"Error: File not found: {args.input_json}")
        sys.exit(1)

    if args.output_txt:
        output_path = args.output_txt
    else:
        output_path = str(input_path.with_suffix(".txt"))

    convert_json_to_txt(str(input_path), output_path)


if __name__ == "__main__":
    main()
