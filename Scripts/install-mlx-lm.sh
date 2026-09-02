#!/usr/bin/env bash
# MLX Studio — install mlx-lm into a dedicated virtual environment.
set -euo pipefail

SUPPORT_DIR="${HOME}/Library/Application Support/MLXStudio"
VENV_DIR="${SUPPORT_DIR}/venv"
PYTHON="${PYTHON:-python3}"

echo "==> MLX Studio: installing mlx-lm"
echo "    Support dir: ${SUPPORT_DIR}"
echo "    Python:      $(command -v "${PYTHON}" || echo "${PYTHON}")"

mkdir -p "${SUPPORT_DIR}"

if ! command -v "${PYTHON}" >/dev/null 2>&1; then
  echo "ERROR: Python 3 not found. Install Xcode Command Line Tools or Homebrew Python." >&2
  exit 1
fi

if [[ -d "${VENV_DIR}" ]]; then
  echo "==> Removing existing venv"
  rm -rf "${VENV_DIR}"
fi

echo "==> Creating virtual environment"
"${PYTHON}" -m venv "${VENV_DIR}"

echo "==> Upgrading pip"
"${VENV_DIR}/bin/python3" -m pip install --upgrade pip

echo "==> Installing mlx-lm[server]"
"${VENV_DIR}/bin/python3" -m pip install "mlx-lm[server]"

echo "==> Verifying"
VERSION=$("${VENV_DIR}/bin/python3" -c "import mlx_lm; print(getattr(mlx_lm, '__version__', 'installed'))")
echo "OK: mlx-lm ${VERSION} at ${VENV_DIR}/bin/python3"
