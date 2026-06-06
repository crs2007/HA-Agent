'use strict';
const sql  = require('mssql');
const fs   = require('fs');
const path = require('path');

const cfg = {
  server:   'localhost\\SQLSERVER2022',
  database: 'TaskManager',
  options: { trustedConnection: true, encrypt: false, trustServerCertificate: true },
};

const planText = fs.readFileSync(
  'C:\\Users\\Sharon\\.claude\\plans\\develop-a-comprehensive-technical-mutable-dolphin.md',
  'utf8'
);

(async () => {
  const pool = await sql.connect(cfg);
  const req  = pool.request();

  req.input('title',       sql.NVarChar(500), 'Deploy SMTP server VM for 23011983.xyz');
  req.input('description', sql.NVarChar(sql.MAX),
    'Provision Proxmox VM 104 (2 vCPU / 2 GB / 20 GB, Debian 12) with Postfix MTA, ' +
    'TLS (Let\'s Encrypt), OpenDKIM, Fail2Ban, UFW. ' +
    'Configure SPF, DKIM, DMARC DNS records for full email deliverability on domain 23011983.xyz.');
  req.input('severity_id', sql.SmallInt,      3);    // 3 = high
  req.input('category',    sql.NVarChar(50),  'feature');
  req.input('status_id',   sql.SmallInt,      3);    // 3 = planned
  req.input('agent',       sql.NVarChar(60),  'unassigned');
  req.input('model',       sql.NVarChar(20),  'unassigned');
  req.input('source',      sql.NVarChar(500), 'claude-plan');
  req.input('plan',        sql.NVarChar(sql.MAX), planText);
  req.input('notes',       sql.NVarChar(sql.MAX),
    'Port 25 must be confirmed open at ISP/router. PTR record requires ISP or VPS action. ' +
    'Upgrade DMARC from quarantine to reject after 2 weeks of clean aggregate reports.');

  const result = await req.execute('dbo.usp_Task_Insert');
  const row    = result.recordset[0];
  console.log(`✓ Task created: ${row.id} — ${row.title}`);
  console.log(`  severity=${row.severity}  category=${row.category}  status=${row.status}`);
  await pool.close();
})().catch(err => { console.error('ERROR:', err.message); process.exit(1); });
