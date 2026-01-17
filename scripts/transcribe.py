#!/usr/bin/env python3
"""
MedASR File Transcription Script

Transcribes audio/video files using MedASR with optional 6-gram language model.
Outputs JSON with timestamps, then converts to timestamped TXT.

Usage:
    python transcribe.py <audio_or_video_file>
    python transcribe.py lecture.mp4
    python transcribe.py recording.wav
"""

import argparse
import json
import os
import subprocess
import sys
import tempfile
from pathlib import Path

import torch
import yaml
from scipy.io import wavfile
from tqdm import tqdm
from transformers import AutoModelForCTC, AutoProcessor

# Add parent directory to path for imports
SCRIPT_DIR = Path(__file__).parent
PROJECT_DIR = SCRIPT_DIR.parent
sys.path.insert(0, str(SCRIPT_DIR))


def load_config():
    """Load configuration from config.yaml."""
    config_path = PROJECT_DIR / "config.yaml"
    if config_path.exists():
        with open(config_path) as f:
            return yaml.safe_load(f)
    return {
        "models": {"medasr": "google/medasr", "lm_path": "models/lm_6.kenlm"},
        "transcription": {"chunk_length_s": 30, "stride_length_s": 5, "use_lm": True},
    }


def extract_audio(input_file: str, output_wav: str) -> None:
    """Extract audio from video/audio file to 16kHz mono WAV."""
    cmd = [
        "ffmpeg",
        "-i", input_file,
        "-ar", "16000",
        "-ac", "1",
        "-f", "wav",
        "-y",
        output_wav,
    ]
    subprocess.run(cmd, check=True, capture_output=True)


def load_audio(wav_path: str) -> tuple:
    """Load WAV file and return sample rate and audio data."""
    sample_rate, audio = wavfile.read(wav_path)
    # Normalize to float32 in range [-1, 1]
    if audio.dtype == "int16":
        audio = audio.astype("float32") / 32768.0
    elif audio.dtype == "int32":
        audio = audio.astype("float32") / 2147483648.0
    return sample_rate, audio


def load_model_and_processor(config: dict):
    """Load MedASR model and processor."""
    model_name = config["models"]["medasr"]
    print(f"Loading MedASR model: {model_name}")

    processor = AutoProcessor.from_pretrained(model_name)
    model = AutoModelForCTC.from_pretrained(model_name)

    device = "cuda" if torch.cuda.is_available() else "mps" if torch.backends.mps.is_available() else "cpu"
    model = model.to(device)
    model.eval()

    print(f"Model loaded on device: {device}")
    return model, processor, device


def load_language_model(config: dict, processor):
    """Load 6-gram language model for decoding."""
    lm_path = PROJECT_DIR / config["models"]["lm_path"]

    if not lm_path.exists():
        print(f"Warning: Language model not found at {lm_path}")
        print("Run setup.sh to download the language model.")
        return None

    try:
        from pyctcdecode import build_ctcdecoder

        vocab = list(processor.tokenizer.get_vocab().keys())
        decoder = build_ctcdecoder(
            labels=vocab,
            kenlm_model_path=str(lm_path),
        )
        print(f"Loaded language model from {lm_path}")
        return decoder
    except Exception as e:
        print(f"Warning: Could not load language model: {e}")
        return None


def transcribe_chunk(
    audio_chunk: "torch.Tensor",
    model,
    processor,
    device: str,
    lm_decoder=None,
) -> str:
    """Transcribe a single audio chunk."""
    inputs = processor(
        audio_chunk,
        sampling_rate=16000,
        return_tensors="pt",
        padding=True,
    )
    inputs = inputs.to(device)

    with torch.no_grad():
        # Use model.generate() for decoding (handles vocab mapping internally)
        outputs = model.generate(**inputs)
        text = processor.batch_decode(outputs)[0]

    return text.strip()


