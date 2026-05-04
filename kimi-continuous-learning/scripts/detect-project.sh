#!/bin/bash
# detect-project.sh — Project detection helper for Kimi Continuous Learning
#
# Sets environment variables:
#   PROJECT_ID      — 12-char hash (portable across machines for git repos)
#   PROJECT_NAME    — human-readable project name
#   PROJECT_ROOT    — absolute path to project root
#   PROJECT_DIR     — alias for PROJECT_ROOT
#
# Detection priority:
#   1. KIMI_PROJECT_DIR env var
#   2. git remote get-url origin → SHA256
#   3. Kimi CLI work_dirs match from ~/.kimi/kimi.json
#   4. git rev-parse --show-toplevel
#   5. cwd itself (fallback)

set -e

# Resolve Python command (honors CLV2_PYTHON_CMD if already set)
resolve_python_cmd() {
  if [ -n "${CLV2_PYTHON_CMD:-}" ] && command -v "$CLV2_PYTHON_CMD" >/dev/null 2>&1; then
    printf '%s\n' "$CLV2_PYTHON_CMD"
    return 0
  fi
  if command -v python3 >/dev/null 2>&1; then
    printf '%s\n' python3
    return 0
  fi
  if command -v python >/dev/null 2>&1; then
    printf '%s\n' python
    return 0
  fi
  return 1
}

PYTHON_CMD="${CLV2_PYTHON_CMD:-$(resolve_python_cmd 2>/dev/null || true)}"

# ─────────────────────────────────────────────
# Detect project from cwd (passed via env or computed)
# ─────────────────────────────────────────────

DETECT_CWD="${CLAUDE_PROJECT_DIR:-${PWD:-$(pwd)}}"

# Helper: hash a string to 12 chars
_hash() {
  if [ -n "$PYTHON_CMD" ]; then
    printf '%s' "$1" | "$PYTHON_CMD" -c 'import sys, hashlib; print(hashlib.sha256(sys.stdin.read().encode()).hexdigest()[:12])'
  else
    # Fallback: use shasum or md5
    if command -v shasum >/dev/null 2>&1; then
      printf '%s' "$1" | shasum -a 256 | cut -c1-12
    elif command -v md5sum >/dev/null 2>&1; then
      printf '%s' "$1" | md5sum | cut -c1-12
    else
      printf '%s' "$1" | cksum | cut -d' ' -f1
    fi
  fi
}

# 1. KIMI_PROJECT_DIR env var
if [ -n "${KIMI_PROJECT_DIR:-}" ]; then
  PROJECT_ROOT="$KIMI_PROJECT_DIR"
  PROJECT_NAME="$(basename "$PROJECT_ROOT")"
  PROJECT_ID="$(_hash "$PROJECT_ROOT")"
  export PROJECT_ID PROJECT_NAME PROJECT_ROOT PROJECT_DIR
  return 0 2>/dev/null || true
fi

# 2. git remote get-url origin → portable hash
try_remote() {
  local _cwd="$1"
  local _remote
  _remote=$(git -C "$_cwd" remote get-url origin 2>/dev/null || true)
  if [ -n "$_remote" ]; then
    PROJECT_ID="$(_hash "$_remote")"
    PROJECT_ROOT="$(git -C "$_cwd" rev-parse --show-toplevel 2>/dev/null || echo "$_cwd")"
    PROJECT_NAME="$(basename "$PROJECT_ROOT")"
    export PROJECT_ID PROJECT_NAME PROJECT_ROOT PROJECT_DIR
    return 0
  fi
  return 1
}

if try_remote "$DETECT_CWD"; then
  return 0 2>/dev/null || true
fi

# 3. Kimi CLI work_dirs match from ~/.kimi/kimi.json
try_kimi_workdirs() {
  local _cwd="$1"
  local _kimi_json="${HOME}/.kimi/kimi.json"
  if [ ! -f "$_kimi_json" ] || [ -z "$PYTHON_CMD" ]; then
    return 1
  fi

  local _match
  _match=$("$PYTHON_CMD" -c '
import json, sys, os
cwd = sys.argv[1]
kimi_json = os.path.expanduser("~/.kimi/kimi.json")
try:
    with open(kimi_json) as f:
        data = json.load(f)
    for entry in data.get("work_dirs", []):
        path = entry.get("path", "")
        if cwd.startswith(path):
            print(path)
            break
except Exception:
    pass
' "$_cwd" 2>/dev/null || true)

  if [ -n "$_match" ]; then
    PROJECT_ROOT="$_match"
    PROJECT_NAME="$(basename "$PROJECT_ROOT")"
    PROJECT_ID="$(_hash "$PROJECT_ROOT")"
    export PROJECT_ID PROJECT_NAME PROJECT_ROOT PROJECT_DIR
    return 0
  fi
  return 1
}

if try_kimi_workdirs "$DETECT_CWD"; then
  return 0 2>/dev/null || true
fi

# 4. git rev-parse --show-toplevel
try_git_root() {
  local _cwd="$1"
  local _root
  _root=$(git -C "$_cwd" rev-parse --show-toplevel 2>/dev/null || true)
  if [ -n "$_root" ]; then
    PROJECT_ROOT="$_root"
    PROJECT_NAME="$(basename "$PROJECT_ROOT")"
    PROJECT_ID="$(_hash "$PROJECT_ROOT")"
    export PROJECT_ID PROJECT_NAME PROJECT_ROOT PROJECT_DIR
    return 0
  fi
  return 1
}

if try_git_root "$DETECT_CWD"; then
  return 0 2>/dev/null || true
fi

# 5. Fallback: cwd itself
PROJECT_ROOT="$DETECT_CWD"
PROJECT_NAME="$(basename "$PROJECT_ROOT")"
PROJECT_ID="$(_hash "$PROJECT_ROOT")"
export PROJECT_ID PROJECT_NAME PROJECT_ROOT PROJECT_DIR
