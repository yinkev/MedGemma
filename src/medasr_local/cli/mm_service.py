from __future__ import annotations

import argparse
import json
import os
import sys
import time
from pathlib import Path
from typing import Any

from medasr_local.cli.ipc import emit, emit_error, emit_status
from medasr_local.qa.medgemma_multimodal import MedGemmaMultimodal, load_images

_SESSIONS: dict[str, dict[str, Any]] = {}


def _get_session(req: dict[str, Any]) -> dict[str, Any]:
    session_id = str(req.get("session_id") or "default")
    session = _SESSIONS.get(session_id)
    if session is None:
        session = {}
        _SESSIONS[session_id] = session
    return session


def _read_jsonl(stdin) -> Any:
    line = stdin.readline()
    if not line:
        return None
    line = line.strip()
    if not line:
        return {}
    return json.loads(line)


def _write_json(obj: dict[str, Any]) -> None:
    emit(obj)


def _path_system_prompt() -> str:
    return (
        "You are MedGemma 1.5, a helpful medical imaging assistant.\n\n"
        "Task: Given the provided pathology image, produce a structured, cautious interpretation.\n\n"
        "Requirements:\n"
        "- Use headings exactly: Findings, Impression, Differential, Confidence, Next steps.\n"
        "- Be explicit about uncertainty and image limitations.\n"
        "- Do not invent clinical history.\n"
        "- Keep it concise.\n"
    )


def _tutor_system_prompt() -> str:
    return (
        "You are a radiology learning companion.\n\n"
        "You will tutor the user using Socratic questions based on the provided medical image.\n"
        "Rules:\n"
        "- Ask one question at a time.\n"
        "- Prefer multiple-choice questions with 4 options (A-D).\n"
        "- If the user answers, give feedback and a short explanation.\n"
        "- Do not reveal the final diagnosis unless asked to reveal.\n"
        "- Keep the conversation educational and concise.\n"
    )


def _validate_local_model_dir(path: str) -> None:
    p = Path(path)
    if not p.exists():
        raise RuntimeError(f"Model not found: {path}")
    need = ["config.json", "processor_config.json", "preprocessor_config.json"]
    missing = [name for name in need if not (p / name).exists()]
    if missing:
        raise RuntimeError(
            "Missing model files: "
            + ", ".join(missing)
            + ". Run ./setup.sh (or rerun scripts/materialize_medgemma_model.py)."
        )