def format_timestamp(seconds: float) -> str:
    """Format seconds as HH:MM:SS."""
    hours = int(seconds // 3600)
    minutes = int((seconds % 3600) // 60)
    secs = int(seconds % 60)
    return f"{hours:02d}:{minutes:02d}:{secs:02d}"


def transcribe_file(
    input_file: str,
    config: dict,
) -> list[dict]:
    """Transcribe an audio/video file with timestamps."""

    # Extract audio to temporary WAV
    with tempfile.NamedTemporaryFile(suffix=".wav", delete=False) as tmp:
        tmp_wav = tmp.name

    try:
        print(f"Extracting audio from: {input_file}")
        extract_audio(input_file, tmp_wav)

        print("Loading audio...")
        sample_rate, audio = load_audio(tmp_wav)
        duration = len(audio) / sample_rate
        print(f"Audio duration: {format_timestamp(duration)}")

        # Load model
        model, processor, device = load_model_and_processor(config)

        # Load language model if enabled
        lm_decoder = None
        if config["transcription"].get("use_lm", True):
            lm_decoder = load_language_model(config, processor)

        # Chunked transcription
        chunk_length = config["transcription"]["chunk_length_s"]
        stride_length = config["transcription"]["stride_length_s"]
        chunk_samples = int(chunk_length * sample_rate)
        stride_samples = int(stride_length * sample_rate)

        segments = []
        position = 0

        # Calculate number of chunks for progress bar
        num_chunks = max(1, (len(audio) - chunk_samples) // stride_samples + 1)

        print("Transcribing...")
        with tqdm(total=num_chunks, desc="Progress") as pbar:
            while position < len(audio):
                # Get chunk
                end_pos = min(position + chunk_samples, len(audio))
                chunk = audio[position:end_pos]

                # Skip very short chunks
                if len(chunk) < sample_rate * 0.5:
                    break

                # Transcribe
                start_time = position / sample_rate
                end_time = end_pos / sample_rate

                text = transcribe_chunk(chunk, model, processor, device, lm_decoder)

                if text:
                    segments.append({
                        "start": start_time,
                        "end": end_time,
                        "text": text,
                    })

                position += stride_samples
                pbar.update(1)

        return segments

    finally:
        # Cleanup temp file
        if os.path.exists(tmp_wav):
            os.remove(tmp_wav)


def merge_overlapping_segments(segments: list[dict]) -> list[dict]:
    """Merge overlapping segments to avoid duplicate text."""
    if not segments:
        return []

    merged = [segments[0].copy()]

    for seg in segments[1:]:
        # Check if this segment significantly overlaps with previous
        prev = merged[-1]

        # If there's overlap, try to merge intelligently
        if seg["start"] < prev["end"]:
            # Take the second half of current segment
            overlap_duration = prev["end"] - seg["start"]
            if overlap_duration > 0:
                # Estimate word boundary - take later words
                words = seg["text"].split()
                if len(words) > 2:
                    # Skip first few words (likely duplicated)
                    skip_words = max(1, len(words) // 3)
                    seg["text"] = " ".join(words[skip_words:])
                    seg["start"] = prev["end"]

        if seg["text"]:
            merged.append(seg)

    return merged


def save_json(segments: list[dict], output_path: str) -> None:
    """Save segments to JSON file."""
    with open(output_path, "w") as f:
        json.dump({"segments": segments}, f, indent=2)
    print(f"JSON saved to: {output_path}")


def save_txt(segments: list[dict], output_path: str) -> None:
    """Save segments to timestamped TXT file."""
    with open(output_path, "w") as f:
        for seg in segments:
            timestamp = format_timestamp(seg["start"])
            f.write(f"[{timestamp}] {seg['text']}\n")
    print(f"TXT saved to: {output_path}")


def main():
    parser = argparse.ArgumentParser(
        description="Transcribe audio/video files using MedASR"
    )
    parser.add_argument("input_file", help="Path to audio or video file")
    parser.add_argument(
        "-o", "--output",
        help="Output path (default: input_file_medasr.txt)",
    )
    parser.add_argument(
        "--no-lm",
        action="store_true",
        help="Disable language model (faster but less accurate)",
    )
    parser.add_argument(
        "--json-only",
        action="store_true",
        help="Output JSON only, skip TXT conversion",
    )
    args = parser.parse_args()

    # Validate input
    input_path = Path(args.input_file)
    if not input_path.exists():
        print(f"Error: File not found: {args.input_file}")
        sys.exit(1)

    # Load config
    config = load_config()

    # Override LM setting if requested
    if args.no_lm:
        config["transcription"]["use_lm"] = False

    # Determine output paths
    if args.output:
        base_output = Path(args.output).with_suffix("")
    else:
        base_output = input_path.parent / f"{input_path.stem}_medasr"

    json_output = str(base_output) + ".json"
    txt_output = str(base_output) + ".txt"

    # Transcribe
    segments = transcribe_file(str(input_path), config)

    # Merge overlapping segments
    segments = merge_overlapping_segments(segments)

    # Save outputs
    save_json(segments, json_output)

    if not args.json_only:
        save_txt(segments, txt_output)

    print("\nTranscription complete!")
    print(f"Total segments: {len(segments)}")


if __name__ == "__main__":
    main()
