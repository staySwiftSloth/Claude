# syntax=docker/dockerfile:1
#
# Playwright MCP server driving Microsoft Edge (headless), exposed over
# Streamable HTTP at http://<host>:8931/mcp for Claude to connect to.
#
# Note: Microsoft only ships Edge for Linux on x86-64 (amd64). On Apple Silicon
# or other ARM hosts, build/run with --platform linux/amd64 (emulated, slower).

FROM node:22-bookworm-slim

# Pin this to a specific version for reproducible builds, e.g. 0.0.70
ARG PLAYWRIGHT_MCP_VERSION=latest
ENV DEBIAN_FRONTEND=noninteractive

# --- Microsoft Edge (stable) from Microsoft's apt repo, plus fonts and tini ---
RUN apt-get update \
 && apt-get install -y --no-install-recommends ca-certificates curl gnupg \
 && curl -fsSL https://packages.microsoft.com/keys/microsoft.asc \
      | gpg --dearmor -o /usr/share/keyrings/microsoft-edge.gpg \
 && echo "deb [arch=amd64 signed-by=/usr/share/keyrings/microsoft-edge.gpg] https://packages.microsoft.com/repos/edge stable main" \
      > /etc/apt/sources.list.d/microsoft-edge.list \
 && apt-get update \
 && apt-get install -y --no-install-recommends \
      microsoft-edge-stable \
      fonts-liberation fonts-noto-color-emoji fonts-noto-cjk \
      tini \
 && apt-get purge -y gnupg \
 && apt-get autoremove -y \
 && rm -rf /var/lib/apt/lists/*

# --- Playwright MCP server ---
WORKDIR /app
RUN npm install --omit=dev "@playwright/mcp@${PLAYWRIGHT_MCP_VERSION}" \
 && npm cache clean --force

# Writable dirs for screenshots/PDFs/traces and an optional persistent profile
RUN mkdir -p /data/output /data/profile && chown -R node:node /data /app

# Run as the unprivileged 'node' user that ships with the base image
USER node

EXPOSE 8931

HEALTHCHECK --interval=30s --timeout=5s --start-period=20s --retries=3 \
  CMD node -e "require('net').connect(8931,'127.0.0.1').on('connect',()=>process.exit(0)).on('error',()=>process.exit(1))"

# tini reaps zombie browser processes and forwards signals cleanly
ENTRYPOINT ["/usr/bin/tini", "--", "node", "/app/node_modules/@playwright/mcp/cli.js"]

# Default flags (override by passing your own args to `docker run`):
#   --browser msedge        use Microsoft Edge instead of Chromium
#   --headless              no display in the container
#   --no-sandbox            Chromium-family sandbox needs privileges a container lacks
#   --host 0.0.0.0          listen on all interfaces inside the container
#   --port 8931             enables the HTTP transport (endpoint: /mcp)
#   --allowed-hosts *       disables Host-header check so the mapped port works;
#                           keep the port bound to 127.0.0.1 on the host (see compose)
#   --isolated              fresh in-memory profile per session; nothing written to disk
CMD ["--browser", "msedge", \
     "--headless", \
     "--no-sandbox", \
     "--host", "0.0.0.0", \
     "--port", "8931", \
     "--allowed-hosts", "*", \
     "--isolated", \
     "--output-dir", "/data/output"]
