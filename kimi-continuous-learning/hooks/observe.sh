#!/bin/bash
# Kimi Continuous Learning v2 — Observation Hook
#
# Captures tool use events for pattern analysis.
# Kimi Code CLI passes hook data via stdin as JSON.
#
# Usage: observe.sh [pre|post|stop]
#   pre  → PreToolUse hook phase
#   post → PostToolUse hook phase
#   stop → SessionEnd hook phase (triggers observer)
#
# v2.0: Project-scoped observations — detects current project context
#       and writes observations to project-specific directory.

set -e

HOOK_PHASE="${1:-post}"

# ─────────────────────────────────────────────
# Read stdin first
# ─────────────────────────────────────────────
INPUT_JSON=$(cat)

if [ -z "$INPUT_JSON" ]; then
  exit 0
fi

# ─────────────────────────────────────────────
# Resolve Python
# ─────────────────────────────────────────────
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

PYTHON_CMD="$(resolve_python_cmd 2>/dev/null || true)"
if [ -z "$PYTHON_CMD" ]; then
  echo "[observe] No python interpreter found, skipping observation" >&2
  exit 0
fi

export CLV2_PYTHON_CMD="${CLV2_PYTHON_CMD:-$PYTHON_CMD}"

# ─────────────────────────────────────────────
# Extract cwd from stdin for project detection
# ─────────────────────────────────────────────
STDIN_CWD=$(echo "$INPUT_JSON" | "$PYTHON_CMD" -c "import json,sys; data=json.load(sys.stdin); print(data.get('cwd',''))" 2>/dev/null || echo "")

if [ -n "$STDIN_CWD" ] && [ -d "$STDIN_CWD" ]; then
  _GIT_ROOT=$(git -C "$STDIN_CWD" rev-parse --show-toplevel 2>/dev/null || true)
  export CLAUDE_PROJECT_DIR="${_GIT_ROOT:-$STDIN_CWD}"
fi

# ─────────────────────────────────────────────
# Lightweight config and automated session guards
# ─────────────────────────────────────────────

LEARNING_DIR="${HOME}/.kimi/learning"

# Skip if disabled
if [ -f "$LEARNING_DIR/disabled" ]; then
  exit 0
fi

# Layer 1: entrypoint filter
KIMI_ENTRYPOINT="${KIMI_CODE_ENTRYPOINT:-${CLAUDE_CODE_ENTRYPOINT:-cli}}"
case "$KIMI_ENTRYPOINT" in
  cli|sdk-ts|claude-desktop|kimi-desktop) ;;
  *) exit 0 ;;
esac

# Layer 2: minimal hook profile
[ "${ECC_HOOK_PROFILE:-standard}" = "minimal" ] && exit 0

# Layer 3: cooperative skip
[ "${ECC_SKIP_OBSERVE:-0}" = "1" ] && exit 0

# Layer 4: subagent sessions
_ECC_AGENT_ID=$(echo "$INPUT_JSON" | "$PYTHON_CMD" -c "import json,sys; print(json.load(sys.stdin).get('agent_id',''))" 2>/dev/null || true)
[ -n "$_ECC_AGENT_ID" ] && exit 0

# Layer 5: known observer-session path exclusions
_ECC_SKIP_PATHS="${ECC_OBSERVE_SKIP_PATHS:-observer-sessions,.kimi-mem,.claude-mem}"
if [ -n "$STDIN_CWD" ]; then
  IFS=',' read -ra _ECC_SKIP_ARRAY <<< "$_ECC_SKIP_PATHS"
  for _pattern in "${_ECC_SKIP_ARRAY[@]}"; do
    _pattern="${_pattern#"${_pattern%%[![:space:]]*}"}"
    _pattern="${_pattern%"${_pattern##*[![:space:]]}"}"
    [ -z "$_pattern" ] && continue
    case "$STDIN_CWD" in *"$_pattern"*) exit 0 ;; esac
  done
