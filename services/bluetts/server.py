"""BlueTTS FastAPI wrapper — exposes a minimal REST endpoint for HA rest_command."""
from __future__ import annotations

import io
import os
import time
import uuid
from pathlib import Path
from threading import Lock

import soundfile as sf
from fastapi import FastAPI, HTTPException
from fastapi.responses import FileResponse, JSONResponse
from pydantic import BaseModel

MODELS_DIR = Path(os.environ.get("MODELS_DIR", "/models"))
AUDIO_DIR = Path(os.environ.get("AUDIO_DIR", "/audio"))
BLUE_DIR = MODELS_DIR / "blue-onnx"
RENIKUD_PATH = MODELS_DIR / "renikud.onnx"
VOICES_DIR = MODELS_DIR / "voices"
DEFAULT_VOICE = os.environ.get("BLUETTS_DEFAULT_VOICE", "female1")
AUDIO_TTL_SECONDS = int(os.environ.get("AUDIO_TTL_SECONDS", "300"))

AUDIO_DIR.mkdir(parents=True, exist_ok=True)

_tts_lock = Lock()
_tts_cache: dict[str, object] = {}


def _load_tts(voice: str):
    """Lazily construct a BlueTTS instance for the requested voice."""
    if voice in _tts_cache:
        return _tts_cache[voice]

    style_path = VOICES_DIR / f"{voice}.json"
    if not style_path.exists():
        raise HTTPException(status_code=400, detail=f"voice '{voice}' not found at {style_path}")

    from blue_onnx import BlueTTS  # imported lazily — heavy

    with _tts_lock:
        if voice not in _tts_cache:
            _tts_cache[voice] = BlueTTS(
                onnx_dir=str(BLUE_DIR),
                style_json=str(style_path),
                renikud_path=str(RENIKUD_PATH),
            )
    return _tts_cache[voice]


def _gc_audio() -> None:
    """Drop WAVs older than AUDIO_TTL_SECONDS."""
    cutoff = time.time() - AUDIO_TTL_SECONDS
    for wav in AUDIO_DIR.glob("*.wav"):
        try:
            if wav.stat().st_mtime < cutoff:
                wav.unlink(missing_ok=True)
        except OSError:
            pass


class SynthesizeRequest(BaseModel):
    text: str
    lang: str = "he"
    voice: str | None = None


app = FastAPI(title="BlueTTS HA Bridge", version="0.1.0")


@app.get("/health")
def health() -> JSONResponse:
    voices = sorted(p.stem for p in VOICES_DIR.glob("*.json")) if VOICES_DIR.exists() else []
    ready = BLUE_DIR.exists() and RENIKUD_PATH.exists() and bool(voices)
    return JSONResponse(
        {
            "status": "ok" if ready else "initializing",
            "voices": voices,
            "default_voice": DEFAULT_VOICE,
            "models_ready": ready,
        }
    )


@app.post("/synthesize")
def synthesize(req: SynthesizeRequest) -> JSONResponse:
    if not req.text.strip():
        raise HTTPException(status_code=400, detail="text is empty")

    voice = req.voice or DEFAULT_VOICE
    tts = _load_tts(voice)

    samples, sr = tts.synthesize(req.text, lang=req.lang)

    _gc_audio()
    audio_id = uuid.uuid4().hex
    out_path = AUDIO_DIR / f"{audio_id}.wav"
    sf.write(out_path, samples, sr)

    return JSONResponse(
        {
            "id": audio_id,
            "url": f"/audio/{audio_id}.wav",
            "sample_rate": sr,
            "voice": voice,
            "lang": req.lang,
        }
    )


@app.get("/audio/{audio_id}.wav")
def get_audio(audio_id: str):
    # Guard against path traversal — only accept hex ids.
    if not all(c in "0123456789abcdef" for c in audio_id) or not audio_id:
        raise HTTPException(status_code=400, detail="invalid id")
    path = AUDIO_DIR / f"{audio_id}.wav"
    if not path.exists():
        raise HTTPException(status_code=404, detail="expired or unknown")
    return FileResponse(path, media_type="audio/wav")
