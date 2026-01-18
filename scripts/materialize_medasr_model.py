#!/usr/bin/env python3
from __future__ import annotations

import argparse
import os
import shutil
import sys
from pathlib import Path


def main() -> None:
    parser = argparse.ArgumentParser(
        description="Copy the cached Hugging Face MedASR snapshot into ./models/medasr (no symlinks)."
    )
    parser.add_argument(
        "--repo-id",
        default="google/medasr",
        help="Hugging Face repo id (default: google/medasr)",
    )
    parser.add_argument(
        "--out",
        default="models/medasr",
        help="Destination directory under the repo (default: models/medasr)",
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

    print(f"Locating cached snapshot for {args.repo_id}…", flush=True)
    snapshot_dir = Path(
        snapshot_download(repo_id=args.repo_id, local_files_only=True)
    ).resolve()

    if not snapshot_dir.exists():
        raise SystemExit(f"Snapshot not found locally for {args.repo_id}.")

    if dest.exists():
        print(f"Already exists: {dest}")
        return

    dest.parent.mkdir(parents=True, exist_ok=True)

    print(f"Copying {snapshot_dir} -> {dest} (no symlinks)…", flush=True)
    shutil.copytree(snapshot_dir, dest, symlinks=False)

    size_mb = 0
    for root, _, files in os.walk(dest):
        for name in files:
            try:
                size_mb += os.path.getsize(os.path.join(root, name))
            except OSError:
                pass
    print(f"Done. Copied ~{size_mb / (1024 * 1024):.1f} MB")


if __name__ == "__main__":
    main()