fi

# ─────────────────────────────────────────────
# Project detection
# ─────────────────────────────────────────────

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
SKILL_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"

# Source shared project detection helper
source "${SKILL_ROOT}/scripts/detect-project.sh" 2>/dev/null || {
  # Inline fallback if detect-project.sh is missing
  DETECT_CWD="${CLAUDE_PROJECT_DIR:-${PWD:-$(pwd)}}"
  _hash() {
    if command -v shasum >/dev/null 2>&1; then
      printf '%s' "$1" | shasum -a 256 2>/dev/null | cut -c1-12
    elif command -v md5sum >/dev/null 2>&1; then
      printf '%s' "$1" | md5sum 2>/dev/null | cut -c1-12
    else
      printf '%s' "$1" | cksum | cut -d' ' -f1
    fi
  }
  _REMOTE=$(git -C "$DETECT_CWD" remote get-url origin 2>/dev/null || true)
  if [ -n "$_REMOTE" ]; then
    PROJECT_ID="$(_hash "$_REMOTE")"
    PROJECT_ROOT="$(git -C "$DETECT_CWD" rev-parse --show-toplevel 2>/dev/null || echo "$DETECT_CWD")"
  else
    PROJECT_ROOT="$DETECT_CWD"
    PROJECT_ID="$(_hash "$PROJECT_ROOT")"
  fi
  PROJECT_NAME="$(basename "$PROJECT_ROOT")"
  export PROJECT_ID PROJECT_NAME PROJECT_ROOT PROJECT_DIR="$PROJECT_ROOT"
}

PYTHON_CMD="${CLV2_PYTHON_CMD:-$PYTHON_CMD}"

# ─────────────────────────────────────────────
# Ensure directories
# ─────────────────────────────────────────────

PROJECT_DIR_LEARNING="${LEARNING_DIR}/projects/${PROJECT_ID}"
mkdir -p "${PROJECT_DIR_LEARNING}"
mkdir -p "${LEARNING_DIR}/instincts/personal"
mkdir -p "${LEARNING_DIR}/instincts/inherited"
mkdir -p "${LEARNING_DIR}/instincts/evolved/skills"

# Update projects registry
PROJECTS_REGISTRY="${LEARNING_DIR}/projects.json"
if [ -f "$PROJECTS_REGISTRY" ] && [ -n "$PYTHON_CMD" ]; then
  "$PYTHON_CMD" -c "import json,sys,os; path=sys.argv[1]; proj_id=sys.argv[2]; proj_name=sys.argv[3]; proj_root=sys.argv[4]; now='$(date -u +%Y-%m-%dT%H:%M:%SZ)'; import json; data=json.load(open(path)) if os.path.exists(path) else {'projects':{}}; p=data.setdefault('projects',{}); p[proj_id]={'name':proj_name,'root':proj_root,'remote':'','first_seen':p.get(proj_id,{}).get('first_seen',now),'last_seen':now,'instinct_count':p.get(proj_id,{}).get('instinct_count',0)}; json.dump(data,open(path,'w'),indent=2)" "$PROJECTS_REGISTRY" "$PROJECT_ID" "$PROJECT_NAME" "$PROJECT_ROOT" 2>/dev/null || true
fi

# ─────────────────────────────────────────────
# Handle stop/sessionend phase
# ─────────────────────────────────────────────
if [ "$HOOK_PHASE" = "stop" ]; then
  # SessionEnd: trigger observer signal or perform lightweight session summary
  OBSERVER_PID_FILE="${PROJECT_DIR_LEARNING}/.observer.pid"
  if [ -f "$OBSERVER_PID_FILE" ]; then
    OBS_PID=$(cat "$OBSERVER_PID_FILE" 2>/dev/null || true)
    if [ -n "$OBS_PID" ] && kill -0 "$OBS_PID" 2>/dev/null; then
      kill -USR1 "$OBS_PID" 2>/dev/null || true
    fi
  fi
  exit 0
