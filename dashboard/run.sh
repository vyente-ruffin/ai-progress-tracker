#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
VENV_DIR="$SCRIPT_DIR/.venv"
PORT=9847

# Create venv if missing
if [ ! -d "$VENV_DIR" ]; then
  echo "Creating virtual environment…"
  python3 -m venv "$VENV_DIR"
fi

source "$VENV_DIR/bin/activate"

# Install Flask if missing
python3 -c "import flask" 2>/dev/null || pip install -q flask

echo "Starting AI Progress Tracker dashboard on port $PORT"
echo "  Local:   http://localhost:$PORT"
echo "  Network: http://$(ipconfig getifaddr en0 2>/dev/null || hostname -I 2>/dev/null | awk '{print $1}'):$PORT"
echo ""

python3 "$SCRIPT_DIR/app.py"
