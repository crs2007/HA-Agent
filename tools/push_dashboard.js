/**
 * push_dashboard.js — Push a modified Lovelace dashboard config to Home Assistant via WebSocket.
 *
 * Usage:
 *   HASS_TOKEN="<token>" node tools/push_dashboard.js [dashboard_path]
 *
 * Args:
 *   dashboard_path: URL path of the dashboard (default: dashboard-mushroom)
 *
 * Reads config from: _bmad/bmm/knowledge/inventory/raw/lovelace.<dashboard_path>
 * Requires: HASS_TOKEN env var, ws npm package (npm install)
 */

const WebSocket = require('ws');
const fs = require('fs');
const path = require('path');

const HA_URL = 'ws://homeassistant.local:8123/api/websocket';
const TOKEN = process.env.HASS_TOKEN;
const DASHBOARD = process.argv[2] || 'dashboard-mushroom';
// File uses underscore (lovelace.dashboard_mushroom), HA URL uses hyphen (dashboard-mushroom)
const FILE_KEY = DASHBOARD.replace(/-/g, '_');
const CONFIG_FILE = path.join(__dirname, `../_bmad/bmm/knowledge/inventory/raw/lovelace.${FILE_KEY}`);

if (!TOKEN) { console.error('ERROR: HASS_TOKEN environment variable not set.'); process.exit(1); }
if (!fs.existsSync(CONFIG_FILE)) { console.error(`ERROR: Config file not found: ${CONFIG_FILE}`); process.exit(1); }

const raw = fs.readFileSync(CONFIG_FILE, 'utf8');
const parsed = JSON.parse(raw);
const config = parsed.data.config;

console.log(`Dashboard: ${DASHBOARD}`);
console.log(`Views: ${config.views?.length ?? 'N/A'}`);
console.log('Connecting to HA...');

const ws = new WebSocket(HA_URL);

ws.on('message', (data) => {
  const msg = JSON.parse(data);
  if (msg.type === 'auth_required') {
    ws.send(JSON.stringify({ type: 'auth', access_token: TOKEN }));
    return;
  }
  if (msg.type === 'auth_ok') {
    console.log(`Authenticated (HA ${msg.ha_version}). Pushing config...`);
    ws.send(JSON.stringify({
      id: 1,
      type: 'lovelace/config/save',
      url_path: DASHBOARD,
      config: config
    }));
    return;
  }
  if (msg.type === 'result') {
    if (msg.success) {
      console.log('✓ Dashboard pushed successfully. Refresh HA browser to see changes.');
    } else {
      console.error('✗ Push failed:', JSON.stringify(msg.error));
    }
    ws.close();
    process.exit(msg.success ? 0 : 1);
  }
});

ws.on('error', (err) => { console.error('WS error:', err.message); process.exit(1); });
