#!/usr/bin/env bash
# MLX Studio — remove bundled mlx-lm virtual environment.
set -euo pipefail

VENV_DIR="${HOME}/Library/Application Support/MLXStudio/venv"

if [[ -d "${VENV_DIR}" ]]; then
  rm -rf "${VENV_DIR}"
  echo "Removed ${VENV_DIR}"
else
  echo "Nothing to remove."
fi
