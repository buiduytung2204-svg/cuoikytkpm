require('dotenv').config();
const http = require('node:http');
const fs = require('node:fs');
const path = require('node:path');
const crypto = require('node:crypto');
const { promisify } = require('node:util');
const { Pool } = require('pg');

const ROOT = __dirname;
const PORT = Number(process.env.PORT || 8000);
const HOST = process.env.HOST || '127.0.0.1';
const DATABASE_URL = process.env.DATABASE_URL;
const scrypt = promisify(crypto.scrypt);
if (!DATABASE_URL) {
  console.error('Thiếu DATABASE_URL. Hãy tạo file .env theo .env.example và cài PostgreSQL trước.');
  process.exit(1);
}

const pool = new Pool({
  connectionString: DATABASE_URL,
  max: Number(process.env.DB_POOL_SIZE || 20),
  idleTimeoutMillis: 30_000,
  connectionTimeoutMillis: 5_000,
  ssl: process.env.PGSSL === 'true' ? { rejectUnauthorized: true } : undefined,
});
const sessions = new Map();
const loginAttempts = new Map();
const collections = ['tournaments', 'teams', 'athletes', 'matches', 'events', 'venues', 'refs', 'users'];
const roles = { admin: 't team ath draw res user score', btc: 't team ath draw res score', ref: 'score', ath: '', view: '' };

async function passwordHash(password) {
  const salt = crypto.randomBytes(16);
  const key = await scrypt(String(password), salt, 64);
  return `scrypt$${salt.toString('hex')}$${key.toString('hex')}`;
}
async function passwordMatches(password, stored) {
  try {
    const [kind, saltHex, hashHex] = String(stored).split('$');
    if (kind !== 'scrypt' || !saltHex || !hashHex) return false;
    const expected = Buffer.from(hashHex, 'hex');
    const actual = await scrypt(String(password), Buffer.from(saltHex, 'hex'), expected.length);
    return expected.length === actual.length && crypto.timingSafeEqual(expected, actual);
  } catch { return false; }
}
const publicUser = ({ id, username, name, role, athlete, team }) => ({ id, username: String(username || '').trim().toLowerCase(), name, role, athlete, team });
function publicState(input) {
  const state = structuredClone(input || {});
  for (const key of collections) if (!Array.isArray(state[key])) state[key] = [];
  state.users = state.users.map(publicUser);
  delete state.userId;
  return state;
}
function initialState() {
  return { tournaments: [], teams: [], athletes: [], matches: [], events: [], venues: [], refs: [], users: [] };
}

async function saveEntities(client, state) {
  for (const key of collections) for (const item of state[key] || []) {
    const payload = key === 'users' ? publicUser(item) : item;
    await client.query('INSERT INTO app_entities(collection,item_id,payload) VALUES($1,$2,$3::jsonb) ON CONFLICT(collection,item_id) DO UPDATE SET payload=EXCLUDED.payload', [key, String(item.id), JSON.stringify(payload)]);
  }
}
async function readState(client = pool) {
  const [data, rev] = await Promise.all([
    client.query('SELECT collection,payload FROM app_entities ORDER BY collection,item_id'),
    client.query('SELECT revision FROM app_meta WHERE id=1'),
  ]);
  const state = initialState();
  for (const row of data.rows) if (collections.includes(row.collection)) state[row.collection].push(row.payload);
  return { state: publicState(state), revision: Number(rev.rows[0]?.revision || 1), updatedAt: new Date().toISOString() };
}

