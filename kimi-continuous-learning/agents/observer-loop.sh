#!/bin/bash
# Kimi Continuous Learning — Observer Loop
#
# Background process that periodically reads observations.jsonl,
# detects patterns, and creates/updates Instinct YAML files.
#
# Trigger modes:
#   - SIGUSR1: immediate analysis (from observe.sh)
#   - Timer: wakes every N minutes (configurable)

set -e

LEARNING_DIR="${HOME}/.kimi/learning"
CONFIG_FILE="${LEARNING_DIR}/config.toml"
PID_FILE="${LEARNING_DIR}/.observer.pid"

# ─────────────────────────────────────────────
# Load config with shell-friendly defaults
# ─────────────────────────────────────────────
RUN_INTERVAL_MINUTES=5
MIN_OBSERVATIONS=20
MODEL="kimi-mini"

if [ -f "$CONFIG_FILE" ]; then
  # Extract values using grep/sed (minimal TOML parsing)
  _val=$(grep -E "^run_interval_minutes\s*=" "$CONFIG_FILE" 2>/dev/null | sed 's/.*=\s*//' | tr -d ' "')
  [ -n "$_val" ] && RUN_INTERVAL_MINUTES="$_val"
  _val=$(grep -E "^min_observations_to_analyze\s*=" "$CONFIG_FILE" 2>/dev/null | sed 's/.*=\s*//' | tr -d ' "')
  [ -n "$_val" ] && MIN_OBSERVATIONS="$_val"
  _val=$(grep -E "^model\s*=" "$CONFIG_FILE" 2>/dev/null | sed 's/.*=\s*//' | tr -d ' "')
  [ -n "$_val" ] && MODEL="$_val"
fi

RUN_INTERVAL_SECONDS=$((RUN_INTERVAL_MINUTES * 60))

# ─────────────────────────────────────────────
# Resolve Python
# ─────────────────────────────────────────────
PYTHON_CMD="${CLV2_PYTHON_CMD:-$(command -v python3 || command -v python || echo '')}"

# ─────────────────────────────────────────────
# Signal handling
# ─────────────────────────────────────────────
SIGUSR1_RECEIVED=0

trap 'SIGUSR1_RECEIVED=1' USR1
trap 'rm -f "$PID_FILE"; exit 0' EXIT INT TERM

# Write PID
echo $$ > "$PID_FILE"

echo "[observer] Started. PID=$$. Interval=${RUN_INTERVAL_MINUTES}m. Min_obs=${MIN_OBSERVATIONS}."

# ─────────────────────────────────────────────
# Analysis function
# ─────────────────────────────────────────────
analyze_project() {
  local proj_dir="$1"
  local obs_file="${proj_dir}/observations.jsonl"
  local instincts_dir="${proj_dir}/instincts/personal"
  local project_id
  project_id=$(basename "$proj_dir")

  if [ ! -f "$obs_file" ]; then
    return 0
  fi

  local obs_count
  obs_count=$(wc -l < "$obs_file" 2>/dev/null || echo 0)
  if [ "$obs_count" -lt "$MIN_OBSERVATIONS" ]; then
    echo "[observer] Project ${project_id}: only ${obs_count} observations, skipping (< ${MIN_OBSERVATIONS})"
    return 0
  fi

  echo "[observer] Analyzing project ${project_id} (${obs_count} observations)..."
  mkdir -p "$instincts_dir"

  # Run analysis via external Python script (avoids shell quote issues)
  ANALYZER_SCRIPT="${LEARNING_DIR}/scripts/analyze-observations.py"
  if [ -f "$ANALYZER_SCRIPT" ] && [ -n "$PYTHON_CMD" ]; then
    _proj_name=$(cat "${proj_dir}/project.json" 2>/dev/null | grep '"name"' | sed 's/.*: "\([^"]*\)".*/\1/' || echo "$project_id")
    "$PYTHON_CMD" "$ANALYZER_SCRIPT" "$obs_file" "$instincts_dir" "$project_id" "$_proj_name" 2>&1 || true
  fi
}

# ─────────────────────────────────────────────
# Main loop
# ─────────────────────────────────────────────
while true; do
  SIGUSR1_RECEIVED=0

  # Analyze all projects
  if [ -d "${LEARNING_DIR}/projects" ]; then
    for proj_dir in "${LEARNING_DIR}"/projects/*/; do
      [ -d "$proj_dir" ] || continue
      analyze_project "$proj_dir"
    done
  fi

  # Wait for signal or timeout
  # Use `sleep` in chunks to allow signal interruption
  elapsed=0
  while [ "$elapsed" -lt "$RUN_INTERVAL_SECONDS" ]; do
    if [ "$SIGUSR1_RECEIVED" -eq 1 ]; then
      SIGUSR1_RECEIVED=0
      break
    fi
    sleep 1
    elapsed=$((elapsed + 1))
  done
done
