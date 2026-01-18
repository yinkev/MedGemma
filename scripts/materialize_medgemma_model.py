#!/usr/bin/env python3
from __future__ import annotations

import argparse
import os
import shutil
from pathlib import Path


def main() -> None:
    parser = argparse.ArgumentParser(
        description="Copy the cached Hugging Face MedGemma snapshot into ./models/medgemma (no symlinks)."
    )
    parser.add_argument(
        "--repo-id",
        default="google/medgemma-1.5-4b-it",
        help="Hugging Face repo id (default: google/medgemma-1.5-4b-it)",
    )
    parser.add_argument(
        "--out",
        default="models/medgemma",
        help="Destination directory under the repo (default: models/medgemma)",
    )
    args = parser.parse_args()

    repo_root = Path(__file__).resolve().parents[1]
    dest = (repo_root / args.out).resolve()

    try:
        from huggingface_hub import snapshot_download
    except Exception as e:
        raise SystemExit(
            "huggingface_hub is required in the active environment. Run ./setup.sh first."
        ) from e

    if dest.exists():
        print(f"Already exists: {dest}")
        return

    print(f"Locating cached snapshot for {args.repo_id}…", flush=True)
    snapshot_dir = Path(
        snapshot_download(repo_id=args.repo_id, local_files_only=True)
    ).resolve()

    if not snapshot_dir.exists():
        raise SystemExit(f"Snapshot not found locally for {args.repo_id}.")

    dest.parent.mkdir(parents=True, exist_ok=True)

    print(f"Copying {snapshot_dir} -> {dest} (no symlinks)…", flush=True)
    shutil.copytree(snapshot_dir, dest, symlinks=False)

    total_bytes = 0
    for root, _, files in os.walk(dest):
        for name in files:
            try:
                total_bytes += os.path.getsize(os.path.join(root, name))
            except OSError:
                pass
    print(f"Done. Copied ~{total_bytes / (1024 * 1024):.1f} MB")


if __name__ == "__main__":
    main()
