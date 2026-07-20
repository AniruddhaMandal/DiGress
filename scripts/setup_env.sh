#!/usr/bin/env bash
# DiGress environment setup: author's exact pinned versions (README), via pip + venv, no conda.
#   torch 2.0.1 / cuda 11.8 / torch_geometric 2.3.1 / python 3.9
#
# Usage (run on the LAB machine):
#   chmod +x scripts/setup_env.sh
#   ./scripts/setup_env.sh

set -euo pipefail

if [ -n "${VIRTUAL_ENV:-}" ]; then
  echo "ERROR: a venv (${VIRTUAL_ENV}) is already active in this shell."
  echo "Run 'deactivate', or better, open a brand-new terminal, then rerun this script."
  echo "(Do NOT 'source' this script - run it as ./scripts/setup_env.sh or bash scripts/setup_env.sh,"
  echo " otherwise venv activation leaks into your interactive shell across runs.)"
  exit 1
fi

# Resolve the true system python3 up front, by absolute path, so later steps
# (after the venv is activated and PATH is shadowed) can't accidentally re-resolve
# the wrong interpreter via a bare `python3` lookup.
SYSTEM_PYTHON3="$(command -v python3)"

VENV_DIR="${HOME}/.venvs/digress"
PY_VERSION="3.9"

. /etc/os-release   # sets ID, VERSION_CODENAME
CODENAME="${VERSION_CODENAME:-$(lsb_release -s -c)}"
echo "== Detected: ${ID} ${CODENAME}"

echo "== [1/6] Ensuring python${PY_VERSION} is available"
if command -v "python${PY_VERSION}" >/dev/null 2>&1; then
  echo "python${PY_VERSION} already installed, skipping."
elif [ "${ID}" = "ubuntu" ]; then
  sudo apt-get update
  sudo apt-get install -y software-properties-common
  sudo add-apt-repository -y ppa:deadsnakes/ppa
  sudo apt-get update
  sudo apt-get install -y "python${PY_VERSION}" "python${PY_VERSION}-venv" "python${PY_VERSION}-dev"
else
  # No deadsnakes on Debian: build python3.9 from source via pyenv instead.
  echo "Non-Ubuntu distro detected - installing python${PY_VERSION} via pyenv (source build)."
  sudo apt-get update
  sudo apt-get install -y build-essential libssl-dev zlib1g-dev libbz2-dev libreadline-dev \
    libsqlite3-dev curl git libncursesw5-dev xz-utils tk-dev libxml2-dev libxmlsec1-dev \
    libffi-dev liblzma-dev
  if [ ! -d "${HOME}/.pyenv" ]; then
    curl -fsSL https://pyenv.run | bash
  fi
  export PYENV_ROOT="${HOME}/.pyenv"
  export PATH="${PYENV_ROOT}/bin:${PATH}"
  eval "$(pyenv init -)"
  pyenv install -s 3.9.18
  pyenv shell 3.9.18
  PY_VERSION="3.9.18"
fi
PYTHON_BIN="$(command -v python${PY_VERSION} || echo ${PYENV_ROOT:-}/versions/3.9.18/bin/python3.9)"
echo "Using ${PYTHON_BIN} ($(${PYTHON_BIN} --version))"

echo "== [2/6] Installing graph-tool from skewed.de (needs sudo)"
TMP_DEB="$(mktemp -d)/skewed-keyring.deb"
wget -O "${TMP_DEB}" "https://downloads.skewed.de/skewed-keyring/skewed-keyring_1.5_all_${CODENAME}.deb"
sudo dpkg -i "${TMP_DEB}"
echo "deb [signed-by=/usr/share/keyrings/skewed-keyring.gpg] https://downloads.skewed.de/apt ${CODENAME} main" \
  | sudo tee /etc/apt/sources.list.d/skewed.list > /dev/null
sudo apt-get update
sudo apt-get install -y python3-graph-tool g++
echo "Checking with system python3: ${SYSTEM_PYTHON3} ($(${SYSTEM_PYTHON3} --version))"
"${SYSTEM_PYTHON3}" -c 'import graph_tool as gt' \
  || { echo "graph-tool not importable from system python3 - aborting"; exit 1; }

echo "== [3/6] Creating venv at ${VENV_DIR} with ${PYTHON_BIN} (--system-site-packages)"
"${PYTHON_BIN}" -m venv --system-site-packages "${VENV_DIR}"
# shellcheck disable=SC1091
source "${VENV_DIR}/bin/activate"

echo "== [4/6] Checking graph-tool is visible inside the venv"
SYS_PY_VER="$(${SYSTEM_PYTHON3} --version | awk '{print $2}' | cut -d. -f1,2)"
if ! python3 -c 'import graph_tool as gt' 2>/tmp/gt_import_error.log; then
  echo
  echo "ERROR: graph-tool is not importable inside the venv. Real error:"
  echo "----------------------------------------------------------------"
  cat /tmp/gt_import_error.log
  echo "----------------------------------------------------------------"
  echo "Diagnostics: venv python is $(python3 -c 'import sys; print(sys.executable)')"
  echo "             true system python3 (${SYSTEM_PYTHON3}) is version ${SYS_PY_VER}, venv was built with ${PY_VERSION}"
  echo "pyvenv.cfg:"
  cat "${VENV_DIR}/pyvenv.cfg"
  deactivate
  exit 1
fi
echo "OK: graph-tool importable in venv."

echo "== [5/6] Installing pinned torch/deps + DiGress"
pip install --upgrade pip
pip install torch==2.0.1 --index-url https://download.pytorch.org/whl/cu118
REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
pip install -r "${REPO_ROOT}/requirements.txt"
pip install -e "${REPO_ROOT}"

echo "== [6/6] Compiling orca"
( cd "${REPO_ROOT}/src/analysis/orca" && g++ -O2 -std=c++11 -o orca orca.cpp )

echo
echo "Done. Activate with: source ${VENV_DIR}/bin/activate"
echo "Sanity check with:   python3 ${REPO_ROOT}/main.py +experiment=debug.yaml"