fi

# ─────────────────────────────────────────────
# Configuration
# ─────────────────────────────────────────────

OBSERVATIONS_FILE="${PROJECT_DIR_LEARNING}/observations.jsonl"
MAX_FILE_SIZE_MB=10

# Auto-purge old archives
PURGE_MARKER="${PROJECT_DIR_LEARNING}/.last-purge"
if [ ! -f "$PURGE_MARKER" ] || [ "$(find "$PURGE_MARKER" -mtime +1 2>/dev/null)" ]; then
  find "${PROJECT_DIR_LEARNING}" -name "observations-*.jsonl" -mtime +30 -delete 2>/dev/null || true
  touch "$PURGE_MARKER" 2>/dev/null || true
fi

# ─────────────────────────────────────────────
# Parse Kimi CLI hook JSON via Python (heredoc to avoid quote issues)
# ─────────────────────────────────────────────
PARSED=$(echo "$INPUT_JSON" | HOOK_PHASE="$HOOK_PHASE" "$PYTHON_CMD" -c "
import json, sys, os

try:
    data = json.load(sys.stdin)
except Exception as e:
    print(json.dumps({'parsed': False, 'error': str(e)}))
    sys.exit(0)

hook_phase = os.environ.get('HOOK_PHASE', 'post')
event = 'tool_start' if hook_phase == 'pre' else 'tool_complete'

# Kimi CLI hook format mapping
tool_name = data.get('tool_name', data.get('tool', 'unknown'))
tool_input = data.get('tool_input', data.get('input', {}))
tool_output = data.get('tool_response')
if tool_output is None:
    tool_output = data.get('tool_output', data.get('output', ''))
if tool_output is None:
    tool_output = ''

session_id = data.get('session_id', 'unknown')
tool_call_id = data.get('tool_call_id', data.get('tool_use_id', ''))
cwd = data.get('cwd', '')

# Truncate large inputs/outputs
if isinstance(tool_input, dict):
    tool_input_str = json.dumps(tool_input)[:5000]
else:
    tool_input_str = str(tool_input)[:5000]

if isinstance(tool_output, dict):
    tool_response_str = json.dumps(tool_output)[:5000]
else:
    tool_response_str = str(tool_output)[:5000]

print(json.dumps({
    'parsed': True,
    'event': event,
    'tool': tool_name,
    'input': tool_input_str if event == 'tool_start' else None,
    'output': tool_response_str if event == 'tool_complete' else None,
    'session': session_id,
    'tool_use_id': tool_call_id,
    'cwd': cwd
}))
")

PARSED_OK=$(echo "$PARSED" | "$PYTHON_CMD" -c "import json,sys; print(json.load(sys.stdin).get('parsed', False))" 2>/dev/null || echo "False")

if [ "$PARSED_OK" != "True" ]; then
  # Fallback: log raw input for debugging (scrubbed)
  timestamp=$(date -u +"%Y-%m-%dT%H:%M:%SZ")
  echo "$INPUT_JSON" | "$PYTHON_CMD" -c "
import json, sys, os, re
_SECRET_RE = re.compile(
    r'(?i)(api[_-]?key|token|secret|password|authorization|credentials?|auth)'
    r'([\"\\x27\s:=]+)'
    r'([A-Za-z]+\s+)?'
    r'([A-Za-z0-9_\-/.+=]{8,})'
)
raw = sys.stdin.read()[:2000]
raw = _SECRET_RE.sub(lambda m: m.group(1) + m.group(2) + (m.group(3) or '') + '[REDACTED]', raw)
print(json.dumps({'timestamp': os.environ.get('TIMESTAMP',''), 'event': 'parse_error', 'raw': raw}))
" >> "$OBSERVATIONS_FILE"
  exit 0
fi

# ─────────────────────────────────────────────
# Archive if file too large
# ─────────────────────────────────────────────
if [ -f "$OBSERVATIONS_FILE" ]; then
  file_size_mb=$(du -m "$OBSERVATIONS_FILE" 2>/dev/null | cut -f1)
  if [ "${file_size_mb:-0}" -ge "$MAX_FILE_SIZE_MB" ]; then
    archive_dir="${PROJECT_DIR_LEARNING}/observations.archive"
    mkdir -p "$archive_dir"
    mv "$OBSERVATIONS_FILE" "$archive_dir/observations-$(date +%Y%m%d-%H%M%S)-$$.jsonl" 2>/dev/null || true
  fi
fi

# ─────────────────────────────────────────────
# Build and write observation (scrub secrets)
# ─────────────────────────────────────────────
timestamp=$(date -u +"%Y-%m-%dT%H:%M:%SZ")
export PROJECT_ID_ENV="$PROJECT_ID"
export PROJECT_NAME_ENV="$PROJECT_NAME"
export TIMESTAMP="$timestamp"

echo "$PARSED" | "$PYTHON_CMD" -c "
import json, sys, os, re

parsed = json.load(sys.stdin)
observation = {
    'timestamp': os.environ.get('TIMESTAMP', ''),
    'event': parsed['event'],
    'tool': parsed['tool'],
    'session': parsed['session'],
    'project_id': os.environ.get('PROJECT_ID_ENV', 'global'),
    'project_name': os.environ.get('PROJECT_NAME_ENV', 'global')
}

# Scrub secrets
_SECRET_RE = re.compile(
    r'(?i)(api[_-]?key|token|secret|password|authorization|credentials?|auth)'
    r'([\"\\x27\s:=]+)'
    r'([A-Za-z]+\s+)?'
    r'([A-Za-z0-9_\-/.+=]{8,})'
)

def scrub(val):
    if val is None:
        return None
    return _SECRET_RE.sub(
        lambda m: m.group(1) + m.group(2) + (m.group(3) or '') + '[REDACTED]',
        str(val)
    )

if parsed.get('input'):
    observation['input'] = scrub(parsed['input'])
if parsed.get('output') is not None:
    observation['output'] = scrub(parsed['output'])

print(json.dumps(observation, ensure_ascii=False))
" >> "$OBSERVATIONS_FILE"

# ─────────────────────────────────────────────
# Throttle SIGUSR1 to observer
# ─────────────────────────────────────────────
SIGNAL_EVERY_N="${ECC_OBSERVER_SIGNAL_EVERY_N:-20}"
SIGNAL_COUNTER_FILE="${PROJECT_DIR_LEARNING}/.observer-signal-counter"

should_signal=0
if [ -f "$SIGNAL_COUNTER_FILE" ]; then
  counter=$(cat "$SIGNAL_COUNTER_FILE" 2>/dev/null || echo 0)
  counter=$((counter + 1))
  if [ "$counter" -ge "$SIGNAL_EVERY_N" ]; then
    should_signal=1
    counter=0
  fi
  echo "$counter" > "$SIGNAL_COUNTER_FILE"
else
  echo "1" > "$SIGNAL_COUNTER_FILE"
fi

if [ "$should_signal" -eq 1 ]; then
  OBSERVER_PID_FILE="${PROJECT_DIR_LEARNING}/.observer.pid"
  if [ -f "$OBSERVER_PID_FILE" ]; then
    observer_pid=$(cat "$OBSERVER_PID_FILE" 2>/dev/null || true)
    case "$observer_pid" in
      ''|*[!0-9]*|0|1) rm -f "$OBSERVER_PID_FILE" 2>/dev/null || true ;;
    esac
    if [ -n "$observer_pid" ] && kill -0 "$observer_pid" 2>/dev/null; then
      kill -USR1 "$observer_pid" 2>/dev/null || true
    fi
  fi
fi

exit 0
