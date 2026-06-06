#!/usr/bin/env bash
set -euo pipefail

MODELS_DIR="${MODELS_DIR:-/models}"
BLUE_DIR="${MODELS_DIR}/blue-onnx"
RENIKUD_PATH="${MODELS_DIR}/renikud.onnx"
VOICES_DIR="${MODELS_DIR}/voices"

mkdir -p "${BLUE_DIR}" "${VOICES_DIR}"

# One-time download of BlueTTS ONNX bundle
if [ ! -f "${BLUE_DIR}/.downloaded" ]; then
  echo "[entrypoint] Downloading notmax123/blue-onnx to ${BLUE_DIR}..."
  python - <<PY
from huggingface_hub import snapshot_download
snapshot_download(
    repo_id="notmax123/blue-onnx",
    repo_type="model",
    local_dir="${BLUE_DIR}",
)
PY
  touch "${BLUE_DIR}/.downloaded"
fi

# One-time download of renikud (Hebrew nikud) model
if [ ! -f "${RENIKUD_PATH}" ]; then
  echo "[entrypoint] Downloading renikud model to ${RENIKUD_PATH}..."
  curl -fL --retry 3 -o "${RENIKUD_PATH}" \
    "https://huggingface.co/thewh1teagle/renikud/resolve/main/model.onnx"
fi

# Voices live in the BlueTTS GitHub repo, not the HF model bundle.
# Fetch female1 + male1 on first run into the named volume.
if [ -z "$(ls -A "${VOICES_DIR}" 2>/dev/null || true)" ]; then
  echo "[entrypoint] Fetching voice JSONs from BlueTTS GitHub..."
  for v in female1 male1; do
    curl -fL --retry 3 -o "${VOICES_DIR}/${v}.json" \
      "https://raw.githubusercontent.com/maxmelichov/BlueTTS/main/voices/${v}.json" \
      || echo "[entrypoint] WARN: failed to fetch ${v}.json"
  done
fi

echo "[entrypoint] Launching FastAPI on :8000"
exec uvicorn server:app --host 0.0.0.0 --port 8000 --workers 1
