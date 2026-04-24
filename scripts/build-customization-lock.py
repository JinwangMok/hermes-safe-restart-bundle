#!/usr/bin/env python3
from __future__ import annotations

import argparse
import hashlib
import json
from pathlib import Path
from typing import Any
import fnmatch
import subprocess
import yaml
from datetime import datetime, timezone

ROOT = Path(__file__).resolve().parents[1]
DEFAULT_LOCK = ROOT / "customization-lock.yaml"


def sha256_bytes(data: bytes) -> str:
    return hashlib.sha256(data).hexdigest()


def iter_files(base: Path, includes: list[str], excludes: list[str]) -> list[Path]:
    found: set[Path] = set()
    for pattern in includes:
        for path in base.glob(pattern):
            if path.is_file():
                rel = path.relative_to(base)
                rel_str = rel.as_posix()
                if any(fnmatch.fnmatch(rel_str, ex) for ex in excludes):
                    continue
                found.add(path)
    return sorted(found)


def file_hashes(base: Path, includes: list[str], excludes: list[str]) -> tuple[str, list[dict[str, str]]]:
    entries = []
    h = hashlib.sha256()
    for path in iter_files(base, includes, excludes):
        rel = path.relative_to(base).as_posix()
        digest = sha256_bytes(path.read_bytes())
        entries.append({"path": rel, "sha256": digest})
        h.update(rel.encode())
        h.update(b"\0")
        h.update(digest.encode())
        h.update(b"\0")
    return h.hexdigest(), entries


def git_head(repo: Path) -> str | None:
    if not (repo / ".git").exists():
        return None
    try:
        completed = subprocess.run(
            ["git", "-C", str(repo), "rev-parse", "HEAD"],
            check=True,
            capture_output=True,
            text=True,
        )
        return completed.stdout.strip() or None
    except Exception:
        return None


def load_yaml(path: Path) -> dict[str, Any]:
    return yaml.safe_load(path.read_text(encoding="utf-8")) or {}


def main() -> int:
    parser = argparse.ArgumentParser()
    parser.add_argument("--lock", default=str(DEFAULT_LOCK))
    parser.add_argument("--output", default=str(ROOT / "reports" / "customization-lock.snapshot.json"))
    args = parser.parse_args()

    lock_path = Path(args.lock).expanduser().resolve()
    lock = load_yaml(lock_path)
    output = Path(args.output).expanduser().resolve()
    output.parent.mkdir(parents=True, exist_ok=True)

    bundles = []
    for rel_manifest in lock.get("bundles", []):
        manifest_path = (lock_path.parent / rel_manifest).resolve()
        manifest = load_yaml(manifest_path)
        repo_path = Path(manifest["repo_path"]).expanduser().resolve()
        fp = manifest.get("source_fingerprint", {})
        digest, files = file_hashes(repo_path, list(fp.get("include", [])), list(fp.get("exclude", [])))
        bundles.append(
            {
                "bundle_id": manifest["bundle_id"],
                "display_name": manifest.get("display_name"),
                "manifest_path": str(manifest_path),
                "repo_path": str(repo_path),
                "git_head": git_head(repo_path),
                "source_digest": digest,
                "file_count": len(files),
                "files": files,
                "apply_order": manifest.get("apply_order"),
                "target": manifest.get("target"),
                "install_script": manifest.get("install_script"),
                "verify_script": manifest.get("verify_script"),
                "managed_config_paths": manifest.get("managed_config_paths", []),
                "managed_runtime_paths": manifest.get("managed_runtime_paths", []),
                "managed_hermes_paths": manifest.get("managed_hermes_paths", []),
            }
        )

    result = {
        "generated_at": datetime.now(timezone.utc).isoformat(),
        "lock_path": str(lock_path),
        "hermes_repo": lock.get("hermes_repo"),
        "policies": lock.get("policies", {}),
        "bundles": bundles,
    }
    output.write_text(json.dumps(result, ensure_ascii=False, indent=2) + "\n", encoding="utf-8")
    print(str(output))
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
