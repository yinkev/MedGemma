from __future__ import annotations

import argparse
import json
import os
import queue
import subprocess
import threading
import time
from pathlib import Path

import numpy as np
import sounddevice as sd

from medasr_local.asr.decode import transcribe_audio
from medasr_local.asr.lm import build_kenlm_decoder
from medasr_local.asr.model import load_asr


class LiveAssistant:
    def __init__(
        self,
        repo_root: Path,
        model_name: str,
        kenlm_path: Path,
        use_lm: bool,
        medgemma_model: str,
        qa_python: Path,
        speak_bin: Path,
        voice: str,
        chunk_s: float,
    ):
        self.repo_root = repo_root
        self.qa_python = qa_python
        self.speak_bin = speak_bin
        self.medgemma_model = medgemma_model
        self.voice = voice

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

    def _ask_medgemma(self, context: str, question: str, max_tokens: int) -> str:
        if not self.qa_python.exists():
            raise RuntimeError(
                f"MedGemma Python runtime not found: {self.qa_python} (run ./setup.sh)"
            )

        if not Path(self.medgemma_model).exists():
            raise RuntimeError(
                "MedGemma model not found locally. Run: .venv314/bin/python scripts/materialize_medgemma_model.py --out models/medgemma"
            )

        env = os.environ.copy()
        env["PYTHONPATH"] = str((self.repo_root / "src").resolve())
        env["TOKENIZERS_PARALLELISM"] = "false"
        env["HF_HUB_DISABLE_TELEMETRY"] = "1"
        env["TRANSFORMERS_VERBOSITY"] = "error"
        env["HF_HUB_OFFLINE"] = "1"
        env["TRANSFORMERS_OFFLINE"] = "1"

        payload = json.dumps(
            {"context": context, "question": question}, ensure_ascii=False
        )

        proc = subprocess.run(
            [
                str(self.qa_python),
                "-u",
                "-m",
                "medasr_local.cli.qa_inline",
                "--model",
                self.medgemma_model,
                "--max-tokens",
                str(max_tokens),
            ],
            input=payload,
            text=True,
            capture_output=True,
            env=env,
        )

        if proc.returncode != 0:
            err = (proc.stderr or "").strip()
            raise RuntimeError(err if err else f"medgemma exited {proc.returncode}")

        return (proc.stdout or "").strip()

    def _speak(self, text: str) -> None:
        if not text.strip():
            return
        if not self.speak_bin.exists():
            raise RuntimeError(f"Speak helper not found: {self.speak_bin}")
        subprocess.run(
            [str(self.speak_bin), "--voice", self.voice, text],
            check=False,
        )

    def _handle_question(self, question: str):
        print(f"\n[QUESTION DETECTED] {question}")
        print("[Thinking...]", flush=True)

        context = " ".join(self.transcript_buffer[-50:])

        try:
            answer = self._ask_medgemma(context, question, max_tokens=256)
        except Exception as e:
            print(f"\n[ANSWER ERROR] {e}\n")
            return

        print(f"\n[ANSWER] {answer}\n")

        print("[Speaking...]", flush=True)
        try:
            self._speak(answer)
        except Exception as e:
            print(f"[SPEAK ERROR] {e}")

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
    lm_group = parser.add_mutually_exclusive_group()
    lm_group.add_argument("--lm", dest="lm", action="store_true")
    lm_group.add_argument("--no-lm", dest="lm", action="store_false")
    parser.set_defaults(lm=None)
    parser.add_argument("--voice", default="alba")
    parser.add_argument("--chunk-s", type=float, default=None)
    args = parser.parse_args()

    project = Path(__file__).resolve().parents[3]
    config_path = project / "config.yaml"

    model_name = "models/medasr"
    kenlm_path = project / "models" / "lm_6.kenlm"
    medgemma_model = "models/medgemma"

    use_lm_default = False
    chunk_s = 5.0

    if config_path.exists():
        import yaml

        cfg = yaml.safe_load(config_path.read_text()) or {}

        models = cfg.get("models", {})
        model_name = models.get("medasr", model_name)
        if (project / model_name).exists():
            model_name = str((project / model_name).resolve())

        medgemma_model = models.get("medgemma", medgemma_model)
        if (project / medgemma_model).exists():
            medgemma_model = str((project / medgemma_model).resolve())

        lm_rel = models.get("lm_path", "models/lm_6.kenlm")
        kenlm_path = project / lm_rel

        live_cfg = cfg.get("live", {})
        use_lm_default = bool(live_cfg.get("use_lm", use_lm_default))
        try:
            chunk_s = float(live_cfg.get("chunk_length_s", chunk_s))
        except (TypeError, ValueError):
            pass

    use_lm = use_lm_default if args.lm is None else bool(args.lm)
    chunk_s = chunk_s if args.chunk_s is None else args.chunk_s

    assistant = LiveAssistant(
        repo_root=project,
        model_name=model_name,
        kenlm_path=kenlm_path,
        use_lm=use_lm,
        medgemma_model=medgemma_model,
        qa_python=project / ".venv314/bin/python",
        speak_bin=project / "bin/medasr-speak",
        voice=args.voice,
        chunk_s=chunk_s,
    )

    assistant.run()


if __name__ == "__main__":
    main()
