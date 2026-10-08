'use strict';
/*
 * MCP firewall gateway.
 *
 * Sits in front of an MCP server (Streamable HTTP) and enforces a per-client
 * "auth map":
 *   - bearer-token authentication (tokens stored only as SHA-256 hashes)
 *   - tool allow/deny lists (glob patterns), applied to tools/call AND used to
 *     hide tools from tools/list
 *   - URL allowlist for any "url" argument (e.g. browser_navigate)
 *   - session binding: a session can only be used by the client that opened it
 *   - per-client rate limiting, body-size limit, Origin check
 *   - JSON-lines audit log on stdout
 *
 * No dependencies; Node 18+.
 */
const http = require('node:http');
const crypto = require('node:crypto');
const fs = require('node:fs');

const PORT = Number(process.env.PORT || 8080);
const HOST = process.env.HOST || '0.0.0.0';
const UPSTREAM = new URL(process.env.UPSTREAM_URL || 'http://edge-mcp:8931/mcp');
const MAP_PATH = process.env.AUTH_MAP_PATH || '/config/auth-map.json';
const MAX_BODY = Number(process.env.MAX_BODY_BYTES || 1_000_000);
const ALLOWED_ORIGINS = (process.env.ALLOWED_ORIGINS || '')
  .split(',').map((s) => s.trim()).filter(Boolean);

const PASS_REQ_HEADERS = ['accept', 'content-type', 'mcp-session-id', 'mcp-protocol-version',
  'last-event-id', 'mcp-method', 'mcp-name'];
const HOP_BY_HOP = new Set(['connection', 'keep-alive', 'transfer-encoding', 'te', 'trailer',
  'upgrade', 'proxy-authenticate', 'proxy-authorization', 'content-length']);

function log(event, fields = {}) {
  process.stdout.write(JSON.stringify({ ts: new Date().toISOString(), event, ...fields }) + '\n');
}

// ---------------------------------------------------------------- glob match
const globCache = new Map();
function globToRegex(glob) {
  let re = globCache.get(glob);
  if (!re) {
    const src = glob.split('*').map((p) => p.replace(/[.+?^${}()|[\]\\]/g, '\\$&')).join('.*');
    re = new RegExp(`^${src}$`, 'i');
    globCache.set(glob, re);
  }
  return re;
}
const matchAny = (patterns, value) => patterns.some((p) => globToRegex(p).test(value));

// ------------------------------------------------------------------ auth map
let clients = [];

function loadMap() {
  const raw = JSON.parse(fs.readFileSync(MAP_PATH, 'utf8'));
  const list = [];
  for (const [name, c] of Object.entries(raw.clients || {})) {
    if (!/^[0-9a-f]{64}$/i.test(c.tokenSha256 || '')) {
      throw new Error(`client "${name}": tokenSha256 must be 64 hex characters`);
    }
    list.push({
      name,
      hash: Buffer.from(c.tokenSha256, 'hex'),
      toolsAllow: c.tools?.allow ?? [],
      toolsDeny: c.tools?.deny ?? [],
      urlsAllow: c.urls?.allow ?? [],
      urlsDeny: c.urls?.deny ?? [],
      rate: c.rateLimitPerMinute ?? 120,
    });
  }
  clients = list;
  log('auth_map_loaded', { path: MAP_PATH, clients: list.map((c) => c.name) });
}

function authenticate(req) {
  const m = /^Bearer\s+(\S+)$/i.exec(req.headers.authorization || '');
  if (!m) return null;
  const digest = crypto.createHash('sha256').update(m[1]).digest();
  let found = null;
  for (const c of clients) {           // check every entry: no early exit
    if (crypto.timingSafeEqual(digest, c.hash)) found = c;
  }
  return found;
}

// --------------------------------------------------------------- rate limit
const buckets = new Map();
function takeToken(client) {
  const now = Date.now();
  const b = buckets.get(client.name) || { tokens: client.rate, last: now };
  b.tokens = Math.min(client.rate, b.tokens + ((now - b.last) / 60000) * client.rate);
  b.last = now;
  const ok = b.tokens >= 1;
  if (ok) b.tokens -= 1;
  buckets.set(client.name, b);
  return ok;
}

// ------------------------------------------------------------------- policy
function checkTool(client, name) {
  if (typeof name !== 'string' || !name) return 'missing tool name';
  if (matchAny(client.toolsDeny, name)) return `tool "${name}" is denied for this client`;
  if (!matchAny(client.toolsAllow, name)) return `tool "${name}" is not in this client's allow list`;
  return null;
}

