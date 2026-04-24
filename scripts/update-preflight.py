#!/usr/bin/env python3
from __future__ import annotations

import argparse
import fnmatch
import json
import subprocess
from dataclasses import dataclass
from datetime import datetime, timezone
from pathlib import Path
from typing import Any
import yaml

ROOT = Path(__file__).resolve().parents[1]
DEFAULT_LOCK = ROOT / "customization-lock.yaml"
DEFAULT_REPORT = ROOT / "reports" / "update-preflight-report.json"


@dataclass
class Bundle:
    bundle_id: str
    manifest_path: Path
    data: dict[str, Any]


def load_yaml(path: Path) -> dict[str, Any]:
    return yaml.safe_load(path.read_text(encoding="utf-8")) or {}


def git_status(repo: Path) -> list[dict[str, str]]:
    out = subprocess.check_output(["git", "-C", str(repo), "status", "--porcelain"], text=True)
    rows = []
    for line in out.splitlines():
        if not line.strip():
            continue
        code = line[:2]
        path = line[3:]
        rows.append({"code": code, "path": path})
    return rows


def git_rev_parse(repo: Path, ref: str) -> str | None:
    try:
        out = subprocess.check_output(["git", "-C", str(repo), "rev-parse", ref], text=True)
    except Exception:
        return None
    value = out.strip()
    return value or None


def git_diff_name_only(repo: Path, left: str, right: str) -> list[str]:
    try:
        out = subprocess.check_output(
            ["git", "-C", str(repo), "diff", "--name-only", f"{left}..{right}"],
            text=True,
        )
    except Exception:
        return ["<git-diff-failed>"]
    return [line.strip() for line in out.splitlines() if line.strip()]


def matches_any(path: str, patterns: list[str]) -> bool:
    return any(fnmatch.fnmatch(path, pat) or path.startswith(pat.rstrip("*")) for pat in patterns)


def current_digest_for_manifest(manifest: dict[str, Any]) -> str:
    from hashlib import sha256
    base = Path(manifest["repo_path"]).expanduser().resolve()
    include = list(manifest.get("source_fingerprint", {}).get("include", []))
    exclude = list(manifest.get("source_fingerprint", {}).get("exclude", []))
    h = sha256()
    found: set[Path] = set()
    for pattern in include:
        for path in base.glob(pattern):
            if not path.is_file():
                continue
            rel = path.relative_to(base).as_posix()
            if any(fnmatch.fnmatch(rel, ex) for ex in exclude):
                continue
            found.add(path)
    for path in sorted(found):
        rel = path.relative_to(base).as_posix()
        digest = sha256(path.read_bytes()).hexdigest()
        h.update(rel.encode())
        h.update(b"\0")
        h.update(digest.encode())
        h.update(b"\0")
    return h.hexdigest()


def main() -> int:
    parser = argparse.ArgumentParser()
    parser.add_argument("--lock", default=str(DEFAULT_LOCK))
    parser.add_argument("--snapshot", default=str(ROOT / "reports" / "customization-lock.snapshot.json"))
    parser.add_argument("--output", default=str(DEFAULT_REPORT))
    args = parser.parse_args()

    lock_path = Path(args.lock).expanduser().resolve()
    lock = load_yaml(lock_path)
    snapshot = json.loads(Path(args.snapshot).expanduser().resolve().read_text(encoding="utf-8"))
    snapshot_by_id = {item["bundle_id"]: item for item in snapshot["bundles"]}

    bundles = []
    for rel_manifest in lock.get("bundles", []):
        manifest_path = (lock_path.parent / rel_manifest).resolve()
        data = load_yaml(manifest_path)
        bundles.append(Bundle(bundle_id=data["bundle_id"], manifest_path=manifest_path, data=data))

    hermes_repo = Path(lock["hermes_repo"]).expanduser().resolve()
    hermes_status = git_status(hermes_repo)

    managed_paths = sorted({path for bundle in bundles for path in bundle.data.get("managed_hermes_paths", [])})
    ignored_untracked: list[str] = []

    disallowed_targets = []
    disallowed_managed_paths = []
    for bundle in bundles:
        target = str(bundle.data.get("target", "")).strip().lower()
        if target == "hermes":
            disallowed_targets.append(bundle.bundle_id)
        if bundle.data.get("managed_hermes_paths"):
            disallowed_managed_paths.append(bundle.bundle_id)

    unmanaged = []
    for row in hermes_status:
        path = row["path"]
        if matches_any(path, managed_paths):
            continue
        if row["code"] == "??" and matches_any(path, ignored_untracked):
            continue
        unmanaged.append(row)

    bundle_reports = []
    fingerprint_mismatches = []
    for bundle in bundles:
        expected = snapshot_by_id.get(bundle.bundle_id, {})
        current_digest = current_digest_for_manifest(bundle.data)
        mismatch = expected.get("source_digest") != current_digest
        if mismatch:
            fingerprint_mismatches.append(bundle.bundle_id)
        bundle_reports.append(
            {
                "bundle_id": bundle.bundle_id,
                "manifest_path": str(bundle.manifest_path),
                "expected_source_digest": expected.get("source_digest"),
                "current_source_digest": current_digest,
                "mismatch": mismatch,
                "target": bundle.data.get("target"),
                "managed_hermes_paths": bundle.data.get("managed_hermes_paths", []),
            }
        )

    hermes_head = git_rev_parse(hermes_repo, "HEAD")
    origin_main_head = git_rev_parse(hermes_repo, "origin/main")
    origin_tree_diff = []
    if hermes_head and origin_main_head:
        origin_tree_diff = git_diff_name_only(hermes_repo, "origin/main", "HEAD")
    else:
        origin_tree_diff = ["<origin-main-unavailable>"]

    blockers = []
    if unmanaged:
        blockers.append("Hermes checkout has unmanaged dirty paths")
    if fingerprint_mismatches:
        blockers.append("Bundle source fingerprint mismatch detected")
    if disallowed_targets:
        blockers.append("Bundle lock contains Hermes source mutation targets")
    if disallowed_managed_paths:
        blockers.append("Bundle lock contains managed_hermes_paths entries")
    if origin_tree_diff:
        blockers.append("Hermes checkout content differs from origin/main")

    result = {
        "generated_at": datetime.now(timezone.utc).isoformat(),
        "lock_path": str(lock_path),
        "snapshot_path": str(Path(args.snapshot).expanduser().resolve()),
        "hermes_repo": str(hermes_repo),
        "policies": lock.get("policies", {}),
        "managed_hermes_paths": managed_paths,
        "ignored_untracked_paths": ignored_untracked,
        "hermes_head": hermes_head,
        "origin_main_head": origin_main_head,
        "origin_main_tree_diff": origin_tree_diff,
        "hermes_status": hermes_status,
        "unmanaged_dirty_paths": unmanaged,
        "disallowed_source_mutation_targets": disallowed_targets,
        "disallowed_managed_hermes_path_bundles": disallowed_managed_paths,
        "bundle_reports": bundle_reports,
        "blockers": blockers,
        "ready": not blockers,
    }

    output = Path(args.output).expanduser().resolve()
    output.parent.mkdir(parents=True, exist_ok=True)
    output.write_text(json.dumps(result, ensure_ascii=False, indent=2) + "\n", encoding="utf-8")
    print(str(output))
    if blockers:
        for blocker in blockers:
            print(f"BLOCKER: {blocker}")
        return 1
    print("READY")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
