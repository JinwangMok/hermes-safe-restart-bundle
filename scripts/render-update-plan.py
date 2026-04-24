#!/usr/bin/env python3
from __future__ import annotations

import argparse
import json
from pathlib import Path
from typing import Any
import yaml

ROOT = Path(__file__).resolve().parents[1]
DEFAULT_LOCK = ROOT / "customization-lock.yaml"


def load_yaml(path: Path) -> dict[str, Any]:
    return yaml.safe_load(path.read_text(encoding="utf-8")) or {}


def main() -> int:
    parser = argparse.ArgumentParser()
    parser.add_argument("--lock", default=str(DEFAULT_LOCK))
    args = parser.parse_args()

    lock_path = Path(args.lock).expanduser().resolve()
    lock = load_yaml(lock_path)
    bundles = []
    for rel_manifest in lock.get("bundles", []):
        manifest_path = (lock_path.parent / rel_manifest).resolve()
        manifest = load_yaml(manifest_path)
        bundles.append(
            {
                "bundle_id": manifest["bundle_id"],
                "display_name": manifest.get("display_name"),
                "apply_order": int(manifest.get("apply_order", 1000)),
                "install_script": manifest.get("install_script"),
                "verify_script": manifest.get("verify_script"),
                "repo_path": manifest.get("repo_path"),
                "target": manifest.get("target"),
            }
        )
    bundles.sort(key=lambda item: item["apply_order"])
    print(json.dumps({"bundles": bundles}, ensure_ascii=False))
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
