#!/usr/bin/env bash
# publish_temps.sh — Reads CPU and Coral TPU temperatures on the Proxmox node
# and publishes them to the MQTT broker.
#
# Deploy to Proxmox HOST (not a VM/LXC):
#   chmod +x /usr/local/bin/publish_temps.sh
#
# Add to root crontab (crontab -e):
#   * * * * * /usr/local/bin/publish_temps.sh
#
# Requirements on Proxmox host:
#   apt install mosquitto-clients bc

MQTT_BROKER="homeassistant.local"
MQTT_PORT="1883"
MQTT_USER=""        # set if broker requires auth
MQTT_PASS=""        # set if broker requires auth

TOPIC_CPU="homelab/proxmox/cpu_temp"
TOPIC_CORAL="homelab/proxmox/coral_tpu_temp"

# ── CPU Temperature ────────────────────────────────────────────────────────────
CPU_TEMP=""
for hwmon_dir in /sys/class/hwmon/hwmon*/; do
    name=$(cat "${hwmon_dir}name" 2>/dev/null)
    if [[ "$name" == "coretemp" || "$name" == "k10temp" || "$name" == "zenpower" ]]; then
        temp_raw=$(cat "${hwmon_dir}temp1_input" 2>/dev/null)
        if [[ -n "$temp_raw" ]]; then
            CPU_TEMP=$(echo "scale=1; $temp_raw / 1000" | bc)
            break
        fi
    fi
done

# fallback: acpitz (generic ACPI thermal)
if [[ -z "$CPU_TEMP" ]]; then
    for hwmon_dir in /sys/class/hwmon/hwmon*/; do
        name=$(cat "${hwmon_dir}name" 2>/dev/null)
        if [[ "$name" == "acpitz" ]]; then
            temp_raw=$(cat "${hwmon_dir}temp1_input" 2>/dev/null)
            if [[ -n "$temp_raw" ]]; then
                CPU_TEMP=$(echo "scale=1; $temp_raw / 1000" | bc)
                break
            fi
        fi
    done
fi

# ── Coral TPU Temperature ──────────────────────────────────────────────────────
CORAL_TEMP=""
if [[ -f /sys/class/apex/apex_0/temp ]]; then
    temp_raw=$(cat /sys/class/apex/apex_0/temp 2>/dev/null)
    if [[ -n "$temp_raw" ]]; then
        CORAL_TEMP=$(echo "scale=1; $temp_raw / 1000" | bc)
    fi
fi

# ── Publish ────────────────────────────────────────────────────────────────────
MQTT_ARGS=(-h "$MQTT_BROKER" -p "$MQTT_PORT")
[[ -n "$MQTT_USER" ]] && MQTT_ARGS+=(-u "$MQTT_USER" -P "$MQTT_PASS")

if [[ -n "$CPU_TEMP" ]]; then
    mosquitto_pub "${MQTT_ARGS[@]}" -t "$TOPIC_CPU" -m "$CPU_TEMP" -r
fi

if [[ -n "$CORAL_TEMP" ]]; then
    mosquitto_pub "${MQTT_ARGS[@]}" -t "$TOPIC_CORAL" -m "$CORAL_TEMP" -r
fi
