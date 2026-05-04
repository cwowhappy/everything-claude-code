#!/bin/bash
# Kimi Continuous Learning — Observer Starter
#
# Ensures single-instance observer process using PID file + lock.
# Usage: start-observer.sh [start|stop|status|restart]

set -e

LEARNING_DIR="${HOME}/.kimi/learning"
AGENTS_DIR="${LEARNING_DIR}/agents"
OBSERVER_LOOP="${AGENTS_DIR}/observer-loop.sh"
PID_FILE="${LEARNING_DIR}/.observer.pid"
LOCK_FILE="${LEARNING_DIR}/.observer-start.lock"

# ─────────────────────────────────────────────
# Helpers
# ─────────────────────────────────────────────

_check_observer_running() {
  local pid_file="$1"
  if [ -f "$pid_file" ]; then
    local pid
    pid=$(cat "$pid_file" 2>/dev/null)
    case "$pid" in
      ''|*[!0-9]*|0|1)
        rm -f "$pid_file" 2>/dev/null || true
        return 1
        ;;
    esac
    if kill -0 "$pid" 2>/dev/null; then
      return 0
    fi
    rm -f "$pid_file" 2>/dev/null || true
  fi
  return 1
}

_start_observer() {
  if _check_observer_running "$PID_FILE"; then
    local pid
    pid=$(cat "$PID_FILE" 2>/dev/null)
    echo "[start-observer] Observer already running (PID: $pid)"
    return 0
  fi

  if [ ! -x "$OBSERVER_LOOP" ]; then
    echo "[start-observer] Error: observer-loop.sh not found or not executable: $OBSERVER_LOOP" >&2
    return 1
  fi

  echo "[start-observer] Starting observer..."

  # Use flock if available (Linux), fallback for macOS
  if command -v flock >/dev/null 2>&1; then
    (
      flock -n 9 || exit 0
      if ! _check_observer_running "$PID_FILE"; then
        nohup "$OBSERVER_LOOP" >/dev/null 2>&1 &
        echo $! > "$PID_FILE"
        echo "[start-observer] Started observer (PID: $!)"
      fi
    ) 9>"$LOCK_FILE"
  elif command -v lockfile >/dev/null 2>&1; then
    (
      trap 'rm -f "$LOCK_FILE" 2>/dev/null || true' EXIT
      lockfile -r 1 -l 30 "$LOCK_FILE" 2>/dev/null || exit 0
      if ! _check_observer_running "$PID_FILE"; then
        nohup "$OBSERVER_LOOP" >/dev/null 2>&1 &
        echo $! > "$PID_FILE"
        echo "[start-observer] Started observer (PID: $!)"
      fi
      rm -f "$LOCK_FILE" 2>/dev/null || true
    )
  else
    # POSIX fallback: mkdir is atomic
    (
      trap 'rmdir "${LOCK_FILE}.d" 2>/dev/null || true' EXIT
      mkdir "${LOCK_FILE}.d" 2>/dev/null || exit 0
      if ! _check_observer_running "$PID_FILE"; then
        nohup "$OBSERVER_LOOP" >/dev/null 2>&1 &
        echo $! > "$PID_FILE"
        echo "[start-observer] Started observer (PID: $!)"
      fi
    )
  fi
}

_stop_observer() {
  if [ -f "$PID_FILE" ]; then
    local pid
    pid=$(cat "$PID_FILE" 2>/dev/null)
    case "$pid" in
      ''|*[!0-9]*|0|1)
        rm -f "$PID_FILE" 2>/dev/null || true
        echo "[start-observer] No running observer."
        return 0
        ;;
    esac
    if kill -0 "$pid" 2>/dev/null; then
      kill -TERM "$pid" 2>/dev/null || true
      # Wait for process to exit
      for _ in $(seq 1 10); do
        if ! kill -0 "$pid" 2>/dev/null; then
          break
        fi
        sleep 0.5
      done
      rm -f "$PID_FILE" 2>/dev/null || true
      echo "[start-observer] Stopped observer (PID: $pid)."
    else
      rm -f "$PID_FILE" 2>/dev/null || true
      echo "[start-observer] Observer was not running."
    fi
  else
    echo "[start-observer] No PID file found."
  fi
}

_status_observer() {
  if _check_observer_running "$PID_FILE"; then
    local pid
    pid=$(cat "$PID_FILE" 2>/dev/null)
    echo "[start-observer] Observer is running (PID: $pid)."
    return 0
  else
    echo "[start-observer] Observer is not running."
    return 1
  fi
}

# ─────────────────────────────────────────────
# Main
# ─────────────────────────────────────────────

CMD="${1:-start}"

case "$CMD" in
  start)
    _start_observer
    ;;
  stop)
    _stop_observer
    ;;
  status)
    _status_observer
    ;;
  restart)
    _stop_observer
    sleep 1
    _start_observer
    ;;
  *)
    echo "Usage: $0 [start|stop|status|restart]"
    exit 1
    ;;
esac