async function initDatabase() {
  await pool.query(`
    CREATE TABLE IF NOT EXISTS app_entities (
      collection text NOT NULL CHECK (collection IN ('tournaments','teams','athletes','matches','events','venues','refs','users')),
      item_id text NOT NULL, payload jsonb NOT NULL, PRIMARY KEY(collection,item_id)
    );
    CREATE TABLE IF NOT EXISTS app_meta (id integer PRIMARY KEY CHECK (id=1), revision bigint NOT NULL DEFAULT 1);
    CREATE TABLE IF NOT EXISTS accounts (
      id text PRIMARY KEY, username text NOT NULL UNIQUE, password_hash text NOT NULL,
      display_name text NOT NULL, role text NOT NULL, athlete_id text, team_id text,
      must_change boolean NOT NULL DEFAULT false, updated_at timestamptz NOT NULL DEFAULT now()
    );
  `);
  await pool.query('ALTER TABLE accounts ADD COLUMN IF NOT EXISTS must_change boolean NOT NULL DEFAULT false');
  await pool.query('INSERT INTO app_meta(id,revision) VALUES(1,1) ON CONFLICT(id) DO NOTHING');
  const populated = await pool.query('SELECT 1 FROM app_entities LIMIT 1');
  if (populated.rowCount) return;

  // One-time import of the existing SQLite file. Passwords are immediately converted to scrypt hashes.
  const oldDb = path.join(ROOT, 'giai-dau.sqlite3');
  if (!fs.existsSync(oldDb)) return;
  let legacy, usersWithPasswords;
  try {
    const { DatabaseSync } = require('node:sqlite');
    const sqlite = new DatabaseSync(oldDb, { readOnly: true });
    const row = sqlite.prepare('SELECT payload FROM app_state WHERE id=1').get();
    if (row) { usersWithPasswords = JSON.parse(row.payload); legacy = publicState(usersWithPasswords); }
    sqlite.close();
  } catch (error) {
    console.warn('Không nhập được dữ liệu SQLite cũ:', error.message);
  }
  if (!legacy) return;
  const client = await pool.connect();
  try {
    await client.query('BEGIN');
    await saveEntities(client, legacy);
    for (const user of usersWithPasswords.users || []) {
      if (!user?.id || !user?.username || !user?.password) continue;
      const mustChange = String(user.password).length < 12 || ['admin123', 'btc123', 'athlete123', 'ref123', 'view123'].includes(String(user.password));
      await client.query(`INSERT INTO accounts(id,username,password_hash,display_name,role,athlete_id,team_id,must_change)
        VALUES($1,$2,$3,$4,$5,$6,$7,$8) ON CONFLICT(id) DO NOTHING`,
      [String(user.id), String(user.username).trim().toLowerCase(), await passwordHash(user.password), String(user.name || ''), String(user.role || 'view'), user.athlete || null, user.team || null, mustChange]);
    }
    await client.query('UPDATE app_meta SET revision=1 WHERE id=1');
    await client.query('COMMIT');
    console.log('Đã nhập dữ liệu từ giai-dau.sqlite3 sang PostgreSQL. Các mật khẩu cũ đã được băm.');
  } catch (error) {
    await client.query('ROLLBACK');
    throw error;
  } finally { client.release(); }
}

