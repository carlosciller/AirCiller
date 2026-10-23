import { test } from 'node:test';
import assert from 'node:assert/strict';
import { createServer } from 'node:http';
import { randomUUID } from 'node:crypto';
import { Relay } from './relay.mjs';
import { mcpHandler } from './http.mjs';

test('loopback MCP rejects anonymous access and exposes bounded tools', async () => {
  const token = 'a'.repeat(32);
  const relay = new Relay({key: Buffer.alloc(32, 1), installationID: randomUUID()});
  const server = createServer(mcpHandler(relay, token));
  await new Promise(resolve => server.listen(0, '127.0.0.1', resolve));
  const url = `http://127.0.0.1:${server.address().port}/mcp`;
  try {
    assert.equal((await fetch(url, {method: 'POST'})).status, 401);
    for (const path of ['/', '/.well-known/oauth-protected-resource', '/.well-known/oauth-protected-resource/mcp',
      '/.well-known/oauth-authorization-server', '/.well-known/openid-configuration']) {
      assert.equal((await fetch(new URL(path, url))).status, 404);
    }
    assert.equal((await fetch(url)).status, 401, 'discovery absence does not expose the MCP endpoint');
    const headers = {Authorization: `Bearer ${token}`, 'Content-Type': 'application/json'};
    const call = async (method, params) => (await fetch(url, {method: 'POST', headers,
      body: JSON.stringify({jsonrpc: '2.0', id: 1, method, params})})).json();
    const listing = await call('tools/list');
    assert.equal(listing.result.tools.length, 22);
    assert.equal(listing.result.tools.some(t => /shell|file|exec/.test(t.name)), false);
    assert.equal((await call('tools/call', {name: 'airciller_shell', arguments: {}})).error.code, -32602);
    assert.equal((await call('initialize', {})).result.serverInfo.name, 'AirCiller Private');
    assert.equal((await fetch(url, {method: 'POST', headers: {...headers, Origin: 'https://example.invalid'}})).status, 403);
  } finally { relay.close(); server.closeAllConnections(); await new Promise(r => server.close(r)); }
});
