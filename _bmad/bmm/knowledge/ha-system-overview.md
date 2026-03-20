# Home Assistant System Overview

## System
- **Platform:** Home Assistant OS on Raspberry Pi 4
- **Location:** Hod HaSharon, Israel
- **Coordinates:** 32.164358, 34.903672
- **Timezone:** Asia/Jerusalem
- **Scale:** 121 automations, 107 scripts, 3,619 entities, 363 devices, 73 integrations
- **Last Inventory:** 2026-03-20 — see `knowledge/inventory/inventory-index.md`

## Companion Hardware
- **Windows Desktop:** NVIDIA GTX 1080 Ti, Docker host
  - Frigate (object detection) at http://192.168.68.246:5000
  - Doubletake (face recognition)
  - Ollama (llama3.2-vision:11b — LLM fallback)

## Family
| Person | Entity | Mobile Notify | Role |
|--------|--------|---------------|------|
| Sharon | `person.sharon` | `notify.mobile_app_sharon_mobile` | Parent / Admin |
| Maayan | `person.maayan` | `notify.mobile_app_maayan_mobile` | Parent |
| Lenny | `person.lenny` | — | Child |
| Ofri | `person.ofri` | — | Child |
| Miley | — | — | Child (youngest) |

**Groups:** `notify.parentsmobile` (both parents), `notify.workingfromhome` (Sharon + Echo Show)

## Areas (14)
Bedroom (Parents), Lenny & Miley, Ofri, Kitchen, Living Room, Office, Hallway, Main Bathroom, Outdoor, Warehouse, Outdoor Hallway, Service Room, General

## Key Integrations
Zigbee2MQTT (dual), Tuya Cloud + Tuya Local, Shelly, NUKI Smart Lock, Yi Cameras, Reolink Doorbell, Frigate, Doubletake, Google Home, Alexa (native + Alexa Media Player HACS), Samsung TVs (samsungtv_tizen), Spotify/Spotcast, AWTRIX 3 (Ulanzi), Oref Alert, HebCal, LLM Vision, Broadlink remotes, iRobot Roomba, Google Drive Backup, Watchman, Govee (Matter + Govee2MQTT)

## Dual-Integration Devices
Native HA integrations are preferred, but HACS/community integrations run alongside when native lacks features:

| Device | Native | HACS / Community | Gap filled by HACS |
|--------|--------|------------------|--------------------|
| Alexa Echo | Alexa (HA native) | Alexa Media Player (HACS) | Volume control, TTS, media playback |
| Govee LED | Matter | Govee to MQTT Bridge (app → MQTT) | LED scenes and effects |
| Tuya | Tuya Cloud (`tuya`) | Tuya Local (`localtuya`) | Local speed, no cloud dependency |
| Samsung TV | — | samsungtv_tizen (HACS, patched) | Full TV control, WoL, sources |

## Network
| Service | Address |
|---------|---------|
| Home Assistant | `homeassistant.local:8123` |
| MQTT Broker | `core-mosquitto:1883` (internal) / `homeassistant.local:1883` (external) |
| Z2M Indoor | `tcp://192.168.68.189:6638` (SLZB-06M, Ember) |
| Z2M Outdoor | `tcp://192.168.68.188:6639` (SLZB-06, ZStack) |
| Z2M Frontend | Port 8099 |
| Frigate | `http://192.168.68.246:5000` |
| AWTRIX MQTT | `ulanzi/custom/*` / `ulanzi/notify` |

## Zigbee2MQTT Dual Instances
| Instance | Coordinator | MQTT Topic |
|----------|-------------|------------|
| Indoor | SLZB-06M @ tcp://192.168.68.189:6638 | `zigbee2mqtt` |
| Outdoor | SLZB-06 @ tcp://192.168.68.188:6639 | `zigbee2mqttout` |

## Configuration Architecture
Single `configuration.yaml` with `!include` for 18+ split files:
automations.yaml, scripts.yaml, scenes.yaml, camera.yaml, sensor.yaml, template.yaml, mqtt.yaml, light.yaml, media_player.yaml, notify.yaml, group.yaml, counter.yaml, input_boolean.yaml, input_datetime.yaml, input_number.yaml, input_text.yaml, input_select.yaml, shell_command.yaml, tts.yaml, recorder.yaml, ingress.yaml

## Entity Discovery Patterns
- Search config files: `grep -rn "entity_pattern"` across config
- Entity registry: `core.entity_registry`
- Naming: `{domain}.{room_or_device}_{function}`
- Person: `person.{first_name}`, notify via `notify.mobile_app_{first_name}_mobile`
- Tuya Local: search `tuya_local` domain in entity registry
- Room stops: `input_boolean.{room}room_stopautomation` or `input_boolean.toggle_hold{area}`

## Key Subsystems
- **Red Alert (Oref):** Cover snapshot/restore, TTS, AWTRIX display, mobile alerts
- **Doorbell:** Reolink → Frigate → Doubletake → AI description (Gemini/Ollama fallback)
- **Night Walker:** Motion-based nighttime navigation lights
- **Boiler Control:** Queued approval workflow for children's requests
- **Ceiling Fan:** Power-signature-based speed/light detection via Shelly sensors
- **Universal Notifier:** Presence-based, time-aware, multi-platform announcements (Jarvis)
