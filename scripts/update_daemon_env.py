#!/usr/bin/env python3
"""Merge KEY=VALUE updates into a daemon .env file without touching unrelated
keys or comments. Reads a JSON object on stdin: {"path": "...", "updates":
{"KEY": "VALUE", ...}}. Values are never taken as argv (avoids process-list
exposure of secrets) and never echoed back.

Used by roles/claudeweb_console (env tag) so a partial .env update goes
through the exact same merge logic whether it's one key or all of them --
same code path as a full rewrite, just with a smaller `updates` dict.
"""
import json
import os
import sys
import tempfile


def merge(path, updates):
    lines = []
    if os.path.exists(path):
        with open(path) as f:
            lines = f.readlines()

    remaining = dict(updates)
    for i, line in enumerate(lines):
        stripped = line.strip()
        if not stripped or stripped.startswith("#") or "=" not in stripped:
            continue
        key = stripped.split("=", 1)[0].strip()
        if key in remaining:
            lines[i] = f"{key}={remaining.pop(key)}\n"

    if lines and not lines[-1].endswith("\n"):
        lines[-1] += "\n"
    for key, value in remaining.items():
        lines.append(f"{key}={value}\n")

    directory = os.path.dirname(path)
    os.makedirs(directory, exist_ok=True, mode=0o700)
    fd, tmp = tempfile.mkstemp(dir=directory)
    with os.fdopen(fd, "w") as f:
        f.writelines(lines)
    os.chmod(tmp, 0o600)
    os.replace(tmp, path)


def main():
    payload = json.load(sys.stdin)
    merge(payload["path"], payload["updates"])
    print(f"OK: merged {len(payload['updates'])} key(s) into {payload['path']}")


if __name__ == "__main__":
    main()
