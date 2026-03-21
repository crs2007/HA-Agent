# Helpers

**Total: 39 helpers across 7 types**

| Helper Type | Count |
|-------------|-------|
| Input Boolean | 7 |
| Input Number | 1 |
| Input Select | 2 |
| Input Text | 13 |
| Input Datetime | 6 |
| Counter | 5 |
| Group | 2 |

---

## Input Boolean

| Entity ID | Name | Icon | Initial |
|-----------|------|------|---------|
| input_boolean.red_alert_test | Test Alert | mdi:alert-circle | off |
| input_boolean.zigbee2mqtt_restart_in_progress | Zigbee2MQTT Restart In Progress | mdi:restart-alert | — |
| input_boolean.zigbee_health_alert_active | Zigbee Health Alert Active | mdi:zigbee | — |
| input_boolean.tuya_restart_in_progress | Tuya Restart In Progress | mdi:restart-alert | — |
| input_boolean.washing_machine_active | Washing Machine Active | mdi:washing-machine | — |
| input_boolean.calendar_all_day_event | All Day Event | mdi:calendar-today | — |
| input_boolean.week_planner_refresh | Week Planner Refresh | mdi:refresh | — |

## Input Number

| Entity ID | Name | Min | Max | Step | Initial |
|-----------|------|-----|-----|------|---------|
| input_number.volume_night_mode | Night Mode Volume | 0 | 1 | 0.05 | 0.1 |

## Input Select

| Entity ID | Name | Icon | Options | Initial |
|-----------|------|------|---------|---------|
| input_select.calendar_select | Calendar / Person Select | mdi:account-multiple | ימי הולדת, משפחה, גוגל | משפחה |
| input_select.calendar_view | Calendar View | mdi:calendar-month | היום, מחר, שבוע, שבועיים, חודש, חודשיים | חודש |

## Input Text

| Entity ID | Name | Icon | Max | Mode | Initial |
|-----------|------|------|-----|------|---------|
| input_text.red_alert | Last Alert in Israel | — | 255 | — | — |
| input_text.red_alert_status | Red Alert Status | mdi:shield-check | 255 | — | (status string) |
| input_text.hallway_ai_description | Hallway AI Description | — | 255 | — | SYSTEM READY. WAITING FOR EVENTS... |
| input_text.livingroom_ai_description | Living Room AI Description | — | 255 | — | SYSTEM READY. WAITING FOR EVENTS... |
| input_text.livingroomfront_ai_description | Living Room Front AI Description | — | 255 | — | SYSTEM READY. WAITING FOR EVENTS... |
| input_text.calendar_event_title | Calendar Event Title | — | 100 | text | — |
| input_text.calendar_event_description | Calendar Event Description | — | 255 | text | — |
| input_text.sharon_calendar_filter | Sharon Calendar Filter | — | 100 | text | .* |
| input_text.maayan_calendar_filter | Maayan Calendar Filter | — | 100 | text | .* |
| input_text.lenny_calendar_filter | Lenny Calendar Filter | — | 100 | text | .* |
| input_text.miley_calendar_filter | Miley Calendar Filter | — | 100 | text | .* |
| input_text.ofri_calendar_filter | Ofri Calendar Filter | — | 100 | text | .* |
| input_text.birthdays_calendar_filter | Birthdays Calendar Filter | — | 100 | text | .* |
| input_text.family_calendar_filter | Family (Google) Calendar Filter | — | 100 | text | .* |

## Input Datetime

| Entity ID | Name | Has Date | Has Time | Initial |
|-----------|------|----------|----------|---------|
| input_datetime.last_z2m_restart | Last Zigbee2MQTT Restart | yes | yes | — |
| input_datetime.last_tuya_restart | Last Tuya Restart | yes | yes | — |
| input_datetime.calendar_date_start | Calendar Start Date | yes | no | — |
| input_datetime.calendar_date_end | Calendar End Date | yes | no | — |
| input_datetime.calendar_time_start | Calendar Start Time | no | yes | 08:00:00 |
| input_datetime.calendar_time_end | Calendar End Time | no | yes | 09:00:00 |

## Counter

| Entity ID | Name | Icon | Initial | Step | Min | Max |
|-----------|------|------|---------|------|-----|-----|
| counter.z2m_error_counter | Zigbee2MQTT Error Counter | — | 0 | 1 | — | — |
| counter.zigbee2mqtt_restart_attempts | Zigbee2MQTT Restart Attempts | — | 0 | 1 | 0 | 3 |
| counter.tuya_restart_attempts | Tuya Restart Attempts | — | 0 | 1 | 0 | 3 |
| counter.llm_fallback_count | LLM Fallback Usage Count | mdi:swap-horizontal | 0 | 1 | — | — |
| counter.llm_primary_success | LLM Primary Success Count | mdi:check-circle | 0 | 1 | — | — |

## Group

| Entity ID | Name | Members |
|-----------|------|---------|
| group.all_persons | All persons | person.sharon, person.maayan |
| group.alexa_devices | Alexa Devices | media_player.hallway_echo_dot, media_player.living_room_echo, media_player.sharon_s_echo_show_5_2nd_gen, media_player.ofri_echo_dot, media_player.balcony_echo_dot |
