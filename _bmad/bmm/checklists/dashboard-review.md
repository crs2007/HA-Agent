# Dashboard Review Checklist

Run through this checklist before finalizing any dashboard change.

## Layout
- [ ] 3-per-row layout via `horizontal-stack`
- [ ] Fixed card footprint — no unbounded growth, resize internal elements only
- [ ] Consistent spacing between cards
- [ ] Responsive: cards don't break on tablet/mobile views

## Hebrew & RTL
- [ ] Hebrew labels with `direction: rtl` via card-mod where needed
- [ ] Text alignment correct in RTL context
- [ ] Icon placement works with RTL direction

## Card Conventions
- [ ] Color conventions followed (amber=both, yellow=light, blue=fan, grey=off)
- [ ] Office room colors correct (teal/amber/coral)
- [ ] `mushroom-template-card` used for custom secondary info (NOT `secondary_info` with Jinja)
- [ ] `mushroom-entity-card` with `tap_action: toggle` used for scripts (no `mushroom-script-card`)

## Known Quirks Avoided
- [ ] No `advanced-camera-card` nested in `stack-in-card` (use `card_wide: true` or `picture-entity`)
- [ ] kiosk-mode version matches HA version
- [ ] No colorloop with rgb_color in card actions

## Person Tracker Cards
- [ ] person-tracker-card layout chosen appropriate for context (compact for overview, glass/neon for featured)
- [ ] Auto-detection sensors verified or manually configured
- [ ] Theme consistent with overall dashboard style

## Accessibility
- [ ] Cards have meaningful labels (not just icons)
- [ ] State changes are visually clear (color, icon, or text change)
- [ ] Important information is not hidden behind tap actions

## MCP Verification
- [ ] Current dashboard state read via MCP before changes
- [ ] YAML diff shown and approved by Sharon before applying
