const assert = require('node:assert/strict');
const fs = require('node:fs');
const path = require('node:path');
const vm = require('node:vm');
const { spawnSync } = require('node:child_process');

const root = path.resolve(__dirname, '..');
const serverPath = path.join(root, 'server.js');
const htmlPath = path.join(root, 'giai-dau.html');
const server = fs.readFileSync(serverPath, 'utf8');
const html = fs.readFileSync(htmlPath, 'utf8');

const serverCheck = spawnSync(process.execPath, ['--check', serverPath], { encoding: 'utf8' });
assert.equal(serverCheck.status, 0, serverCheck.stderr || 'server.js syntax check failed');
console.log('PASS server.js syntax');

const inlineScripts = [...html.matchAll(/<script(?:\s[^>]*)?>([\s\S]*?)<\/script>/gi)]
  .map(match => match[1].trim())
  .filter(Boolean);
assert.ok(inlineScripts.length > 0, 'No inline application JavaScript found');
inlineScripts.forEach((source, index) => new vm.Script(source, { filename: `giai-dau.html<script-${index + 1}>` }));
console.log(`PASS ${inlineScripts.length} inline HTML script(s) parse`);

assert.match(html, /@media\s*\(max-width:\s*760px\)/, 'Mobile breakpoint is missing');
assert.match(html, /\.side\s*\{[^}]*position:\s*fixed/s, 'Mobile navigation bar is missing');
assert.match(html, /data-a="moreNav"/, 'Mobile More navigation action is missing');
console.log('PASS mobile navigation and responsive breakpoint');

assert.match(server, /pathname !== '\/' && pathname !== '\/giai-dau\.html'/, 'Static file allow-list is missing');
assert.match(server, /Cache-Control': 'no-store'/, 'Static page no-store header is missing');
console.log('PASS static route allow-list and no-store response');

for (const file of ['package-lock.json', '.env.example', '.gitignore']) {
  assert.ok(fs.existsSync(path.join(root, file)), `${file} is missing`);
}
const ignore = fs.readFileSync(path.join(root, '.gitignore'), 'utf8');
assert.match(ignore, /^\.env\s*$/m, '.env must not be committed');
assert.match(ignore, /^\*\.sqlite3\s*$/m, 'SQLite database files must not be committed');
assert.match(ignore, /^\.postgres-admin-password\.txt\s*$/m, 'Admin password file must not be committed');
console.log('PASS lockfile and secret/database ignore rules');