def handle_request(
    mm: MedGemmaMultimodal,
    req: dict[str, Any],
    repo_root: Path,
) -> dict[str, Any]:
    task = str(req.get("task") or "")
    session = _get_session(req)

    if task == "path_report":
        image_path = Path(str(req.get("image_path") or ""))
        if not image_path.is_absolute():
            image_path = (repo_root / image_path).resolve()
        question = str(
            req.get("question") or "Describe the key morphology and likely diagnosis."
        )
        max_tokens = int(req.get("max_tokens") or 512)

        imgs = load_images(image_path, max_tiles=int(req.get("max_tiles") or 4))
        content = [{"type": "image"} for _ in range(len(imgs))] + [
            {"type": "text", "text": question}
        ]

        messages = [
            {"role": "system", "content": _path_system_prompt()},
            {
                "role": "user",
                "content": content,
            },
        ]

        answer = mm.generate(messages=messages, images=imgs, max_new_tokens=max_tokens)
        return {"ok": True, "answer": answer}

    if task == "tutor_next":
        image_path = Path(str(req.get("image_path") or ""))
        if not image_path.is_absolute():
            image_path = (repo_root / image_path).resolve()

        topic = req.get("topic")
        question = (
            f"Generate the next teaching question about: {topic}"
            if topic
            else "Generate the next teaching question about the image."
        )
        max_tokens = int(req.get("max_tokens") or 256)

        session["image_path"] = str(image_path)

        imgs = load_images(image_path, max_tiles=1)
        content = [{"type": "image"} for _ in range(len(imgs))] + [
            {"type": "text", "text": question}
        ]

        messages = [
            {"role": "system", "content": _tutor_system_prompt()},
            {
                "role": "user",
                "content": content,
            },
        ]

        out = mm.generate(messages=messages, images=imgs, max_new_tokens=max_tokens)
        session["last_question"] = out
        return {"ok": True, "question": out}

    if task == "tutor_grade":
        image_path_str = str(req.get("image_path") or session.get("image_path") or "")
        image_path = Path(image_path_str)
        if not image_path.is_absolute():
            image_path = (repo_root / image_path).resolve()

        prompt = str(req.get("prompt") or session.get("last_question") or "")
        user_answer = str(req.get("user_answer") or req.get("student_answer") or "")
        max_tokens = int(req.get("max_tokens") or 256)

        if not prompt.strip():
            raise RuntimeError("Missing prompt")
        if not user_answer.strip():
            raise RuntimeError("Missing user_answer")

        grade_prompt = (
            "Given the image and the question, evaluate the user's answer. "
            "Respond with: Verdict: <Correct/Partially correct/Incorrect>\\n"
            "Feedback: <one paragraph>\\n"
            "Key points: <3 bullets>"
        )

        imgs = load_images(image_path, max_tiles=1)
        content = [{"type": "image"} for _ in range(len(imgs))] + [
            {"type": "text", "text": f"Question: {prompt}"},
            {"type": "text", "text": f"User answer: {user_answer}"},
            {"type": "text", "text": grade_prompt},
        ]

        messages = [
            {"role": "system", "content": _tutor_system_prompt()},
            {
                "role": "user",
                "content": content,
            },
        ]

        out = mm.generate(messages=messages, images=imgs, max_new_tokens=max_tokens)
        return {"ok": True, "grading": out}

    if task == "tutor_reveal":
        image_path_str = str(req.get("image_path") or session.get("image_path") or "")
        image_path = Path(image_path_str)
        if not image_path.is_absolute():
            image_path = (repo_root / image_path).resolve()

        max_tokens = int(req.get("max_tokens") or 384)

        reveal_prompt = (
            "Reveal your best-effort interpretation and likely diagnosis for the image. "
            "Be explicit about uncertainty and limitations. Keep it concise."
        )

        imgs = load_images(image_path, max_tiles=1)
        content = [{"type": "image"} for _ in range(len(imgs))] + [
            {"type": "text", "text": reveal_prompt}
        ]

        messages = [
            {"role": "system", "content": _tutor_system_prompt()},
            {
                "role": "user",
                "content": content,
            },
        ]

        out = mm.generate(messages=messages, images=imgs, max_new_tokens=max_tokens)
        return {"ok": True, "reveal": out}

    raise RuntimeError(f"Unknown task: {task}")


def main() -> None:
    parser = argparse.ArgumentParser(
        description="Persistent MedGemma multimodal service (JSONL in/out)."
    )
    parser.add_argument("--model", default="models/medgemma")
    args = parser.parse_args()

    repo_root = Path(__file__).resolve().parents[3]

    env = os.environ
    env["TOKENIZERS_PARALLELISM"] = "false"
    env["HF_HUB_DISABLE_TELEMETRY"] = "1"
    env["TRANSFORMERS_VERBOSITY"] = "error"
    env["HF_HUB_OFFLINE"] = "1"
    env["TRANSFORMERS_OFFLINE"] = "1"

    try:
        _validate_local_model_dir(args.model)
    except Exception as e:
        emit_error("mm_service_init_failed", detail=str(e))
        raise SystemExit(1)

    t0 = time.time()
    emit_status("loading_medgemma_multimodal")
    try:
        mm = MedGemmaMultimodal(model_name=args.model)
    except Exception as e:
        emit_error("mm_service_init_failed", detail=str(e))
        raise SystemExit(1)

    emit_status("ready", load_s=time.time() - t0)

    while True:
        try:
            req = _read_jsonl(sys.stdin)
        except Exception as e:
            emit_error("invalid_json", detail=str(e))
            continue

        if req is None:
            break

        req_id = req.get("id")
        if not req_id:
            req_id = "req_" + str(int(time.time() * 1000))

        try:
            result = handle_request(mm=mm, req=req, repo_root=repo_root)
            _write_json(
                {"type": "result", "id": req_id, "task": req.get("task"), **result}
            )
        except Exception as e:
            emit_error("request_failed", id=req_id, detail=str(e))


if __name__ == "__main__":
    main()
