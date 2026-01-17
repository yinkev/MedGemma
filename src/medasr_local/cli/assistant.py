from __future__ import annotations

import argparse
import queue
import threading
import time
from pathlib import Path

import numpy as np
import sounddevice as sd

from medasr_local.asr.decode import transcribe_audio
from medasr_local.asr.lm import build_kenlm_decoder
from medasr_local.asr.model import load_asr
from medasr_local.qa.medgemma import MedGemma
from medasr_local.tts.pocket import PocketTts


class LiveAssistant:
    def __init__(
        self,
        model_name: str,
        kenlm_path: Path,
        use_lm: bool,
        voice: str,
        chunk_s: float,
    ):
        self.sample_rate = 16000
        self.chunk_s = chunk_s
        self.chunk_samples = int(self.sample_rate * chunk_s)

        self.audio_queue: queue.Queue = queue.Queue()
        self.audio_buffer = np.array([], dtype=np.float32)
        self.transcript_buffer: list[str] = []

        self.is_running = True
        self.is_paused = False

        print("Loading MedASR...")
        self.asr_bundle = load_asr(model_name)
        self.lm_decoder = None
        if use_lm:
            self.lm_decoder = build_kenlm_decoder(
                self.asr_bundle.processor, self.asr_bundle.model, str(kenlm_path)
            )

        print("Loading MedGemma...")
        self.qa = MedGemma()

        print("Loading Pocket-TTS...")
        self.tts = PocketTts(voice=voice)

    def _audio_callback(self, indata, frames, time_info, status):
        if status:
            print(f"Audio status: {status}")
        if not self.is_paused:
            audio = indata[:, 0] if len(indata.shape) > 1 else indata
            self.audio_queue.put(audio.copy())

    def _process_audio(self):
        while self.is_running:
            try:
                audio = self.audio_queue.get(timeout=0.1)
                self.audio_buffer = np.concatenate([self.audio_buffer, audio])

                if len(self.audio_buffer) >= self.chunk_samples:
                    chunk = self.audio_buffer[: self.chunk_samples]
                    self.audio_buffer = self.audio_buffer[self.chunk_samples // 2 :]

                    text = transcribe_audio(
                        chunk,
                        self.sample_rate,
                        self.asr_bundle,
                        self.lm_decoder,
                    )

                    if text:
                        print(f"\r[ASR] {text}")
                        self.transcript_buffer.append(text)

                        if self._is_question(text):
                            self._handle_question(text)

            except queue.Empty:
                continue
            except Exception as e:
                print(f"Error processing audio: {e}")

    def _is_question(self, text: str) -> bool:
        text_lower = text.lower().strip()
        question_words = [
            "what",
            "how",
            "why",
            "when",
            "where",
            "who",
            "which",
            "can",
            "could",
            "would",
            "should",
            "is",
            "are",
            "does",
            "do",
        ]
        return any(
            text_lower.startswith(w) for w in question_words
        ) or text.strip().endswith("?")

    def _handle_question(self, question: str):
        print(f"\n[QUESTION DETECTED] {question}")
        print("[Thinking...]", flush=True)

        context = " ".join(self.transcript_buffer[-50:])

        answer = self.qa.ask(context, question, max_tokens=256)
        print(f"\n[ANSWER] {answer}\n")

        print("[Speaking...]", flush=True)
        audio = self.tts.synth(answer)

        import tempfile
        from scipy.io import wavfile

        tmp = tempfile.NamedTemporaryFile(suffix=".wav", delete=False)
        tmp_path = Path(tmp.name)
        tmp.close()

        wavfile.write(str(tmp_path), self.tts.sample_rate, audio.astype(np.float32))

        import subprocess

        subprocess.run(["afplay", str(tmp_path)], check=False)

        try:
            tmp_path.unlink()
        except OSError:
            pass

        print("[Ready]")

    def run(self):
        print("\n=== MedASR Live Assistant ===")
        print("Speak naturally. Questions will be detected and answered.")
        print("Press Ctrl+C to stop.\n")

        process_thread = threading.Thread(target=self._process_audio, daemon=True)
        process_thread.start()

        try:
            with sd.InputStream(
                samplerate=self.sample_rate,
                channels=1,
                dtype="float32",
                callback=self._audio_callback,
            ):
                while self.is_running:
                    time.sleep(0.1)
        except KeyboardInterrupt:
            print("\n\nStopping...")
            self.is_running = False


def main() -> None:
    parser = argparse.ArgumentParser()
    parser.add_argument("--no-lm", action="store_true")
    parser.add_argument("--voice", default="alba")
    parser.add_argument("--chunk-s", type=float, default=5.0)
    args = parser.parse_args()

    project = Path(__file__).resolve().parents[3]
    config_path = project / "config.yaml"

    model_name = "google/medasr"
    kenlm_path = project / "models" / "lm_6.kenlm"

    if config_path.exists():
        import yaml

        cfg = yaml.safe_load(config_path.read_text())
        model_name = cfg.get("models", {}).get("medasr", model_name)
        lm_rel = cfg.get("models", {}).get("lm_path", "models/lm_6.kenlm")
        kenlm_path = project / lm_rel

    assistant = LiveAssistant(
        model_name=model_name,
        kenlm_path=kenlm_path,
        use_lm=(not args.no_lm),
        voice=args.voice,
        chunk_s=args.chunk_s,
    )

    assistant.run()


if __name__ == "__main__":
    main()
