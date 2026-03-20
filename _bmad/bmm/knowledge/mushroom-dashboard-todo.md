# Mushroom Dashboard TODO

Last updated: 2026-03-20

## Active Tasks

_(none — all current tasks completed)_

---

## Completed (2026-03-20 — current session)
- [x] Audit all entity references against live HA — found 3 broken
- [x] Fix `switch.aroma_diffuser` → `switch.aroma_diffuser_socket_socket_1`
- [x] Fix `light.smart_office_led_strip` → `light.shellyofficesmartled`
- [x] Fix `binary_sensor.front_door_contact` — removed (no replacement sensor), simplified front door card to lock-only state
- [x] Fix Entrance card chip styling to match other 3 room cards (alignment, grid CSS, icon_color, glow animations)
- [x] Add 9 Hebrew quick-nav tabs (Office, Balcony, Parents, Switches, Sensors, Batteries, Ofri, Red Alert, Water Insights)
- [x] Apply min-height (230px) to all 4 New Rooms Design cards
- [x] Apply glassmorphism to all Home view cards (21 nav buttons + 4 room cards + front door)
- [x] Fix push_dashboard.js path mapping (hyphen vs underscore)

## Completed (2026-03-20 — prior session)
- [x] Fix CSS typo: `min-hight` → `min-height` (Living Room, Office, Entrance)
- [x] Remove duplicate `light.smart_office_led_strip` chip from Office
- [x] Fix Office fan chip calling wrong service (was `script.office_tv_on`)
- [x] Add missing `tap_action navigate` to Entrance card
- [x] Add missing `extra_styles` (pulse + glow-purple) to Entrance card
- [x] Fix Kitchen roller chip entity (was `cover.living_room_roller_cover_0`)
- [x] Fix Entrance main entity (was `light.local_tuya_kitchen_light`)
- [x] Fix Entrance ceiling light chip entity + icon_color template
- [x] Fix Lenny person card missing `entity_picture`
- [x] Align all 4 room cards to consistent gradient/opacity/white-icon standard
- [x] Add Hebrew quick-nav panel for non-admin users (6 tabs)

---

## Notes
- Dashboard file: `_bmad/bmm/knowledge/inventory/raw/lovelace.dashboard_mushroom`
- Push tool: `tools/push_dashboard.js`
- Admin-only tabs (excluded from nav): HA Monitor, Helpers, System Monitor
