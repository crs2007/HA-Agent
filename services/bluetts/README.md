# BlueTTS HA Bridge

Minimal Docker service that wraps [BlueTTS](https://github.com/maxmelichov/BlueTTS) with a FastAPI REST endpoint so Home Assistant can call it via `rest_command`.

**Runs on:** Proxmox LXC 100 (`docker-frigate`, `192.168.68.30`), deployed as a separate Portainer stack — does not touch the existing Frigate stack.

## Endpoints

| Method | Path                  | Purpose                                              |
|--------|-----------------------|------------------------------------------------------|
| GET    | `/health`             | Liveness + list of available voices                  |
| POST   | `/synthesize`         | Body `{text, lang="he", voice?}` → returns JSON `{id, url, sample_rate, voice, lang}` |
| GET    | `/audio/{id}.wav`     | Fetch the synthesized WAV (5-min TTL)                |

## First-run behavior

On first container start, `entrypoint.sh` downloads:
- `notmax123/blue-onnx` → `/models/blue-onnx/` (~1.5 GB)
- `thewh1teagle/renikud/model.onnx` → `/models/renikud.onnx`

These land in the named volume `bluetts-models`, so rebuilds don't re-download. Initial startup can take 5–10 min depending on bandwidth — the healthcheck has a 120 s start_period and the `/health` endpoint returns `status:"initializing"` until files are present.

## Deploy via Portainer

1. Copy the three files (`Dockerfile`, `server.py`, `entrypoint.sh`, `docker-compose.yml`) into LXC 100 at e.g. `/opt/bluetts/`.
2. Portainer → Stacks → Add stack → "Upload from repository" or paste the compose file.
3. First `docker compose up -d --build` will build the image (pip install + model download on first start).
4. Verify: `curl http://192.168.68.30:8088/health`.

## Smoke test

```bash
curl -X POST http://192.168.68.30:8088/synthesize \
  -H "Content-Type: application/json" \
  -d '{"text":"שלום, זאת בדיקה","lang":"he"}' | jq
# → {"id":"...","url":"/audio/....wav","sample_rate":...}

curl -o test.wav http://192.168.68.30:8088/audio/<id>.wav
```

## Resource caps

CPU capped at **2.0 cores**, memory at **2 GB** — prevents synthesis bursts from starving Frigate detection sharing the same LXC.

## HA integration

See [`../../configuration/`](../..) for the `rest_command.bluetts_say` and `script.bluetts_announce` additions (next step of the PoC).
