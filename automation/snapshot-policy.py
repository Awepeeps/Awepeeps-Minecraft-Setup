#!/usr/bin/env python3
"""Export only validated, non-identifying gameplay policy from live properties."""

from __future__ import annotations

import argparse
import json
import os
import re
import stat
import tempfile
from pathlib import Path


SLUG_RE = re.compile(r"^[a-z0-9]+(?:-[a-z0-9]+)*$")
BOOL_KEYS = {
    "white-list", "enforce-whitelist", "online-mode", "pvp", "allow-nether",
    "spawn-monsters", "spawn-animals", "hardcore", "force-gamemode",
    "enable-command-block", "prevent-proxy-connections", "hide-online-players",
}
ENUM_KEYS = {"difficulty": {"peaceful", "easy", "normal", "hard"},
             "gamemode": {"survival", "creative", "adventure", "spectator"}}
INTEGER_KEYS = {
    "view-distance": (2, 32),
    "simulation-distance": (2, 32),
    "max-players": (1, 1000),
    "spawn-protection": (0, 1000),
    "player-idle-timeout": (0, 10000),
    "entity-broadcast-range-percentage": (10, 1000),
}
ALLOWED_KEYS = BOOL_KEYS | set(ENUM_KEYS) | set(INTEGER_KEYS)


def validate_slug(value: str, label: str) -> str:
    if not SLUG_RE.fullmatch(value):
        raise ValueError(f"{label} must be a lowercase alphanumeric slug")
    return value


def parse_properties(text: str) -> dict[str, str]:
    """Parse key=value lines without interpreting or returning unknown values."""
    result: dict[str, str] = {}
    for raw in text.splitlines():
        line = raw.strip()
        if not line or line.startswith(("#", "!")) or "=" not in line:
            continue
        key, value = line.split("=", 1)
        result[key.strip()] = value.strip()
    return result


def build_policy(properties: dict[str, str]) -> dict[str, object]:
    output: dict[str, object] = {}
    for key in sorted(ALLOWED_KEYS):
        if key not in properties:
            continue
        value = properties[key].strip()
        if key in BOOL_KEYS:
            normalized = value.lower()
            if normalized not in {"true", "false"}:
                raise ValueError(f"invalid boolean value for {key}")
            output[key] = normalized == "true"
        elif key in ENUM_KEYS:
            normalized = value.lower()
            if normalized not in ENUM_KEYS[key]:
                raise ValueError(f"invalid enum value for {key}")
            output[key] = normalized
        else:
            if not re.fullmatch(r"[0-9]+", value):
                raise ValueError(f"invalid integer value for {key}")
            number = int(value)
            lower, upper = INTEGER_KEYS[key]
            if not lower <= number <= upper:
                raise ValueError(f"integer value out of range for {key}")
            output[key] = number
    return {"schema_version": 1, "policy": output}


def safe_source(server_dir: Path, filename: str) -> Path:
    if server_dir.is_symlink():
        raise ValueError("refusing symlink SERVER_DIR")
    base = server_dir.resolve(strict=True)
    candidate = server_dir / filename
    if candidate.is_symlink():
        raise ValueError(f"refusing symlink source: {filename}")
    resolved = candidate.resolve(strict=True)
    if not resolved.is_relative_to(base) or not resolved.is_file():
        raise ValueError(f"source must be a regular file under SERVER_DIR: {filename}")
    return resolved


def atomic_write(repo_dir: Path, output_path: Path, payload: bytes) -> None:
    repo = repo_dir.resolve(strict=True)
    relative = output_path.absolute().relative_to(repo)
    parent_parts = relative.parts[:-1]
    parent = repo
    for part in parent_parts:
        parent = parent / part
        if parent.is_symlink():
            raise ValueError("refusing symlink output directory component")
        if parent.exists():
            resolved = parent.resolve(strict=True)
            if not resolved.is_relative_to(repo):
                raise ValueError("output directory must remain inside REPO_DIR")
        else:
            parent.mkdir()
    if output_path.is_symlink():
        raise ValueError("refusing symlink output")
    if output_path.exists() and not output_path.is_file():
        raise ValueError("output path must be a regular file")

    fd, temporary = tempfile.mkstemp(prefix=".snapshot-policy-", dir=parent)
    try:
        os.fchmod(fd, stat.S_IRUSR | stat.S_IWUSR)
        with os.fdopen(fd, "wb") as stream:
            stream.write(payload)
            stream.flush()
            os.fsync(stream.fileno())
        os.replace(temporary, output_path)
    except BaseException:
        try:
            os.unlink(temporary)
        except FileNotFoundError:
            pass
        raise


def main() -> int:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--repo-dir", required=True, type=Path)
    parser.add_argument("--server-dir", required=True, type=Path)
    parser.add_argument("--server-slug", required=True)
    parser.add_argument("--season-slug", required=True)
    args = parser.parse_args()
    try:
        server_slug = validate_slug(args.server_slug, "server slug")
        season_slug = validate_slug(args.season_slug, "season slug")
        source = safe_source(args.server_dir, "server.properties")
        raw = source.read_text(encoding="utf-8", errors="strict")
        document = build_policy(parse_properties(raw))
        payload = (json.dumps(document, sort_keys=True, indent=2) + "\n").encode()
        destination = (args.repo_dir / "seasons" / server_slug / season_slug /
                      "policy.json")
        atomic_write(args.repo_dir, destination, payload)
    except (OSError, UnicodeError, ValueError):
        parser.error("snapshot generation failed validation or safe file handling; no source content was exported")
    print(f"Generated sanitized policy: seasons/{server_slug}/{season_slug}/policy.json")
    print("Review the diff manually before any Git staging or publication.")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