function collectUrls(value, out = []) {
  if (Array.isArray(value)) value.forEach((v) => collectUrls(v, out));
  else if (value && typeof value === 'object') {
    for (const [k, v] of Object.entries(value)) {
      if (/^urls?$/i.test(k) && typeof v === 'string') out.push(v);
      else collectUrls(v, out);
    }
  }
  return out;
}

function checkUrl(client, raw) {
  let u;
  try { u = new URL(raw); } catch { return `"${raw}" is not an absolute URL`; }
  if (u.protocol !== 'http:' && u.protocol !== 'https:') return `scheme "${u.protocol}" is not allowed`;
  if (matchAny(client.urlsDeny, u.origin)) return `${u.origin} is denied for this client`;
  if (!matchAny(client.urlsAllow, u.origin)) return `${u.origin} is not in this client's URL allow list`;
  return null;
}

function visibleTools(client, tools) {
  return tools.filter((t) => !checkTool(client, t && t.name));
}

// ----------------------------------------------------------------- sessions
const sessions = new Map();   // mcp-session-id -> client name

// ------------------------------------------------------------------ helpers
function sendJson(res, status, obj, extra = {}) {
  if (res.headersSent) return res.end();
  res.writeHead(status, { 'content-type': 'application/json', ...extra });
  res.end(JSON.stringify(obj));
}
const rpcError = (id, code, message) => ({ jsonrpc: '2.0', id: id ?? null, error: { code, message } });

function readBody(req) {
  return new Promise((resolve, reject) => {
    const chunks = [];
    let size = 0;
    req.on('data', (c) => {
      size += c.length;
      if (size > MAX_BODY) { reject(new Error('too_large')); req.destroy(); return; }
      chunks.push(c);
    });
    req.on('end', () => resolve(Buffer.concat(chunks)));
    req.on('error', reject);
  });
}

function filterMessage(client, text) {
  let msg;
  try { msg = JSON.parse(text); } catch { return text; }
  if (msg && msg.result && Array.isArray(msg.result.tools)) {
    const before = msg.result.tools.length;
    msg.result.tools = visibleTools(client, msg.result.tools);
    log('tools_list_filtered', { client: client.name, shown: msg.result.tools.length, hidden: before - msg.result.tools.length });
    return JSON.stringify(msg);
  }
  return text;
}

// Rewrites an SSE stream event by event, filtering tools/list results.
function sseFilter(client, upstream, res) {
  let buf = '';
  const flushEvent = (evt) => {
    const lines = evt.split(/\r?\n/);
    const data = lines.filter((l) => l.startsWith('data:')).map((l) => l.slice(5).replace(/^ /, ''));
    if (!data.length) { res.write(evt + '\n\n'); return; }
    const other = lines.filter((l) => !l.startsWith('data:'));
    const payload = filterMessage(client, data.join('\n'));
    res.write([...other, ...payload.split('\n').map((l) => `data: ${l}`)].join('\n') + '\n\n');
  };
  upstream.setEncoding('utf8');
  upstream.on('data', (chunk) => {
    buf += chunk;
    let m;
    while ((m = /\r?\n\r?\n/.exec(buf))) {
      flushEvent(buf.slice(0, m.index));
      buf = buf.slice(m.index + m[0].length);
    }
  });
  upstream.on('end', () => { if (buf.trim()) flushEvent(buf); res.end(); });
}

// ------------------------------------------------------------------ forward
function forward(req, res, body, client, msg) {
  const headers = { host: UPSTREAM.host };
  for (const h of PASS_REQ_HEADERS) if (req.headers[h]) headers[h] = req.headers[h];
  if (body) headers['content-length'] = body.length;
  const reqSid = req.headers['mcp-session-id'];

  const up = http.request({
    hostname: UPSTREAM.hostname,
    port: UPSTREAM.port || 80,
    path: UPSTREAM.pathname,
    method: req.method,
    headers,
  }, (ur) => {
    const out = {};
    for (const [k, v] of Object.entries(ur.headers)) if (!HOP_BY_HOP.has(k)) out[k] = v;

    const newSid = ur.headers['mcp-session-id'];
    if (newSid && !sessions.has(newSid)) {
      sessions.set(newSid, client.name);
      log('session_opened', { client: client.name, session: newSid });
    }
    if (req.method === 'DELETE' && reqSid && ur.statusCode < 300) sessions.delete(reqSid);

    const ct = String(ur.headers['content-type'] || '');
    const needsFilter = msg && msg.method === 'tools/list';
    res.writeHead(ur.statusCode, out);
    if (!needsFilter) { ur.pipe(res); return; }
    if (ct.includes('text/event-stream')) { sseFilter(client, ur, res); return; }
    const chunks = [];
    ur.on('data', (c) => chunks.push(c));
    ur.on('end', () => res.end(filterMessage(client, Buffer.concat(chunks).toString('utf8'))));
  });

  up.on('error', (e) => {
    log('upstream_error', { client: client.name, error: e.message });
    if (!res.headersSent) sendJson(res, 502, rpcError(msg?.id, -32603, 'Upstream MCP server unavailable'));
    else res.end();
  });
  res.on('close', () => up.destroy());
  up.end(body || undefined);
}

