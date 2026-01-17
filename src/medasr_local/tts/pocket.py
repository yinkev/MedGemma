from __future__ import annotations

import tempfile
from dataclasses import dataclass
from pathlib import Path

import numpy as np
import torch


@dataclass(frozen=True)
class PocketVoice:
    name: str


class PocketTts:
    def __init__(self, voice: str, device: str = "cpu"):
        from pocket_tts import TTSModel

        self._model = TTSModel.load_model()
        self._voice = voice
        self._device = device
        self._state = self._model.get_state_for_audio_prompt(voice)

    @property
    def sample_rate(self) -> int:
        return int(getattr(self._model, "sample_rate"))

    def synth(self, text: str) -> np.ndarray:
        audio: torch.Tensor = self._model.generate_audio(self._state, text)
        return audio.detach().to("cpu").float().numpy()


def write_wav_float32(path: Path, sample_rate: int, audio: np.ndarray) -> None:
    from scipy.io import wavfile

    wavfile.write(str(path), sample_rate, audio.astype(np.float32))


def synth_to_temp_wav(text: str, voice: str) -> tuple[Path, int]:
    tts = PocketTts(voice=voice)
    audio = tts.synth(text)
    tmp = tempfile.NamedTemporaryFile(suffix=".wav", delete=False)
    tmp_path = Path(tmp.name)
    tmp.close()
    write_wav_float32(tmp_path, tts.sample_rate, audio)
    return tmp_path, tts.sample_rate
