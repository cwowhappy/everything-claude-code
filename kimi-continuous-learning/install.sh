#!/bin/bash
# Kimi Continuous Learning — One-click Installer
#
# Usage:
#   curl -fsSL ... | bash
#   or
#   ./install.sh

set -e

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
LEARNING_DIR="${HOME}/.kimi/learning"
SKILLS_DIR="${HOME}/.kimi/skills/learned"
KIMI_CONFIG="${HOME}/.kimi/config.toml"

echo "═══════════════════════════════════════════════════════════════"
echo "  Kimi Code CLI Continuous Learning v2 — Installer"
echo "═══════════════════════════════════════════════════════════════"
echo ""

# ─────────────────────────────────────────────
# Pre-flight checks
# ─────────────────────────────────────────────

if [ ! -d "${HOME}/.kimi" ]; then
  echo "⚠️  ~/.kimi not found. Is Kimi Code CLI installed?" >&2
  echo "   Please install kimi-cli first: https://github.com/MoonshotAI/kimi-cli" >&2
  exit 1
fi

if ! command -v python3 >/dev/null 2>&1 && ! command -v python >/dev/null 2>&1; then
  echo "⚠️  Python is required but not found." >&2
  exit 1
fi

# ─────────────────────────────────────────────
# Create directories
# ─────────────────────────────────────────────

echo "📁 Creating directories..."
mkdir -p "${LEARNING_DIR}"/{
    hooks,scripts,agents,
    instincts/{personal,inherited,evolved/{skills,commands,agents}},
    projects
}
mkdir -p "${SKILLS_DIR}"

# ─────────────────────────────────────────────
# Copy scripts
# ─────────────────────────────────────────────

echo "📦 Installing scripts..."

cp "${SCRIPT_DIR}/hooks/observe.sh" "${LEARNING_DIR}/hooks/"
chmod +x "${LEARNING_DIR}/hooks/observe.sh"

cp "${SCRIPT_DIR}/scripts/instinct-cli.py" "${LEARNING_DIR}/scripts/"
chmod +x "${LEARNING_DIR}/scripts/instinct-cli.py"

cp "${SCRIPT_DIR}/scripts/detect-project.sh" "${LEARNING_DIR}/scripts/"
chmod +x "${LEARNING_DIR}/scripts/detect-project.sh"

cp "${SCRIPT_DIR}/agents/start-observer.sh" "${LEARNING_DIR}/agents/"
chmod +x "${LEARNING_DIR}/agents/start-observer.sh"

cp "${SCRIPT_DIR}/agents/observer-loop.sh" "${LEARNING_DIR}/agents/"
chmod +x "${LEARNING_DIR}/agents/observer-loop.sh"

# ─────────────────────────────────────────────
# Install default config
# ─────────────────────────────────────────────

if [ ! -f "${LEARNING_DIR}/config.toml" ]; then
  echo "⚙️  Creating default config..."
  cp "${SCRIPT_DIR}/config.default.toml" "${LEARNING_DIR}/config.toml"
else
  echo "⚙️  Config already exists at ${LEARNING_DIR}/config.toml (skipped)"
fi

# ─────────────────────────────────────────────
# Register Hooks in ~/.kimi/config.toml
# ─────────────────────────────────────────────

echo "🔗 Registering hooks in ~/.kimi/config.toml..."

HOOK_MARKER="kimi/learning/hooks/observe.sh"

if [ -f "$KIMI_CONFIG" ] && grep -q "$HOOK_MARKER" "$KIMI_CONFIG"; then
  echo "   Hooks already registered (skipped)"
else
  # Backup original config
  cp "$KIMI_CONFIG" "${KIMI_CONFIG}.backup.$(date +%Y%m%d-%H%M%S)"

  cat >> "$KIMI_CONFIG" << 'HOOKS'

# ─── Kimi Continuous Learning Hooks ───
[[hooks]]
event = "PreToolUse"
command = "~/.kimi/learning/hooks/observe.sh pre"
timeout = 5

[[hooks]]
event = "PostToolUse"
command = "~/.kimi/learning/hooks/observe.sh post"
timeout = 5

[[hooks]]
event = "SessionEnd"
command = "~/.kimi/learning/hooks/observe.sh stop"
timeout = 30
# ──────────────────────────────────────
HOOKS

  echo "   ✅ Hooks registered"
fi

# ─────────────────────────────────────────────
# Create symlink for evolved skills
# ─────────────────────────────────────────────

if [ ! -L "${SKILLS_DIR}" ] && [ ! -d "${SKILLS_DIR}" ]; then
  # If skills dir doesn't exist yet, we can make it a symlink
  # But if user already has skills there, don't overwrite
  true
elif [ ! -L "${SKILLS_DIR}" ]; then
  # Directory exists but is not a symlink — leave it, evolved skills will be copied
  true
fi

# ─────────────────────────────────────────────
# Install optional shell aliases
# ─────────────────────────────────────────────

echo ""
echo "═══════════════════════════════════════════════════════════════"
echo "  ✅ Installation complete!"
echo "═══════════════════════════════════════════════════════════════"
echo ""
echo "📍 Installation directory: ${LEARNING_DIR}"
echo ""
echo "🚀 Quick start:"
echo ""
echo "   # Check instinct status"
echo "   python3 ${LEARNING_DIR}/scripts/instinct-cli.py status"
echo ""
echo "   # Start the background observer"
echo "   ${LEARNING_DIR}/agents/start-observer.sh start"
echo ""
echo "   # Manually evolve instincts into skills"
echo "   python3 ${LEARNING_DIR}/scripts/instinct-cli.py evolve"
echo ""
echo "   # Stop observer"
echo "   ${LEARNING_DIR}/agents/start-observer.sh stop"
echo ""
echo "📝 Shell aliases (optional, add to ~/.bashrc or ~/.zshrc):"
echo ""
echo '   alias kl-status="python3 ~/.kimi/learning/scripts/instinct-cli.py status"'
echo '   alias kl-evolve="python3 ~/.kimi/learning/scripts/instinct-cli.py evolve"'
echo '   alias kl-promote="python3 ~/.kimi/learning/scripts/instinct-cli.py promote --auto"'
echo '   alias kl-observer="~/.kimi/learning/agents/start-observer.sh"'
echo ""
echo "⚠️  The background observer is NOT started automatically."
echo "   Run '${LEARNING_DIR}/agents/start-observer.sh start' to enable continuous analysis."
echo ""
echo "🔕 To disable: touch ${LEARNING_DIR}/disabled"
echo ""
