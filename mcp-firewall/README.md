# Edge MCP Server with MCP Firewall (Docker)

Headless **Microsoft Edge**, driven by Microsoft's **Playwright MCP** server, behind an **MCP firewall gateway** that enforces a per-client **auth map**. Claude connects only to the firewall; the browser is never exposed and can only reach the internet through an allowlisted egress proxy.

```
Claude ──► firewall :8080 ──► edge-mcp :8931 ──► egress :3128 ──► internet
          auth map:           Playwright MCP     squid: domain
          tokens, tools,      + headless Edge    allowlist, blocks
          URLs, sessions      (internal only)    private IPs
```

| Layer | What it enforces |
|---|---|
| **Firewall** (`firewall/`) | Bearer-token auth; tool allow/deny lists (also hides denied tools from `tools/list`); URL allowlist on every `url` argument; only `http(s)` schemes; sessions bound to the client that opened them; rate limits; Origin check; `Mcp-Method`/`Mcp-Name` header must match the body; JSON audit log |
| **Network** (`docker-compose.yml`) | Edge sits on an `internal` Docker network: no published port, no direct internet |
| **Egress proxy** (`egress/`) | Hard domain allowlist for every client; blocks private, loopback and link-local addresses (your LAN, cloud metadata) |

Why both URL layers? The firewall only sees what Claude *asks* for. Once a page loads, links, redirects and scripts can go anywhere, and only the egress proxy catches those.

## Files

| Path | Purpose |
|---|---|
| `Dockerfile` | Node 22 + Edge stable + `@playwright/mcp`, non-root, tini |
| `firewall/server.js` | The gateway (no dependencies) |
| `firewall/gen-token.js` | Creates a client token and its hash |
| `config/auth-map.example.json` | Template auth map; copy to `config/auth-map.json` |
| `egress/squid.conf`, `egress/allowed-domains.txt` | Egress proxy and its domain allowlist |
| `docker-compose.yml` | Wires the three containers together |

## Set up

**1. Create a token per client**

```bash
node firewall/gen-token.js
# or, without Node installed:
docker compose build firewall && docker run --rm mcp-firewall node gen-token.js
```

Keep the **token** for the client. Put the **tokenSha256** in the auth map. The token itself is never stored.

**2. Write the auth map**

```bash
cp config/auth-map.example.json config/auth-map.json
```

Paste each hash into `tokenSha256`, then set each client's policy:

```json
"claude-code": {
  "tokenSha256": "<64 hex chars>",
  "tools": { "allow": ["browser_*"], "deny": ["browser_run_code_unsafe", "browser_evaluate"] },
  "urls":  { "allow": ["https://example.com", "https://*.wikipedia.org"] },
  "rateLimitPerMinute": 120
}
```

- Patterns use `*` as a wildcard. Deny wins over allow.
- URL patterns match the **origin** (`scheme://host[:port]`). `https://*.wikipedia.org` does **not** match `https://wikipedia.org`, so list both if needed.
- The gateway refuses to start while placeholder hashes are present. It reloads the file automatically when you edit it.
- `auth-map.json` is git-ignored.

**3. Set the egress allowlist**

List every domain the browser may load in `egress/allowed-domains.txt`, including the CDNs those sites use. A leading dot covers subdomains. Restart after editing: `docker compose restart egress`.

**4. Start**

```bash
docker compose up -d --build
docker compose logs -f firewall
```

Endpoint: `http://localhost:8080/mcp`

**Apple Silicon / ARM:** Edge for Linux is amd64-only. Compose sets `platform: linux/amd64` for the Edge container, so it runs under emulation and is slower.

## Connect Claude

**Claude Code**

```bash
claude mcp add --transport http edge-browser http://localhost:8080/mcp \
  --header "Authorization: Bearer mcpfw_YOUR_TOKEN"
```

Run `/mcp` inside Claude Code to confirm.

**Claude Desktop**: in `claude_desktop_config.json` (Settings → Developer → Edit Config):

```json
{
  "mcpServers": {
    "edge-browser": {
      "command": "npx",
      "args": ["-y", "mcp-remote", "http://localhost:8080/mcp",
               "--header", "Authorization:${AUTH_HEADER}"],
      "env": { "AUTH_HEADER": "Bearer mcpfw_YOUR_TOKEN" }
    }
  }
}
```

**claude.ai custom connectors** need OAuth 2.1 and a public HTTPS URL. This gateway uses static bearer tokens, so it's suited to Claude Code, Claude Desktop and other clients you configure yourself.

**Test it:** *"Open https://example.com in Edge and tell me the page heading."* Then try a site that isn't allowed. Claude should get `Blocked by MCP firewall: …`.

## What a blocked call looks like

Blocked tool calls return a normal tool result with `isError: true`, so Claude sees the reason and can adjust:

```
Blocked by MCP firewall: https://evil.example is not in this client's URL allow list
```

Every decision is logged as one JSON line:

```bash
docker compose logs firewall | grep '"blocked"'
docker compose exec egress tail -f /var/log/squid/access.log
```

## Firewall settings

| Env var | Default | Meaning |
|---|---|---|
| `UPSTREAM_URL` | `http://edge-mcp:8931/mcp` | MCP server to protect |
| `AUTH_MAP_PATH` | `/config/auth-map.json` | Auth map location |
| `PORT` / `HOST` | `8080` / `0.0.0.0` | Listen address inside the container |
| `ALLOWED_ORIGINS` | empty | Comma-separated browser origins allowed; requests with any other `Origin` get 403 |
| `MAX_BODY_BYTES` | `1000000` | Request size limit |

The gateway is generic. Point `UPSTREAM_URL` at any Streamable HTTP MCP server to put the same policy layer in front of it.

## Security notes

- **Default tools to deny:** `browser_run_code_unsafe` (runs arbitrary code in the server, so it's equivalent to remote code execution), `browser_evaluate` (arbitrary page JavaScript), `browser_file_upload` and `browser_drop` (read files from the container).
- **Tokens are bearer secrets.** Anyone holding one gets that client's permissions. Rotate a token by generating a new one and replacing the hash.
- **Keep port 8080 on `127.0.0.1`.** To reach it from elsewhere, put a TLS reverse proxy in front and never serve plain HTTP across a network.
- **Treat web content as untrusted.** Pages can contain prompt injection aimed at Claude. The firewall limits what a hijacked session can do; it doesn't stop the injection itself. Keep Claude's approval prompts on for form submissions and logins.
- **Isolation per session:** Edge runs with `--isolated`, so nothing persists between sessions. Each client's session can be used only by that client's token.

## Troubleshooting

| Problem | Fix |
|---|---|
| Firewall exits with `auth_map_invalid` | A `tokenSha256` is still a placeholder or isn't 64 hex characters |
| `401` | Missing/wrong `Authorization: Bearer` header, or the hash doesn't match the token |
| `404 Session not found` after restarting the firewall | Expected: sessions are re-bound on restart. The client re-initialises automatically |
| Pages fail to load / `ERR_TUNNEL_CONNECTION_FAILED` | Domain (or its CDN) missing from `egress/allowed-domains.txt` |
| Edge crashes / "Target closed" | Increase `shm_size` (1–2 GB) |
| `exec format error` on Mac/ARM | Keep `platform: linux/amd64` |