// ------------------------------------------------------------------- server
const server = http.createServer(async (req, res) => {
  const path = new URL(req.url, 'http://gateway').pathname;
  if (path === '/healthz') { res.writeHead(200, { 'content-type': 'text/plain' }).end('ok'); return; }
  if (path !== UPSTREAM.pathname) { sendJson(res, 404, { error: 'not_found' }); return; }

  const origin = req.headers.origin;
  if (origin && !ALLOWED_ORIGINS.includes(origin)) {
    log('blocked', { reason: 'origin', origin });
    sendJson(res, 403, { error: 'origin_not_allowed' });
    return;
  }

  const client = authenticate(req);
  if (!client) {
    log('auth_failed', { ip: req.socket.remoteAddress });
    sendJson(res, 401, { error: 'unauthorized' }, { 'www-authenticate': 'Bearer realm="mcp-firewall"' });
    return;
  }
  if (!takeToken(client)) {
    log('rate_limited', { client: client.name });
    sendJson(res, 429, { error: 'rate_limited' }, { 'retry-after': '10' });
    return;
  }

  const sid = req.headers['mcp-session-id'];
  if (sid && sessions.get(sid) !== client.name) {
    log('blocked', { client: client.name, reason: 'session_not_owned' });
    sendJson(res, 404, rpcError(null, -32001, 'Session not found'));
    return;
  }

  if (req.method === 'GET' || req.method === 'DELETE') { forward(req, res, null, client, null); return; }
  if (req.method !== 'POST') { sendJson(res, 405, { error: 'method_not_allowed' }, { allow: 'GET, POST, DELETE' }); return; }

  let body;
  try { body = await readBody(req); } catch {
    sendJson(res, 413, rpcError(null, -32600, 'Request body too large'));
    return;
  }
  let msg;
  try { msg = JSON.parse(body.toString('utf8')); } catch {
    sendJson(res, 400, rpcError(null, -32700, 'Parse error'));
    return;
  }
  if (!msg || typeof msg !== 'object' || Array.isArray(msg)) {
    sendJson(res, 400, rpcError(null, -32600, 'Batch and non-object requests are not accepted'));
    return;
  }

  // Routing headers must agree with the body, or a gateway could be fooled.
  const hMethod = req.headers['mcp-method'];
  const hName = req.headers['mcp-name'];
  if ((hMethod && msg.method && hMethod !== msg.method) ||
      (hName && msg.method === 'tools/call' && hName !== msg.params?.name)) {
    log('blocked', { client: client.name, reason: 'header_body_mismatch' });
    sendJson(res, 400, rpcError(msg.id, -32600, 'Mcp-Method/Mcp-Name headers do not match the request body'));
    return;
  }

  if (msg.method === 'tools/call') {
    const name = msg.params?.name;
    const urls = collectUrls(msg.params?.arguments);
    const reason = checkTool(client, name) || urls.map((u) => checkUrl(client, u)).find(Boolean);
    if (reason) {
      log('blocked', { client: client.name, tool: name, urls, reason });
      const result = { content: [{ type: 'text', text: `Blocked by MCP firewall: ${reason}` }], isError: true };
      if (String(req.headers['mcp-protocol-version'] || '') >= '2026-07-28') result.resultType = 'complete';
      sendJson(res, 200, { jsonrpc: '2.0', id: msg.id, result });
      return;
    }
    log('allowed', { client: client.name, tool: name, urls });
  }

  forward(req, res, body, client, msg);
});

try { loadMap(); } catch (e) {
  log('auth_map_invalid', { path: MAP_PATH, error: e.message });
  process.exit(1);
}
fs.watchFile(MAP_PATH, { interval: 2000 }, () => {
  try { loadMap(); } catch (e) { log('auth_map_reload_failed', { error: e.message }); }
});
for (const sig of ['SIGTERM', 'SIGINT']) process.on(sig, () => server.close(() => process.exit(0)));

server.listen(PORT, HOST, () => log('listening', { host: HOST, port: PORT, upstream: UPSTREAM.href }));
