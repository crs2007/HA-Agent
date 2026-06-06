# BlueTTS — HA Integration (Step 3)

Three small, additive changes to the live HA config. The existing `smart_announcement_universal_notifier` and Google TTS path are **not touched** in this step — the new script is parallel and opt-in.

> **⚠️ Live-instance-first rule.** Before pasting, use File Editor / Studio Code Server / SSH on the live HA host to open each target file **live**. The snapshots under `_bmad/bmm/knowledge/inventory/raw/` can be weeks stale. If the live file looks different, trust the live instance and merge the new block in manually.

## 1. `configuration.yaml` — add `rest_command`

Open `/config/configuration.yaml` on the HA host. Append the contents of [rest_command.bluetts.yaml](rest_command.bluetts.yaml).

If a top-level `rest_command:` key already exists, place `bluetts_say:` under it rather than adding a second key.

## 2. `scripts.yaml` — add `bluetts_announce`

Open `/config/scripts.yaml`. Append the contents of [script.bluetts_announce.yaml](script.bluetts_announce.yaml) as a new top-level entry.

## 3. `input_boolean.yaml` — add toggle

Open `/config/input_boolean.yaml`. Append [input_boolean.bluetts.yaml](input_boolean.bluetts.yaml).

## 4. Reload

Dev Tools → **YAML configuration reloading** →
- Reload *Rest Commands*
- Reload *Scripts*
- Reload *Input Booleans*

(Or just restart HA if unsure.)

## 5. Smoke test

Dev Tools → **Services** → call `script.bluetts_announce`:

```yaml
service: script.bluetts_announce
data:
  message: שלום, זאת בדיקה של BlueTTS
  target: media_player.kitchen_google_home   # swap for an actual Google Home entity you own
```

Expected: Kitchen speaker plays the Hebrew phrase in the BlueTTS voice.

## 6. Troubleshooting

| Symptom | Check |
|---------|-------|
| Script logs `BlueTTS synth failed: status=` | `curl http://192.168.68.30:8088/health` from the HA host shell — is the container up? |
| `status=200` but speaker silent | Open `http://192.168.68.30:8088<url>` in a browser on the same LAN. If the WAV plays there, the issue is `media_player.play_media` (wrong entity_id, or the speaker can't reach that IP). |
| Hebrew pronunciation wrong | BlueTTS uses renikud for nikud. Try adding nikud to the text manually, or file as a voice-quality note for the go/no-go review. |
| Container shows `status:"initializing"` | First-run model download still running. Watch `docker compose logs -f bluetts` on LXC 100. |

## 7. Language-aware wrapper (optional, Step 3b)

If BlueTTS quality looks good, add a second script that routes **Hebrew → BlueTTS, other → Google TTS** automatically:

Append [script.smart_announce.yaml](script.smart_announce.yaml) to `/config/scripts.yaml` and reload scripts.

Call it like:

```yaml
service: script.smart_announce
data:
  message: ארוחת הערב מוכנה!
  speakers:
    - media_player.kitchen_google_home
    - media_player.living_room_echo
  voice: female1   # optional, only used when BlueTTS is chosen
```

Non-Hebrew examples fall through to `tts.google_translate_say` automatically. If BlueTTS is unreachable the script **also** falls back to Google TTS (with a warning in the system log), so this is safe to start calling from automations today.

Scope note: this is a standalone primitive — it does **not** replace `smart_announcement_universal_notifier`. Telegram/mobile push still go through the existing notifier. Migrating that notifier to use BlueTTS for Hebrew would require a change to the `universal_notifier` custom Python component; deferred.

## 8. Rollback

`input_boolean.use_bluetts` exists for future A/B wiring inside `smart_announcement_universal_notifier` (next step). For now, rollback is simply: stop calling `script.bluetts_announce`. The Google TTS path is untouched and keeps working.
