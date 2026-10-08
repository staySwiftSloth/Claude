'use strict';
// Generates a client token and the hash to put in auth-map.json.
// Usage: node gen-token.js   (or: docker compose run --rm firewall node gen-token.js)
const crypto = require('node:crypto');

const token = 'mcpfw_' + crypto.randomBytes(32).toString('base64url');
const hash = crypto.createHash('sha256').update(token).digest('hex');

console.log('Token (give this to the MCP client; it is not stored anywhere):');
console.log('  ' + token);
console.log('\ntokenSha256 (paste into config/auth-map.json):');
console.log('  ' + hash);
