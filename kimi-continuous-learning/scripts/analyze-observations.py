#!/usr/bin/env python3
"""
Kimi Continuous Learning — Observation Analyzer

Reads observations.jsonl and generates/updates Instinct YAML files.
Called by observer-loop.sh.
"""

import json
import os
import re
import sys
from collections import Counter
from datetime import datetime, timezone


def load_instinct_meta(path: str) -> tuple[float, int, str]:
    """Return (confidence, observation_count, created_at) from existing instinct."""
    if not os.path.exists(path):
        return 0.5, 0, ""
    try:
        with open(path) as f:
            content = f.read()
        m = re.search(r"^confidence:\s*([0-9.]+)", content, re.M)
        conf = float(m.group(1)) if m else 0.5
        m = re.search(r"^observation_count:\s*([0-9]+)", content, re.M)
        count = int(m.group(1)) if m else 0
        m = re.search(r'^created_at:\s*"([^"]+)"', content, re.M)
        created = m.group(1) if m else ""
        return conf, count, created
    except Exception:
        return 0.5, 0, ""


def write_instinct(
    instinct_path: str,
    instinct_id: str,
    trigger: str,
    confidence: float,
    domain: str,
    scope: str,
    project_id: str,
    project_name: str,
    observation_count: int,
    created_at: str,
    body: str,
) -> None:
    now = datetime.now(timezone.utc).isoformat()
    if not created_at:
        created_at = now

    yaml_content = f"""---
id: {instinct_id}
trigger: "{trigger}"
confidence: {confidence:.2f}
domain: {domain}
scope: {scope}
source: session-observation
project_id: "{project_id}"
project_name: "{project_name}"
created_at: "{created_at}"
updated_at: "{now}"
observation_count: {observation_count}
---

{body}
"""
    os.makedirs(os.path.dirname(instinct_path), exist_ok=True)
    with open(instinct_path, "w") as f:
        f.write(yaml_content)
    print(f"[observer] Updated instinct: {instinct_id} (confidence: {confidence:.2f})")


def analyze(obs_file: str, instincts_dir: str, project_id: str, project_name: str) -> None:
    if not os.path.exists(obs_file):
        return

    try:
        with open(obs_file) as f:
            lines = f.readlines()[-200:]
    except Exception:
        lines = []

    observations = []
    for line in lines:
        try:
            observations.append(json.loads(line))
        except json.JSONDecodeError:
            continue

    if not observations:
        print(f"[observer] No valid observations in {obs_file}")
        return

    # Detect tool sequences (3-grams)
    sequences = []
    for i in range(len(observations) - 2):
        tools = [observations[j].get("tool", "unknown") for j in range(i, i + 3)]
        sequences.append(" → ".join(tools))

    seq_counts = Counter(sequences)
    common = seq_counts.most_common(10)

    now = datetime.now(timezone.utc).isoformat()

    # Heuristic 1: Grep → Read → Edit pattern
    grep_edit_count = sum(
        c for s, c in common if "grep" in s.lower() and "edit" in s.lower()
    )
    if grep_edit_count >= 1:
        instinct_id = "grep-before-edit"
        instinct_path = os.path.join(instincts_dir, f"{instinct_id}.yaml")
        existing_conf, existing_count, created_at = load_instinct_meta(instinct_path)
        new_count = existing_count + grep_edit_count
        new_conf = min(0.9, existing_conf + 0.05)
        body = (
            f"# Grep Before Edit\n\n"
            f"## Action\n"
            f"Always use Grep to locate content before using Edit or WriteFile.\n\n"
            f"## Evidence\n"
            f"- Observed {new_count} tool sequences involving Grep → Edit\n"
            f"- Project: {project_name}\n"
        )
        write_instinct(
            instinct_path, instinct_id,
            "when asked to modify existing code files",
            new_conf, "workflow", "project",
            project_id, project_name, new_count,
            created_at, body,
        )

    # Heuristic 2: Read → Write pattern
    read_write_count = sum(
        c for s, c in common if "read" in s.lower() and "write" in s.lower()
    )
    if read_write_count >= 1:
        instinct_id = "read-before-write"
        instinct_path = os.path.join(instincts_dir, f"{instinct_id}.yaml")
        existing_conf, existing_count, created_at = load_instinct_meta(instinct_path)
        new_count = existing_count + read_write_count
        new_conf = min(0.9, existing_conf + 0.05)
        body = (
            f"# Read Before Write\n\n"
            f"## Action\n"
            f"Always read existing files before writing to avoid data loss.\n\n"
            f"## Evidence\n"
            f"- Observed {new_count} tool sequences involving Read → Write\n"
            f"- Project: {project_name}\n"
        )
        write_instinct(
            instinct_path, instinct_id,
            "when asked to create or overwrite files",
            new_conf, "workflow", "project",
            project_id, project_name, new_count,
            created_at, body,
        )

    # Heuristic 3: Shell → Read (checking existence)
    shell_read_count = sum(
        c for s, c in common if "shell" in s.lower() and "read" in s.lower()
    )
    if shell_read_count >= 1:
        instinct_id = "check-existence-before-read"
        instinct_path = os.path.join(instincts_dir, f"{instinct_id}.yaml")
        existing_conf, existing_count, created_at = load_instinct_meta(instinct_path)
        new_count = existing_count + shell_read_count
        new_conf = min(0.9, existing_conf + 0.05)
        body = (
            f"# Check Existence Before Read\n\n"
            f"## Action\n"
            f"Verify file or directory exists before attempting to read it.\n\n"
            f"## Evidence\n"
            f"- Observed {new_count} sequences checking existence before reading\n"
            f"- Project: {project_name}\n"
        )
        write_instinct(
            instinct_path, instinct_id,
            "when accessing files that may not exist",
            new_conf, "debugging", "project",
            project_id, project_name, new_count,
            created_at, body,
        )

    # Heuristic 4: Single-tool preference — ReadFile
    tool_counts = Counter(o.get("tool", "unknown") for o in observations)
    if tool_counts.get("ReadFile", 0) >= 3:
        instinct_id = "read-before-modify"
        instinct_path = os.path.join(instincts_dir, f"{instinct_id}.yaml")
        existing_conf, existing_count, created_at = load_instinct_meta(instinct_path)
        new_count = existing_count + tool_counts["ReadFile"]
        new_conf = min(0.9, existing_conf + 0.05)
        body = (
            f"# Read Before Modify\n\n"
            f"## Action\n"
            f"Always read files before attempting to modify them.\n\n"
            f"## Evidence\n"
            f"- Observed {new_count} ReadFile operations in this project\n"
            f"- Project: {project_name}\n"
        )
        write_instinct(
            instinct_path, instinct_id,
            "when asked to read or modify files",
            new_conf, "workflow", "project",
            project_id, project_name, new_count,
            created_at, body,
        )

    print(f"[observer] Analysis complete for {project_id}.")


if __name__ == "__main__":
    if len(sys.argv) < 4:
        print("Usage: analyze-observations.py <obs_file> <instincts_dir> <project_id> [project_name]")
        sys.exit(1)
    analyze(sys.argv[1], sys.argv[2], sys.argv[3], sys.argv[4] if len(sys.argv) > 4 else sys.argv[3])
