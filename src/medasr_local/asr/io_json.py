from __future__ import annotations

import json
from pathlib import Path


def read_json(path: Path) -> dict:
    return json.loads(path.read_text())
