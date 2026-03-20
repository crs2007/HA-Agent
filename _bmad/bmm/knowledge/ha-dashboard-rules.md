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

## Glassmorphism Standard
The default glass style for Home view cards:
```css
ha-card {
  backdrop-filter: blur(12px) saturate(140%);
  -webkit-backdrop-filter: blur(12px) saturate(140%);
  background: rgba(255, 255, 255, 0.08) !important;
  border: 1px solid rgba(255, 255, 255, 0.15) !important;
  box-shadow: 0 4px 20px rgba(0, 0, 0, 0.25);
}
```
- For `mushroom-template-card` nav buttons: add via `card_mod.style`
- For `button-card` room cards: add via `styles.card` array properties + slightly tinted background gradient (e.g., `rgba(R, G, B, 0.08)` matching the card's theme color)
- Person-tracker-card: uses `layout: "glass"` with `card_background: "rgba(255, 255, 255, 0.08)"` and `card_border_radius: "16px"`
- Front door card: glass backdrop with conditional border color based on lock state

## New Rooms Design Card Pattern
The 4 room cards (Living Room, Kitchen, Office, Entrance) use `custom:button-card` with:
- **Layout:** 3-row grid: `"n btn" / "s btn" / "i btn"` — name+state on left, chips on right
- **Gradient orb:** `img_cell` 160x140px, position absolute bottom-left, `border-radius: 500px`, themed gradient, `opacity: 0.95`
- **Icon:** 60px white, animated when entity is on (rock/bounce/spin/pulse)
- **Chips:** `mushroom-chips-card` in `custom_fields.btn`, 2-column grid layout, each chip has `icon_color` template + glow animation
- **Sizing:** `min-height: 230px` on all cards for consistent height regardless of chip count
- **Glass:** `backdrop-filter`, border, box-shadow, border-radius: 16px in `styles.card`
- **Glow animations:** Each chip color has a matching `@keyframes glow-{color}` in `extra_styles`

### Room Card Color Themes
| Room | Gradient | Name Color | Glow Colors |
|------|----------|------------|-------------|
| Living Room | `#FFC47E → #FFD9A0` (amber) | `#FFC47E` | cyan, orange, green |
| Kitchen | `#FF6F00 → #FF8F00` (deep orange) | `#FF6F00` | yellow-orange, peach, coral, deep-orange |
| Office | `#0764fa → #4A90E2` (blue) | `#0764fa` | cyan, orange |
| Entrance | `#d97cf2 → #E8A0F8` (purple) | `#d97cf2` | purple, green |

## Non-Admin Navigation Pattern
Non-admin users (kiosk mode) have no tab bar. Navigation is via:
1. **English row** (2 horizontal-stacks, 6 buttons): Light, Switch, Camera, Shade, Sensors, Batteries
2. **Hebrew quick-nav** (5 horizontal-stacks, 15 buttons): All family-relevant tabs in Hebrew
   - Skip admin-only tabs: HA Monitor, Helpers, System Monitor
   - Each button: `mushroom-template-card`, `layout: "vertical"`, with glass `card_mod`
   - 3 cards per row via `horizontal-stack`

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
