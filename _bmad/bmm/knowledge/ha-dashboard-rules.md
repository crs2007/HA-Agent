# Home Assistant Dashboard Design Rules

## Layout Principles
- **3-per-row** using `horizontal-stack` as the default grid
- **Fixed card footprint** — resize internal elements, NEVER expand containers
- **vertical-stack** for column grouping within a row
- **stack-in-card** for combining multiple elements into a single card boundary

## Color Conventions
### Fan/Light Cards
- **Amber** = both fan and light on
- **Yellow** = light only
- **Blue** = fan only
- **Grey** = off

### Office Room Colors
- Teal: `rgba(138, 205, 215)`
- Amber: `rgba(249, 180, 45)`
- Coral: `rgba(223, 130, 108)`

## Hebrew & RTL Support
- Apply `direction: rtl` via card-mod where needed
- Hebrew labels are the primary language
- Ensure text alignment and icon placement work in RTL context

## Card Catalog

### Primary Cards
- **Mushroom Cards**: entity, template, chips, title, light, climate, cover, fan, media-player, alarm, lock, number, select, update
- **button-card**: Custom templates, conditional styling, multi-action
- **bubble-card**: Navigation and quick access

### Layout Cards
- **stack-in-card**: Combine multiple cards into one
- **horizontal-stack / vertical-stack**: Grid layout
- **layout-card**: Advanced grid and masonry layouts
- **grid**: Simple CSS grid

### Data Visualization
- **mini-graph-card**: Inline sparkline graphs
- **apexcharts-card**: Advanced charts and graphs
- **sankey-chart**: Energy flow visualization
- **battery-state-card**: Battery level overview

### Media & Camera
- **advanced-camera-card**: Live camera feeds (quirk: init issues in stack-in-card)
- **universal-remote-card**: TV and device remote control
- **mini-media-player**: Compact media controls

### Utility
- **auto-entities**: Dynamic entity lists
- **state-switch**: Conditional card display
- **config-template-card**: Template-based configuration
- **swipe-card**: Swipeable card container

### Specialty
- **week-planner-card**: Calendar week view
- **calendar-card-pro**: Enhanced calendar display
- **kiosk-mode**: Tablet/kiosk display mode
- **person-tracker-card**: Advanced person tracking with 8 layouts (classic, compact, modern, neon, glass, bioluminescence, holographic-3d, weather-station), auto-detection of battery/activity/connection sensors, animated weather backgrounds, glassmorphism, distance/travel tracking

## Person Tracker Card Design Patterns
The person-tracker-card supports multiple visual themes:
- **Glass**: Frosted glassmorphism with translucent chips, gradient orbs, animated status dot
- **Neon**: Dark cyberpunk theme with glowing neon badges, monospace font, scanline overlay
- **Holographic 3D**: Futuristic card with real CSS 3D perspective, floating tilt animation
- **Modern**: Sleek horizontal design with SVG circular progress rings
- **Bioluminescence**: Deep-ocean theme with animated glowing orbs, rising particles

Use person-tracker-card for family member displays. It auto-detects companion app sensors (battery, activity, WiFi/mobile connection, distance). Supports Waze/Google Routes integration for travel time.

## Known Quirks
1. **mushroom `secondary_info`**: Only predefined values, NOT Jinja2 — use `mushroom-template-card` for custom templating
2. **advanced-camera-card**: Initialization issues in `stack-in-card` — use `card_wide: true` or `picture-entity`
3. **kiosk-mode**: Version in `configuration.yaml` must match HA version — update version query string after HACS upgrades
4. **No `mushroom-script-card`**: Use `mushroom-entity-card` with `tap_action: toggle` for scripts
5. **Card-mod**: Use for custom styling, RTL direction, conditional colors

## Dashboards
| Dashboard | URL Path | Mode | Purpose |
|-----------|----------|------|---------|
| Mushroom | `dashboard-mushroom` | Storage | Primary UI (467KB) |
| Kiosk | `dashboard-kiosk` | Storage | Tablet display (25KB) |
| Calendar Planner | `calander-planer` | Storage | Calendar management |
| YAML Kiosk | `kiosk` | YAML | Additional kiosk at `dashboards/kiosk_dashboard.yaml` |

## Design Review Checklist
Before finalizing any dashboard change, run through `_bmad/bmm/checklists/dashboard-review.md`.
