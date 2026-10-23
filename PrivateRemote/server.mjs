import { createServer as httpServer } from 'node:http';
import { createServer as httpsServer } from 'node:https';
import { readFileSync, statSync } from 'node:fs';
import { Relay } from './relay.mjs';
import { mcpHandler, agentHandler } from './http.mjs';
import { resolveAgentAddress } from './listener-address.mjs';

// Private configuration is supplied by the installer, never committed. Runtime
// requires no administrator privileges and does not alter any other service.
const configPath = process.argv[2];
if (!configPath || !configPath.startsWith('/')) throw new Error('Private configuration path required');
const stat = statSync(configPath);
if (!stat.isFile() || (stat.mode & 0o077) !== 0 || stat.size > 16384) throw new Error('Unsafe private configuration');
const config = JSON.parse(readFileSync(configPath, 'utf8'));
if (typeof config.mcpToken !== 'string' || config.mcpToken.length < 32
    || typeof config.agentToken !== 'string' || config.agentToken.length < 32
    || config.agentToken === config.mcpToken) throw new Error('Separate strong credentials required');
for (const port of [config.mcpPort, config.agentPort]) {
  if (!Number.isSafeInteger(port) || port < 1024 || port > 65535) throw new Error('Invalid port');
}
if (config.mcpPort === config.agentPort || typeof config.agentHost !== 'string') throw new Error('Invalid endpoints');
const relay = new Relay({key: Buffer.from(config.commandKey, 'base64'), installationID: config.installationID});
const lifecycle = new Relay({key: Buffer.from(config.commandKey, 'base64'), installationID: config.installationID});
const mcp = httpServer(mcpHandler(relay, config.mcpToken, lifecycle));
const agent = httpsServer({key: readFileSync(config.tlsKey), cert: readFileSync(config.tlsCertificate),
  minVersion: 'TLSv1.3'}, agentHandler(relay, config.agentToken, lifecycle));
for (const server of [mcp, agent]) {
  server.maxConnections = 16;
  server.requestTimeout = 35000;
  server.headersTimeout = 10000;
  server.timeout = 35000;
  server.on('error', () => { process.stderr.write('AirCiller relay listener failed\n'); process.exit(1); });
}
const agentAddress = await resolveAgentAddress(config.agentHost);
mcp.listen(config.mcpPort, '127.0.0.1');
agent.listen(config.agentPort, agentAddress);
let closing = false;
function stop() {
  if (closing) return;
  closing = true; relay.close(); lifecycle.close();
  for (const server of [mcp, agent]) { server.closeAllConnections(); server.close(); }
}
process.on('SIGTERM', stop);
process.on('SIGINT', stop);
