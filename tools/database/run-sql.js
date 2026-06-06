#!/usr/bin/env node
'use strict';

/**
 * run-sql.js — Execute SQL files against TaskManager DB
 * Splits scripts on GO batch separators (as SSMS/sqlcmd would).
 *
 * Usage:
 *   node tools/database/run-sql.js 01_tables.sql
 *   node tools/database/run-sql.js 01_tables.sql 02_stored_procs.sql 03_trigger.sql 04_permissions.sql
 */

const sql  = require('mssql');
const fs   = require('fs');
const path = require('path');

const DB_CONFIG = {
  server:   process.env.MSSQL_SERVER   || 'localhost\\SQLSERVER2022',
  database: process.env.MSSQL_DATABASE || 'master',  // use master; scripts USE TaskManager internally
  options: {
    trustedConnection:      !process.env.MSSQL_USER,
    encrypt:                false,
    trustServerCertificate: true,
    enableArithAbort:       true,
    multipleStatements:     true,
  },
  ...(process.env.MSSQL_USER && {
    user:     process.env.MSSQL_USER,
    password: process.env.MSSQL_PASSWORD || '',
  }),
};

const SCRIPT_DIR = __dirname;

function splitOnGo(sql) {
  // Split on lines that are exactly 'GO' (case-insensitive, optional trailing whitespace)
  return sql
    .split(/\r?\n/)
    .reduce((batches, line) => {
      if (/^\s*GO\s*$/i.test(line)) {
        batches.push('');
      } else {
        batches[batches.length - 1] += line + '\n';
      }
      return batches;
    }, [''])
    .map(b => b.trim())
    .filter(b => b.length > 0);
}

async function runFile(pool, file) {
  const filePath = path.isAbsolute(file) ? file : path.join(SCRIPT_DIR, file);
  console.log(`\n${'='.repeat(60)}`);
  console.log(`Running: ${path.basename(filePath)}`);
  console.log('='.repeat(60));

  const content = fs.readFileSync(filePath, 'utf8');
  const batches = splitOnGo(content);
  console.log(`  ${batches.length} batch(es) found`);

  for (let i = 0; i < batches.length; i++) {
    const batch = batches[i];
    const preview = batch.replace(/\s+/g, ' ').substring(0, 80);
    try {
      await pool.request().query(batch);
      console.log(`  [OK] batch ${i + 1}: ${preview}...`);
    } catch (err) {
      // Ignore "already exists" errors so the script is idempotent
      if (err.message.includes('already exists') || err.message.includes('There is already an object')) {
        console.log(`  [SKIP - already exists] batch ${i + 1}: ${preview}...`);
      } else {
        console.error(`  [FAIL] batch ${i + 1}: ${preview}...`);
        console.error(`         Error: ${err.message}`);
        throw err;
      }
    }
  }
}

async function main() {
  const files = process.argv.slice(2);
  if (files.length === 0) {
    console.error('Usage: node run-sql.js <file1.sql> [file2.sql ...]');
    process.exit(1);
  }

  console.log(`Connecting to ${DB_CONFIG.server}...`);
  const pool = await sql.connect(DB_CONFIG);
  console.log('Connected.\n');

  for (const file of files) {
    await runFile(pool, file);
  }

  await pool.close();
  console.log('\nAll scripts completed successfully.');
}

main().catch(err => {
  console.error('\nFatal:', err.message);
  process.exit(1);
});