function json(res, status, value, extraHeaders = {}) {
  const body = Buffer.from(JSON.stringify(value));
  res.writeHead(status, {
    'Content-Type': 'application/json; charset=utf-8', 'Content-Length': body.length,
    'Cache-Control': 'no-store', 'X-Content-Type-Options': 'nosniff', ...extraHeaders,
  });
  res.end(body);
}
function readBody(req) {
  return new Promise((resolve, reject) => {
    let size = 0;
    const chunks = [];
    req.on('data', chunk => {
      size += chunk.length;
      if (size > 30_000_000) { reject(Object.assign(new Error('Payload vượt quá 30 MB'), { status: 413 })); req.destroy(); }
      else chunks.push(chunk);
    });
    req.on('end', () => {
      if (!size) return reject(Object.assign(new Error('Payload rỗng'), { status: 400 }));
      try { resolve(JSON.parse(Buffer.concat(chunks).toString('utf8'))); }
      catch { reject(Object.assign(new Error('JSON không hợp lệ'), { status: 400 })); }
    });
    req.on('error', reject);
  });
}
function cookies(req) {
  return Object.fromEntries(String(req.headers.cookie || '').split(';').map(x => x.trim().split('=')).filter(x => x.length >= 2));
}
function sessionFor(req) {
  const token = cookies(req).sid;
  const session = token && sessions.get(token);
  if (!session || session.expires < Date.now()) { if (token) sessions.delete(token); return null; }
  session.expires = Date.now() + 7 * 24 * 60 * 60 * 1000;
  return session;
}
async function refreshSession(session) {
  if (!session) return false;
  const result = await pool.query('SELECT username,role,must_change FROM accounts WHERE id=$1', [session.userId]);
  if (!result.rowCount) return false;
  Object.assign(session, { username: result.rows[0].username, role: result.rows[0].role, mustChange: result.rows[0].must_change });
  return true;
}
function safeCookie(req, token, maxAge) {
  const secure = req.headers['x-forwarded-proto'] === 'https';
  return `sid=${token}; HttpOnly; SameSite=Strict; Path=/; Max-Age=${maxAge}${secure ? '; Secure' : ''}`;
}
function stable(value) {
  if (Array.isArray(value)) return `[${value.map(stable).join(',')}]`;
  if (value && typeof value === 'object') return `{${Object.keys(value).sort().map(key => `${JSON.stringify(key)}:${stable(value[key])}`).join(',')}}`;
  return JSON.stringify(value);
}
const same = (a, b) => stable(a ?? null) === stable(b ?? null);
function validOrigin(req) {
  const origin = req.headers.origin;
  if (!origin) return true;
  try { return new URL(origin).host === req.headers.host; } catch { return false; }
}
function changedRows(baseRows, nextRows) {
  const base = new Map((baseRows || []).map(item => [String(item.id), item]));
  const next = new Map((nextRows || []).map(item => [String(item.id), item]));
  const ids = new Set([...base.keys(), ...next.keys()]);
  return [...ids].filter(id => !same(base.get(id), next.get(id)))
    .map(id => ({ id, before: base.get(id), after: next.get(id) })).sort((a, b) => a.id.localeCompare(b.id));
}
function validateState(state) {
  if (!state || typeof state !== 'object' || Array.isArray(state)) throw Object.assign(new Error('Dữ liệu giải đấu không hợp lệ.'), { status: 400 });
  for (const key of collections) {
    if (!Array.isArray(state[key])) throw Object.assign(new Error(`Thiếu danh sách ${key}.`), { status: 400 });
    const seen = new Set();
    for (const item of state[key]) {
      if (!item || typeof item !== 'object' || !item.id || seen.has(String(item.id))) throw Object.assign(new Error(`Danh sách ${key} có ID không hợp lệ hoặc trùng.`), { status: 400 });
      seen.add(String(item.id));
    }
  }
}
function mergeState(base, incoming, latest) {
  const merged = structuredClone(latest);
  const edits = {};
  for (const key of collections) {
    if (!Array.isArray(incoming[key])) throw Object.assign(new Error(`Thiếu danh sách ${key}`), { status: 400 });
    const changes = changedRows(base[key], incoming[key]);
    const b = new Map((base[key] || []).map(x => [String(x.id), x]));
    const n = new Map(incoming[key].map(x => [String(x.id), x]));
    const l = new Map((latest[key] || []).map(x => [String(x.id), x]));
    for (const change of changes) {
      const serverValue = l.get(change.id);
      const baseValue = b.get(change.id);
      const clientValue = n.get(change.id);
      if (!same(serverValue, baseValue) && !same(serverValue, clientValue)) {
        throw Object.assign(new Error('Dữ liệu này vừa được người khác sửa. Hãy tải lại trang rồi thử lại.'), { status: 409 });
      }
      if (clientValue === undefined) l.delete(change.id); else l.set(change.id, clientValue);
    }
    merged[key] = [...l.values()];
    edits[key] = changes;
  }
  return { merged: publicState(merged), edits };
}
function assertCanEdit(session, edits, latest, incoming) {
  const role = session.role;
  if (role === 'admin') return;
  if (role === 'btc') {
    if (edits.users.length) throw Object.assign(new Error('Ban tổ chức không được sửa tài khoản.'), { status: 403 });
    const owned = new Set(latest.tournaments.filter(t => t.owner === session.userId).map(t => t.id));
    for (const row of edits.tournaments) if ((row.before && !owned.has(row.before.id)) || (row.after && row.after.owner !== session.userId)) throw Object.assign(new Error('Bạn chỉ được sửa giải do mình phụ trách.'), { status: 403 });
    const tournamentId = item => item?.tid || (item && latest.teams.find(t => t.id === item.team)?.tid) || (item && latest.matches.find(m => m.id === item.m)?.tid);
    for (const key of ['teams', 'athletes', 'matches', 'events']) for (const row of edits[key]) {
      if (!owned.has(tournamentId(row.before || row.after))) throw Object.assign(new Error('Bạn chỉ được sửa dữ liệu giải do mình phụ trách.'), { status: 403 });
    }
    return;
  }
  if (role === 'ref') {
    if (edits.users.length || edits.tournaments.length || edits.teams.length || edits.athletes.length || edits.venues.length || edits.refs.length) throw Object.assign(new Error('Trọng tài chỉ được cập nhật kết quả trận.'), { status: 403 });
    const assigned = new Set(latest.matches.filter(m => m.refUser === session.userId).map(m => m.id));
    for (const row of edits.matches) {
      if (!assigned.has(row.id) || !row.before || !row.after) throw Object.assign(new Error('Bạn chỉ được cập nhật trận được phân công.'), { status: 403 });
      const allowed = new Set(['sh', 'sa']);
      if (Object.keys(row.after).some(k => !allowed.has(k) && JSON.stringify(row.before[k]) !== JSON.stringify(row.after[k]))) throw Object.assign(new Error('Trọng tài chỉ được cập nhật tỷ số.'), { status: 403 });
    }
    for (const row of edits.events) if (!assigned.has((row.after || row.before || {}).m)) throw Object.assign(new Error('Bạn chỉ được sửa sự kiện trong trận được phân công.'), { status: 403 });
    return;
  }
  if (Object.values(edits).some(rows => rows.length)) throw Object.assign(new Error('Tài khoản này chỉ có quyền xem.'), { status: 403 });
}
async function persistAccounts(client, state, incomingUsers) {
  if (!state.users.some(user => user.role === 'admin')) throw Object.assign(new Error('Phải luôn có ít nhất một quản trị viên.'), { status: 400 });
  const active = new Set();
  const passwords = new Map((incomingUsers || []).map(u => [String(u.id), u.password]));
  for (const user of state.users) {
    active.add(user.id);
    const previous = await client.query('SELECT password_hash FROM accounts WHERE id=$1', [user.id]);
    let hash = previous.rows[0]?.password_hash;
    if (passwords.get(user.id)) {
      if (String(passwords.get(user.id)).length < 12) throw Object.assign(new Error('Mật khẩu phải có ít nhất 12 ký tự.'), { status: 400 });
      hash = await passwordHash(passwords.get(user.id));
    }
    if (!hash) throw Object.assign(new Error(`Tài khoản ${user.username} cần mật khẩu.`), { status: 400 });
    await client.query(`INSERT INTO accounts(id,username,password_hash,display_name,role,athlete_id,team_id,must_change,updated_at)
      VALUES($1,$2,$3,$4,$5,$6,$7,false,now()) ON CONFLICT(id) DO UPDATE SET username=EXCLUDED.username,
      password_hash=EXCLUDED.password_hash,display_name=EXCLUDED.display_name,role=EXCLUDED.role,
      athlete_id=EXCLUDED.athlete_id,team_id=EXCLUDED.team_id,
      must_change=CASE WHEN $8::boolean THEN false ELSE accounts.must_change END,updated_at=now()`,
    [user.id, String(user.username).trim().toLowerCase(), hash, user.name || '', user.role || 'view', user.athlete || null, user.team || null, Boolean(passwords.get(user.id))]);
  }
  if (active.size) await client.query('DELETE FROM accounts WHERE NOT (id = ANY($1::text[]))', [[...active]]);
  else await client.query('DELETE FROM accounts');
}
const mime = { '.html': 'text/html; charset=utf-8', '.css': 'text/css; charset=utf-8', '.js': 'text/javascript; charset=utf-8', '.json': 'application/json; charset=utf-8', '.png': 'image/png', '.jpg': 'image/jpeg', '.svg': 'image/svg+xml' };
const server = http.createServer(async (req, res) => {
  res.setHeader('X-Content-Type-Options', 'nosniff');
  res.setHeader('Referrer-Policy', 'same-origin');
  const url = new URL(req.url, `http://${req.headers.host || 'localhost'}`);
  const session = sessionFor(req);
  try {
    if (url.pathname.startsWith('/api/') && !validOrigin(req)) return json(res, 403, { error: 'Origin không hợp lệ' });
    if (url.pathname === '/api/bootstrap-status' && req.method === 'GET') {
      const result = await pool.query('SELECT EXISTS(SELECT 1 FROM accounts) AS has_accounts');
      return json(res, 200, { setupRequired: !result.rows[0].has_accounts });
    }
    if (url.pathname === '/api/setup' && req.method === 'POST') {
      const input = await readBody(req);
      const username = String(input.username || '').trim().toLowerCase();
      const password = String(input.password || '');
      if (!/^[a-z0-9_.-]{3,40}$/.test(username) || password.length < 12) return json(res, 400, { error: 'Tên đăng nhập không hợp lệ hoặc mật khẩu dưới 12 ký tự.' });
      const client = await pool.connect();
      try {
        await client.query('BEGIN');
        await client.query('SELECT pg_advisory_xact_lock(850021)');
        const has = await client.query('SELECT 1 FROM accounts LIMIT 1');
        if (has.rowCount) { await client.query('ROLLBACK'); return json(res, 409, { error: 'Thiết lập ban đầu đã hoàn thành.' }); }
        const user = { id: crypto.randomUUID(), username, name: String(input.name || 'Quản trị viên').slice(0, 100), role: 'admin' };
        const existing = await readState(client);
        const state = existing?.state || initialState();
        state.users = [user];
        state.tournaments.forEach(tournament => { tournament.owner = user.id; });
        await client.query('INSERT INTO accounts(id,username,password_hash,display_name,role,must_change) VALUES($1,$2,$3,$4,$5,false)', [user.id, username, await passwordHash(password), user.name, 'admin']);
        await client.query("DELETE FROM app_entities WHERE collection='users'");
        await saveEntities(client, state);
        const revisionResult = await client.query('UPDATE app_meta SET revision=revision+1 WHERE id=1 RETURNING revision');
        const saved = await readState(client);
        await client.query('COMMIT');
        const token = crypto.randomBytes(32).toString('hex');
        sessions.set(token, { userId: user.id, username, role: 'admin', mustChange: false, expires: Date.now() + 7 * 86400_000 });
        return json(res, 201, { user, state: saved.state, revision: Number(revisionResult.rows[0].revision) }, { 'Set-Cookie': safeCookie(req, token, 7 * 86400) });
      } catch (error) { await client.query('ROLLBACK'); throw error; }
      finally { client.release(); }
    }
    if (url.pathname === '/api/login' && req.method === 'POST') {
      const input = await readBody(req);
      const username = String(input.username || '').trim().toLowerCase();
      const ip = req.headers['cf-connecting-ip'] || req.socket.remoteAddress || 'unknown';
      const attempts = loginAttempts.get(ip) || { count: 0, until: Date.now() + 60_000 };
      if (attempts.until < Date.now()) { attempts.count = 0; attempts.until = Date.now() + 60_000; }
      if (attempts.count >= 10) return json(res, 429, { error: 'Thử đăng nhập quá nhiều lần. Hãy đợi một phút.' });
      const found = await pool.query('SELECT id,username,password_hash,display_name,role,athlete_id,team_id,must_change FROM accounts WHERE username=$1', [username]);
      const account = found.rows[0];
      if (!account || !(await passwordMatches(input.password || '', account.password_hash))) {
        attempts.count++; loginAttempts.set(ip, attempts);
        return json(res, 401, { error: 'Sai tên đăng nhập hoặc mật khẩu.' });
      }
      loginAttempts.delete(ip);
      const token = crypto.randomBytes(32).toString('hex');
      const user = { id: account.id, username: account.username, role: account.role };
      sessions.set(token, { userId: account.id, username: account.username, role: account.role, mustChange: account.must_change, expires: Date.now() + 7 * 86400_000 });
      if (account.must_change) return json(res, 200, { user, mustChange: true }, { 'Set-Cookie': safeCookie(req, token, 7 * 86400) });
      const saved = await readState();
      return json(res, 200, { user, state: saved?.state, revision: saved?.revision, mustChange: false }, { 'Set-Cookie': safeCookie(req, token, 7 * 86400) });
    }
    if (url.pathname === '/api/change-password' && req.method === 'POST') {
      if (!(await refreshSession(session))) return json(res, 401, { error: 'Vui lòng đăng nhập.' });
      const input = await readBody(req), oldPassword = String(input.oldPassword || ''), newPassword = String(input.newPassword || '');
      if (newPassword.length < 12) return json(res, 400, { error: 'Mật khẩu mới phải có ít nhất 12 ký tự.' });
      const accountResult = await pool.query('SELECT password_hash FROM accounts WHERE id=$1', [session.userId]);
      if (!accountResult.rowCount || !(await passwordMatches(oldPassword, accountResult.rows[0].password_hash))) return json(res, 403, { error: 'Mật khẩu hiện tại không đúng.' });
      await pool.query('UPDATE accounts SET password_hash=$1,must_change=false,updated_at=now() WHERE id=$2', [await passwordHash(newPassword), session.userId]);
      session.mustChange = false;
      return json(res, 200, { ok: true });
    }
    if (url.pathname === '/api/logout' && req.method === 'POST') {
      const token = cookies(req).sid; if (token) sessions.delete(token);
      return json(res, 200, { ok: true }, { 'Set-Cookie': safeCookie(req, '', 0) });
    }
    if (url.pathname === '/api/state' && req.method === 'GET') {
      if (!(await refreshSession(session))) return json(res, 401, { error: 'Vui lòng đăng nhập.' });
      if (session.mustChange) return json(res, 403, { error: 'Đổi mật khẩu trước khi tiếp tục.' });
      const saved = await readState();
      if (!saved) return json(res, 503, { error: 'Database chưa có dữ liệu. Cần hoàn tất thiết lập ban đầu.' });
      const me = await pool.query('SELECT athlete_id,team_id FROM accounts WHERE id=$1', [session.userId]);
      saved.state.userId = session.userId;
      saved.user = { id: session.userId, username: session.username, role: session.role, athlete: me.rows[0]?.athlete_id, team: me.rows[0]?.team_id };
      return json(res, 200, saved);
    }
    if (url.pathname === '/api/state' && req.method === 'PUT') {
      if (!(await refreshSession(session))) return json(res, 401, { error: 'Vui lòng đăng nhập.' });
      if (session.mustChange) return json(res, 403, { error: 'Đổi mật khẩu trước khi tiếp tục.' });
      const input = await readBody(req);
      if (!input.state || !input.baseState) return json(res, 400, { error: 'Thiếu dữ liệu nền để đồng bộ.' });
      validateState(input.state);validateState(input.baseState);
      const client = await pool.connect();
      try {
        await client.query('BEGIN');
        const latestSnapshot = await readState(client);
        const latest = latestSnapshot.state;
        const base = publicState(input.baseState);
        const incoming = structuredClone(input.state);
        // Non-admin clients never submit account changes, even if their browser state was altered.
        if (session.role !== 'admin') incoming.users = base.users;
        const { merged, edits } = mergeState(base, incoming, latest);
        assertCanEdit(session, edits, latest, incoming);
        if (edits.users.length && session.role !== 'admin') throw Object.assign(new Error('Chỉ quản trị viên được quản lý tài khoản.'), { status: 403 });
        for (const key of collections) for (const change of edits[key]) {
          const locked = await client.query('SELECT payload FROM app_entities WHERE collection=$1 AND item_id=$2 FOR UPDATE', [key, change.id]);
          const current = locked.rowCount ? locked.rows[0].payload : undefined;
          const desired = (incoming[key] || []).find(item => String(item.id) === change.id);
          if (!same(current, change.before) && !same(current, desired)) throw Object.assign(new Error('Dữ liệu này vừa được người khác sửa. Hãy tải lại trang rồi thử lại.'), { status: 409 });
          if (desired === undefined) await client.query('DELETE FROM app_entities WHERE collection=$1 AND item_id=$2', [key, change.id]);
          else {
            const payload = key === 'users' ? publicUser(desired) : desired;
            await client.query(`INSERT INTO app_entities(collection,item_id,payload) VALUES($1,$2,$3::jsonb)
              ON CONFLICT(collection,item_id) DO UPDATE SET payload=EXCLUDED.payload`, [key, change.id, JSON.stringify(payload)]);
          }
        }
        if (edits.users.length) await persistAccounts(client, merged, incoming.users);
        await client.query('UPDATE app_meta SET revision=revision+1 WHERE id=1');
        const saved = await readState(client);
        await client.query('COMMIT');
        saved.state.userId = session.userId;
        return json(res, 200, { ok: true, state: saved.state, revision: saved.revision, updatedAt: saved.updatedAt });
      } catch (error) { await client.query('ROLLBACK'); throw error; }
      finally { client.release(); }
    }
    if (url.pathname.startsWith('/api/')) return json(res, 404, { error: 'Không tìm thấy API.' });
    if (req.method !== 'GET' && req.method !== 'HEAD') return json(res, 405, { error: 'Phương thức không được hỗ trợ.' });
    let pathname;
    try { pathname = decodeURIComponent(url.pathname); } catch { return json(res, 400, { error: 'Đường dẫn không hợp lệ.' }); }
    // Only the public page is served. Never expose .env, source files, backups, or SQLite.
    if (pathname !== '/' && pathname !== '/giai-dau.html') return json(res, 404, { error: 'Không tìm thấy tệp.' });
    const target = path.join(ROOT, 'giai-dau.html');
    fs.stat(target, (err, stat) => {
      if (err || !stat.isFile()) { res.writeHead(404); return res.end('Not found'); }
      res.writeHead(200, { 'Content-Type': mime[path.extname(target).toLowerCase()] || 'application/octet-stream', 'Cache-Control': 'no-store' });
      if (req.method === 'HEAD') return res.end();
      fs.createReadStream(target).pipe(res);
    });
  } catch (error) {
    if (res.headersSent || res.destroyed) return;
    console.error('API error:', error);
    json(res, error.status || (error.code === '23505' ? 409 : 500), { error: error.status ? error.message : error.code === '23505' ? 'Tên đăng nhập đã được dùng.' : 'Lỗi máy chủ.' });
  }
});

async function start() {
  await initDatabase();
  server.listen(PORT, HOST, () => console.log(`Tournament app: http://${HOST}:${PORT}/giai-dau.html\nPostgreSQL: connected · pool max ${pool.options.max}`));
}
start().catch(error => { console.error('Không khởi động được PostgreSQL:', error.message); process.exit(1); });
for (const signal of ['SIGINT', 'SIGTERM']) process.on(signal, () => server.close(async () => { await pool.end(); process.exit(0); }));
