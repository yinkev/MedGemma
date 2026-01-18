from __future__ import annotations

import json
import time
from typing import Any


def emit(event: dict[str, Any]) -> None:
    print(json.dumps(event, ensure_ascii=False), flush=True)


def emit_status(message: str, **extra: Any) -> None:
    emit({"type": "status", "ts": time.time(), "message": message, **extra})


def emit_error(message: str, **extra: Any) -> None:
    emit({"type": "error", "ts": time.time(), "message": message, **extra})
