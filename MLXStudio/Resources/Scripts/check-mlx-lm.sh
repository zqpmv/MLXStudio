#!/usr/bin/env bash
# MLX Studio — check whether mlx-lm is available.
set -euo pipefail

SUPPORT_DIR="${HOME}/Library/Application Support/MLXStudio"
VENV_PYTHON="${SUPPORT_DIR}/venv/bin/python3"

check_python() {
  local python_path="$1"
  local label="$2"
  if [[ -x "${python_path}" ]]; then
    if "${python_path}" -c "import mlx_lm; print(getattr(mlx_lm, '__version__', 'installed'))" 2>/dev/null; then
      echo "FOUND (${label}): ${python_path}"
      exit 0
    fi
  fi
}

echo "Checking bundled venv…"
check_python "${VENV_PYTHON}" "bundled venv" || true

for candidate in /opt/homebrew/bin/python3 /usr/local/bin/python3 /usr/bin/python3; do
  echo "Checking ${candidate}…"
  check_python "${candidate}" "system" || true
done

echo "NOT FOUND: mlx-lm is not installed"
exit 1
