#!/usr/bin/env bash
set -euo pipefail

APP_NAME="apple-podcasts-transcriber"
MODEL_NAME="base"
MODEL_FILE="ggml-base.bin"
MODEL_URL="https://huggingface.co/ggerganov/whisper.cpp/resolve/main/${MODEL_FILE}"
PREFIX="${PREFIX:-${HOME}/.local}"
INSTALL_DIR=""
SKIP_BREW=0
SKIP_MODEL=0
SKIP_BUILD=0

usage() {
  cat <<'USAGE'
Usage:
  scripts/install.sh [options]

Installs local dependencies, downloads the default whisper.cpp model, builds the
release binary, and installs the CLI app.

Options:
  --prefix PATH       Install binary under PATH/bin. Default: ~/.local
  --install-dir PATH  Install binary directly into PATH. Overrides --prefix
  --model NAME        Whisper model name. Default: base
  --skip-brew         Do not install whisper-cpp with Homebrew
  --skip-model        Do not download the model file
  --skip-build        Do not run swift build -c release
  --help              Show this help

Examples:
  scripts/install.sh
  scripts/install.sh --prefix /usr/local
  scripts/install.sh --model small
USAGE
}

log() {
  printf '==> %s\n' "$1"
}

fail() {
  printf 'error: %s\n' "$1" >&2
  exit 1
}

while [[ $# -gt 0 ]]; do
  case "$1" in
    --prefix)
      [[ $# -ge 2 ]] || fail "missing value for --prefix"
      PREFIX="$2"
      shift 2
      ;;
    --install-dir)
      [[ $# -ge 2 ]] || fail "missing value for --install-dir"
      INSTALL_DIR="$2"
      shift 2
      ;;
    --model)
      [[ $# -ge 2 ]] || fail "missing value for --model"
      MODEL_NAME="$2"
      MODEL_FILE="ggml-${MODEL_NAME}.bin"
      MODEL_URL="https://huggingface.co/ggerganov/whisper.cpp/resolve/main/${MODEL_FILE}"
      shift 2
      ;;
    --skip-brew)
      SKIP_BREW=1
      shift
      ;;
    --skip-model)
      SKIP_MODEL=1
      shift
      ;;
    --skip-build)
      SKIP_BUILD=1
      shift
      ;;
    --help|-h)
      usage
      exit 0
      ;;
    *)
      fail "unknown option: $1"
      ;;
  esac
done

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "${SCRIPT_DIR}/.." && pwd)"
APP_SUPPORT_DIR="${HOME}/Library/Application Support/${APP_NAME}"
MODEL_DIR="${APP_SUPPORT_DIR}/models"
MODEL_PATH="${MODEL_DIR}/${MODEL_FILE}"
WHISPER_DIR="${APP_SUPPORT_DIR}/whisper.cpp"
WHISPER_BINARY_PATH="${WHISPER_DIR}/whisper-cli"
INSTALL_DIR="${INSTALL_DIR:-${PREFIX}/bin}"
RELEASE_BINARY="${REPO_ROOT}/.build/release/${APP_NAME}"
WHISPER_SOURCE_PATH=""

cd "${REPO_ROOT}"

if [[ "${SKIP_BREW}" -eq 0 ]]; then
  command -v brew >/dev/null 2>&1 || fail "Homebrew is required to install whisper-cpp. Install Homebrew or rerun with --skip-brew."

  if brew list whisper-cpp >/dev/null 2>&1; then
    log "whisper-cpp is already installed"
  else
    log "Installing whisper-cpp with Homebrew"
    brew install whisper-cpp
  fi
else
  log "Skipping Homebrew dependency install"
fi

if command -v whisper-cli >/dev/null 2>&1; then
  WHISPER_SOURCE_PATH="$(command -v whisper-cli)"
elif command -v brew >/dev/null 2>&1; then
  BREW_WHISPER_PREFIX="$(brew --prefix whisper-cpp 2>/dev/null || true)"
  if [[ -n "${BREW_WHISPER_PREFIX}" && -x "${BREW_WHISPER_PREFIX}/bin/whisper-cli" ]]; then
    WHISPER_SOURCE_PATH="${BREW_WHISPER_PREFIX}/bin/whisper-cli"
  fi
fi

if [[ -z "${WHISPER_SOURCE_PATH}" ]]; then
  fail "whisper-cli was not found after dependency installation."
fi

mkdir -p "${WHISPER_DIR}"
log "Symlinking whisper-cli to ${WHISPER_BINARY_PATH}"
ln -sf "${WHISPER_SOURCE_PATH}" "${WHISPER_BINARY_PATH}"

if [[ "${SKIP_MODEL}" -eq 0 ]]; then
  mkdir -p "${MODEL_DIR}"

  if [[ -f "${MODEL_PATH}" ]]; then
    log "Model already exists: ${MODEL_PATH}"
  else
    command -v curl >/dev/null 2>&1 || fail "curl is required to download ${MODEL_FILE}."
    log "Downloading ${MODEL_NAME} model to ${MODEL_PATH}"
    curl -L --fail --progress-bar -o "${MODEL_PATH}.tmp" "${MODEL_URL}"
    mv "${MODEL_PATH}.tmp" "${MODEL_PATH}"
  fi
else
  log "Skipping model download"
fi

if [[ "${SKIP_BUILD}" -eq 0 ]]; then
  command -v swift >/dev/null 2>&1 || fail "Swift is required to build the app."
  log "Building release binary"
  swift build -c release
else
  log "Skipping release build"
fi

[[ -x "${RELEASE_BINARY}" ]] || fail "release binary not found at ${RELEASE_BINARY}. Run without --skip-build first."

mkdir -p "${INSTALL_DIR}"
log "Installing ${APP_NAME} to ${INSTALL_DIR}/${APP_NAME}"
install -m 0755 "${RELEASE_BINARY}" "${INSTALL_DIR}/${APP_NAME}"

cat <<SUMMARY

Installed ${APP_NAME}.

Binary:
  ${INSTALL_DIR}/${APP_NAME}

Model:
  ${MODEL_PATH}

Whisper binary:
  ${WHISPER_BINARY_PATH}

Next steps:
  ${INSTALL_DIR}/${APP_NAME} --check-local-backend
  ${INSTALL_DIR}/${APP_NAME} --list

If ${INSTALL_DIR} is not on your PATH, add this to your shell profile:
  export PATH="${INSTALL_DIR}:\$PATH"
SUMMARY
