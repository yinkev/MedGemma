#!/usr/bin/env python3
"""
MedASR Live Transcription Script

Real-time transcription from microphone or system audio.

Controls:
    Space - Pause/Resume transcription
    Q     - Quit and save transcript
    S     - Save current transcript (without quitting)

Usage:
    python live_transcribe.py              # Microphone input
    python live_transcribe.py --system     # System audio (requires audiocapture)
"""

import argparse
import os
import queue
import select
import signal
import subprocess
import sys
import threading
import time
from datetime import datetime
from pathlib import Path

import numpy as np
import sounddevice as sd
import torch
import yaml
from transformers import AutoModelForCTC, AutoProcessor

# Add parent directory to path
SCRIPT_DIR = Path(__file__).parent
PROJECT_DIR = SCRIPT_DIR.parent
sys.path.insert(0, str(SCRIPT_DIR))


class LiveTranscriber:
    def __init__(self, config: dict, use_system_audio: bool = False):
        self.config = config
        self.use_system_audio = use_system_audio
        self.sample_rate = 16000
        self.chunk_length = config["live"]["chunk_length_s"]
        self.use_lm = config["live"].get("use_lm", False)
        self.save_folder = PROJECT_DIR / config["live"]["save_folder"]

        # State
        self.audio_queue = queue.Queue()
        self.transcript_lines = []
        self.is_paused = False
        self.is_running = True
        self.audio_buffer = np.array([], dtype=np.float32)

        # Create save folder
        self.save_folder.mkdir(parents=True, exist_ok=True)

        # Generate output filename
        timestamp = datetime.now().strftime("%Y-%m-%d_%H-%M-%S")
        self.output_file = self.save_folder / f"live_{timestamp}.txt"

        # Load model
        self._load_model()

    def _load_model(self):
        """Load MedASR model."""
        model_name = self.config["models"]["medasr"]
        print(f"Loading MedASR model: {model_name}")

        self.processor = AutoProcessor.from_pretrained(model_name)
        self.model = AutoModelForCTC.from_pretrained(model_name)

        # Select device
        if torch.cuda.is_available():
            self.device = "cuda"
        elif torch.backends.mps.is_available():
            self.device = "mps"
        else:
            self.device = "cpu"

        self.model = self.model.to(self.device)
        self.model.eval()
        print(f"Model loaded on device: {self.device}")

        # Load LM if enabled
        self.lm_decoder = None
        if self.use_lm:
            self._load_lm()

    def _load_lm(self):
        """Load language model for decoding."""
        lm_path = PROJECT_DIR / self.config["models"]["lm_path"]
        if lm_path.exists():
            try:
                from pyctcdecode import build_ctcdecoder

                vocab = list(self.processor.tokenizer.get_vocab().keys())
                self.lm_decoder = build_ctcdecoder(
                    labels=vocab,
                    kenlm_model_path=str(lm_path),
                )
                print("Language model loaded")
            except Exception as e:
                print(f"Warning: Could not load LM: {e}")

    def _audio_callback(self, indata, frames, time_info, status):
        """Callback for sounddevice audio stream."""
        if status:
            print(f"Audio status: {status}")
        if not self.is_paused:
            # Convert to mono float32
            audio = indata[:, 0] if len(indata.shape) > 1 else indata
            self.audio_queue.put(audio.copy())

    def _transcribe_chunk(self, audio: np.ndarray) -> str:
        """Transcribe audio chunk."""
        if len(audio) < self.sample_rate * 0.5:
            return ""

        inputs = self.processor(
            audio,
            sampling_rate=self.sample_rate,
            return_tensors="pt",
            padding=True,
        )
        inputs = inputs.to(self.device)

        with torch.no_grad():
            # Use model.generate() for decoding
            outputs = self.model.generate(**inputs)
            text = self.processor.batch_decode(outputs)[0]

        return text.strip()

    def _process_audio(self):
        """Process audio from queue and transcribe."""
        chunk_samples = int(self.chunk_length * self.sample_rate)

        while self.is_running:
            try:
                # Get audio from queue
                audio = self.audio_queue.get(timeout=0.1)
                self.audio_buffer = np.concatenate([self.audio_buffer, audio])

                # Process when we have enough audio
                if len(self.audio_buffer) >= chunk_samples:
                    chunk = self.audio_buffer[:chunk_samples]
                    self.audio_buffer = self.audio_buffer[chunk_samples // 2:]  # 50% overlap

                    text = self._transcribe_chunk(chunk)
                    if text:
                        timestamp = datetime.now().strftime("%H:%M:%S")
                        line = f"[{timestamp}] {text}"
                        self.transcript_lines.append(line)
                        print(f"\r{line}")
                        print()  # New line for next output

            except queue.Empty:
                continue
            except Exception as e:
                print(f"Error processing audio: {e}")

    def _save_transcript(self):
        """Save current transcript to file."""
        if not self.transcript_lines:
            print("No transcript to save.")
            return

        with open(self.output_file, "w") as f:
            f.write("\n".join(self.transcript_lines))
            f.write("\n")

        print(f"\nTranscript saved to: {self.output_file}")
        print(f"Total lines: {len(self.transcript_lines)}")

    def _handle_keyboard(self):
        """Handle keyboard input for controls."""
        import termios
        import tty

        old_settings = termios.tcgetattr(sys.stdin)
        try:
            tty.setraw(sys.stdin.fileno())
            while self.is_running:
                if sys.stdin in select.select([sys.stdin], [], [], 0.1)[0]:
                    char = sys.stdin.read(1)
                    if char.lower() == "q":
                        self.is_running = False
                        print("\n\nQuitting...")
                    elif char == " ":
                        self.is_paused = not self.is_paused
                        status = "PAUSED" if self.is_paused else "RECORDING"
                        print(f"\n[{status}]")
                    elif char.lower() == "s":
                        self._save_transcript()
        finally:
            termios.tcsetattr(sys.stdin, termios.TCSADRAIN, old_settings)

    def run(self):
        """Start live transcription."""
        print("\n=== MedASR Live Transcription ===")
        print(f"Output file: {self.output_file}")
        print("\nControls:")
        print("  Space - Pause/Resume")
        print("  S     - Save transcript")
        print("  Q     - Quit and save")
        print("\nListening...\n")

        # Start processing thread
        process_thread = threading.Thread(target=self._process_audio)
        process_thread.start()

        # Start keyboard handler thread
        import select
        keyboard_thread = threading.Thread(target=self._handle_keyboard)
        keyboard_thread.start()

        try:
            if self.use_system_audio:
                self._run_system_audio()
            else:
                self._run_microphone()
        except KeyboardInterrupt:
            self.is_running = False
        finally:
            self.is_running = False
            process_thread.join(timeout=2)
            self._save_transcript()

    def _run_microphone(self):
        """Run with microphone input."""
        with sd.InputStream(
            samplerate=self.sample_rate,
            channels=1,
            dtype="float32",
            callback=self._audio_callback,
        ):
            while self.is_running:
                time.sleep(0.1)

    def _run_system_audio(self):
        """Run with system audio capture."""
        audiocapture = PROJECT_DIR / "native" / "audiocapture"
        if not audiocapture.exists():
            print("Error: audiocapture not found. Run setup.sh to compile it.")
            print("Falling back to microphone input...")
            self._run_microphone()
            return

        # Start audiocapture process
        process = subprocess.Popen(
            [str(audiocapture)],
            stdout=subprocess.PIPE,
            bufsize=0,
        )

        try:
            while self.is_running:
                # Read raw audio data from audiocapture
                data = process.stdout.read(self.sample_rate * 2)  # 1 second of 16-bit audio
                if data:
                    audio = np.frombuffer(data, dtype=np.int16).astype(np.float32) / 32768.0
                    if not self.is_paused:
                        self.audio_queue.put(audio)
        finally:
            process.terminate()


def load_config() -> dict:
    """Load configuration from config.yaml."""
    config_path = PROJECT_DIR / "config.yaml"
    if config_path.exists():
        with open(config_path) as f:
            return yaml.safe_load(f)
    return {
        "models": {"medasr": "google/medasr", "lm_path": "models/lm_6.kenlm"},
        "live": {"use_lm": False, "chunk_length_s": 5, "save_folder": "transcripts/"},
    }


def main():
    parser = argparse.ArgumentParser(description="MedASR Live Transcription")
    parser.add_argument(
        "--system",
        action="store_true",
        help="Use system audio instead of microphone",
    )
    parser.add_argument(
        "--lm",
        action="store_true",
        help="Enable language model (slower but more accurate)",
    )
    args = parser.parse_args()

    config = load_config()

    if args.lm:
        config["live"]["use_lm"] = True

    transcriber = LiveTranscriber(config, use_system_audio=args.system)
    transcriber.run()


if __name__ == "__main__":
    main()
