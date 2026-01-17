#!/usr/bin/env python3
"""
Compare MedASR vs Whisper transcription outputs.

Generates a side-by-side comparison report showing differences
and calculating word-level statistics.

Usage:
    python compare.py medasr.txt whisper.txt
    python compare.py medasr.txt whisper.txt -o comparison.txt
"""

import argparse
import difflib
import re
import sys
from pathlib import Path


def load_transcript(path: str) -> str:
    """Load transcript and strip timestamps."""
    with open(path) as f:
        content = f.read()

    # Remove timestamps [HH:MM:SS] if present
    lines = []
    for line in content.strip().split("\n"):
        # Remove timestamp prefix
        if line.startswith("[") and "]" in line:
            line = line[line.index("]") + 1:].strip()
        lines.append(line)

    return " ".join(lines)


def normalize_text(text: str) -> str:
    """Normalize text for comparison."""
    # Lowercase
    text = text.lower()
    # Remove extra whitespace
    text = " ".join(text.split())
    # Remove punctuation for word comparison
    text = re.sub(r"[^\w\s]", "", text)
    return text


def calculate_wer(reference: str, hypothesis: str) -> tuple[float, dict]:
    """Calculate Word Error Rate and statistics."""
    ref_words = normalize_text(reference).split()
    hyp_words = normalize_text(hypothesis).split()

    # Use difflib to find operations needed
    matcher = difflib.SequenceMatcher(None, ref_words, hyp_words)

    substitutions = 0
    insertions = 0
    deletions = 0

    for op, i1, i2, j1, j2 in matcher.get_opcodes():
        if op == "replace":
            substitutions += max(i2 - i1, j2 - j1)
        elif op == "insert":
            insertions += j2 - j1
        elif op == "delete":
            deletions += i2 - i1

    total_ref = len(ref_words)
    wer = (substitutions + insertions + deletions) / total_ref if total_ref > 0 else 0

    stats = {
        "reference_words": total_ref,
        "hypothesis_words": len(hyp_words),
        "substitutions": substitutions,
        "insertions": insertions,
        "deletions": deletions,
        "wer": wer,
    }

    return wer, stats


def find_differences(text1: str, text2: str, label1: str, label2: str) -> list[str]:
    """Find and format differences between two texts."""
    words1 = normalize_text(text1).split()
    words2 = normalize_text(text2).split()

    matcher = difflib.SequenceMatcher(None, words1, words2)
    differences = []

    for op, i1, i2, j1, j2 in matcher.get_opcodes():
        if op != "equal":
            chunk1 = " ".join(words1[i1:i2]) if i1 < i2 else "(none)"
            chunk2 = " ".join(words2[j1:j2]) if j1 < j2 else "(none)"
            differences.append(f"  {label1}: {chunk1}")
            differences.append(f"  {label2}: {chunk2}")
            differences.append("")

    return differences


def generate_report(
    medasr_path: str,
    whisper_path: str,
    medasr_text: str,
    whisper_text: str,
) -> str:
    """Generate comparison report."""
    lines = []
    lines.append("=" * 60)
    lines.append("MedASR vs Whisper Comparison Report")
    lines.append("=" * 60)
    lines.append("")

    # File info
    lines.append("Files:")
    lines.append(f"  MedASR:  {medasr_path}")
    lines.append(f"  Whisper: {whisper_path}")
    lines.append("")

    # Word counts
    medasr_words = len(normalize_text(medasr_text).split())
    whisper_words = len(normalize_text(whisper_text).split())
    lines.append("Word Counts:")
    lines.append(f"  MedASR:  {medasr_words} words")
    lines.append(f"  Whisper: {whisper_words} words")
    lines.append("")

    # Calculate WER (using Whisper as reference since it's more established)
    wer_whisper_ref, stats_whisper = calculate_wer(whisper_text, medasr_text)
    wer_medasr_ref, stats_medasr = calculate_wer(medasr_text, whisper_text)

    lines.append("Word Error Rate:")
    lines.append(f"  MedASR vs Whisper (Whisper as reference): {wer_whisper_ref:.1%}")
    lines.append(f"  Whisper vs MedASR (MedASR as reference):  {wer_medasr_ref:.1%}")
    lines.append("")

    lines.append("Edit Operations (Whisper as reference):")
    lines.append(f"  Substitutions: {stats_whisper['substitutions']}")
    lines.append(f"  Insertions:    {stats_whisper['insertions']}")
    lines.append(f"  Deletions:     {stats_whisper['deletions']}")
    lines.append("")

    # Show differences
    lines.append("-" * 60)
    lines.append("Differences (first 50):")
    lines.append("-" * 60)
    lines.append("")

    differences = find_differences(medasr_text, whisper_text, "MedASR", "Whisper")
    # Limit to first 50 difference blocks
    diff_blocks = []
    current_block = []
    for line in differences:
        if line == "":
            if current_block:
                diff_blocks.append(current_block)
                current_block = []
        else:
            current_block.append(line)

    for block in diff_blocks[:50]:
        lines.extend(block)
        lines.append("")

    if len(diff_blocks) > 50:
        lines.append(f"... and {len(diff_blocks) - 50} more differences")
        lines.append("")

    # Summary
    lines.append("=" * 60)
    lines.append("Summary")
    lines.append("=" * 60)
    similarity = 1 - wer_whisper_ref
    lines.append(f"Overall similarity: {similarity:.1%}")

    if wer_whisper_ref < 0.1:
        lines.append("Assessment: Very similar outputs")
    elif wer_whisper_ref < 0.2:
        lines.append("Assessment: Moderately similar")
    elif wer_whisper_ref < 0.3:
        lines.append("Assessment: Notable differences")
    else:
        lines.append("Assessment: Significant differences")

    return "\n".join(lines)


def main():
    parser = argparse.ArgumentParser(
        description="Compare MedASR and Whisper transcription outputs"
    )
    parser.add_argument("medasr", help="MedASR transcript file")
    parser.add_argument("whisper", help="Whisper transcript file")
    parser.add_argument(
        "-o", "--output",
        help="Output file for comparison report",
    )
    args = parser.parse_args()

    # Validate files
    medasr_path = Path(args.medasr)
    whisper_path = Path(args.whisper)

    if not medasr_path.exists():
        print(f"Error: MedASR file not found: {args.medasr}")
        sys.exit(1)

    if not whisper_path.exists():
        print(f"Error: Whisper file not found: {args.whisper}")
        sys.exit(1)

    # Load transcripts
    medasr_text = load_transcript(str(medasr_path))
    whisper_text = load_transcript(str(whisper_path))

    # Generate report
    report = generate_report(
        str(medasr_path),
        str(whisper_path),
        medasr_text,
        whisper_text,
    )

    # Output
    print(report)

    if args.output:
        with open(args.output, "w") as f:
            f.write(report)
        print(f"\nReport saved to: {args.output}")


if __name__ == "__main__":
    main()
