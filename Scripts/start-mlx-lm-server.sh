#!/usr/bin/env bash
# MLX Studio — start mlx-lm OpenAI-compatible server.
set -euo pipefail

SUPPORT_DIR="${HOME}/Library/Application Support/MLXStudio"
VENV_PYTHON="${SUPPORT_DIR}/venv/bin/python3"
HOST="${MLX_HOST:-127.0.0.1}"
PORT="${MLX_PORT:-8080}"
MODEL="${MLX_MODEL:-}"

if [[ -x "${VENV_PYTHON}" ]] && "${VENV_PYTHON}" -c "import mlx_lm" 2>/dev/null; then
  PYTHON="${VENV_PYTHON}"
elif python3 -c "import mlx_lm" 2>/dev/null; then
  PYTHON="$(command -v python3)"
else
  echo "ERROR: mlx-lm not found. Run install-mlx-lm.sh first." >&2
  exit 1
fi

ARGS=(-m mlx_lm.server --host "${HOST}" --port "${PORT}")
if [[ -n "${MODEL}" ]]; then
  ARGS+=(--model "${MODEL}")
fi

echo "Starting mlx-lm server at http://${HOST}:${PORT}"
exec "${PYTHON}" "${ARGS[@]}"
