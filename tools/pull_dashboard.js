/**
 * pull_dashboard.js — Pull the current Lovelace dashboard config from Home Assistant and
 * overwrite the local snapshot file. Run this BEFORE making any dashboard edits.
 *
 * Usage:
 *   HASS_TOKEN="<token>" node tools/pull_dashboard.js [dashboard_path]
 *
 * Args:
 *   dashboard_path: URL path of the dashboard (default: dashboard-mushroom)
 *
 * Writes config to: _bmad/bmm/knowledge/inventory/raw/lovelace.<dashboard_path>
 * Requires: HASS_TOKEN env var, ws npm package (npm install)
 */

const WebSocket = require('ws');
const fs = require('fs');
const path = require('path');

const HA_URL = 'ws://homeassistant.local:8123/api/websocket';
const TOKEN = process.env.HASS_TOKEN;
const DASHBOARD = process.argv[2] || 'dashboard-mushroom';
const FILE_KEY = DASHBOARD.replace(/-/g, '_');
const CONFIG_FILE = path.join(__dirname, `../_bmad/bmm/knowledge/inventory/raw/lovelace.${FILE_KEY}`);

if (!TOKEN) { console.error('ERROR: HASS_TOKEN environment variable not set.'); process.exit(1); }

console.log(`Dashboard: ${DASHBOARD}`);
console.log(`Target file: ${CONFIG_FILE}`);
console.log('Connecting to HA...');

const ws = new WebSocket(HA_URL);

ws.on('message', (data) => {
  const msg = JSON.parse(data);
  if (msg.type === 'auth_required') {
    ws.send(JSON.stringify({ type: 'auth', access_token: TOKEN }));
    return;
  }
  if (msg.type === 'auth_ok') {
    console.log(`Authenticated (HA ${msg.ha_version}). Pulling config...`);
    ws.send(JSON.stringify({
      id: 1,
      type: 'lovelace/config',
      url_path: DASHBOARD
    }));
    return;
  }
  if (msg.type === 'result') {
    if (msg.success) {
      // Wrap in same structure as the storage file so push_dashboard.js stays compatible
      const payload = { data: { config: msg.result } };
      fs.writeFileSync(CONFIG_FILE, JSON.stringify(payload, null, 2), 'utf8');
      const views = msg.result?.views?.length ?? 'N/A';
      console.log(`✓ Pulled ${views} views → ${CONFIG_FILE}`);
      console.log('Local snapshot is now up to date with Pi. Safe to edit.');
    } else {
      console.error('✗ Pull failed:', JSON.stringify(msg.error));
    }
    ws.close();
    process.exit(msg.success ? 0 : 1);
  }
});

ws.on('error', (err) => { console.error('WS error:', err.message); process.exit(1); });
