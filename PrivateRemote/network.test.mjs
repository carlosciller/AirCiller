import { test } from 'node:test';
import assert from 'node:assert/strict';
import { createServer as httpServer } from 'node:http';
import { createServer as httpsServer } from 'node:https';
import { mkdtempSync, readFileSync, writeFileSync, rmSync } from 'node:fs';
import { tmpdir } from 'node:os';
import { join, resolve } from 'node:path';
import { spawn, execFileSync } from 'node:child_process';
import { randomBytes, randomUUID, X509Certificate, createHash } from 'node:crypto';
import { Relay } from './relay.mjs';
import { agentHandler, mcpHandler } from './http.mjs';

test('Swift coordinator through real HTTPS relay and authenticated MCP', {timeout: 180000}, async () => {
  const directory = mkdtempSync(join(tmpdir(), 'airciller-remote-fixture-'));
  const key = randomBytes(32), installationID = randomUUID();
  const agentToken = randomBytes(32).toString('hex'), mcpToken = randomBytes(32).toString('hex');
  const relay = new Relay({key, installationID});
  let child, agent, mcp;
  try {
    const tlsKey = join(directory, 'key.pem'), tlsCert = join(directory, 'cert.pem');
    const tlsConfig = join(directory, 'openssl.cnf');
    writeFileSync(tlsConfig, '[req]\ndistinguished_name=dn\nx509_extensions=server\n'
      + '[dn]\n[server]\nsubjectAltName=IP:127.0.0.1,DNS:localhost\nbasicConstraints=critical,CA:TRUE\n'
      + 'keyUsage=critical,digitalSignature,keyEncipherment,keyCertSign\nextendedKeyUsage=serverAuth\n');
    execFileSync('/usr/bin/openssl', ['req', '-x509', '-newkey', 'rsa:2048', '-nodes', '-keyout', tlsKey,
      '-out', tlsCert, '-subj', '/CN=localhost', '-days', '1', '-sha256', '-config', tlsConfig], {stdio: 'ignore'});
    const cert = readFileSync(tlsCert);
    let pollArrived;
    const ready = new Promise(r => { pollArrived = r; });
    const handler = agentHandler(relay, agentToken);
    let authenticatedPolls = 0;
    agent = httpsServer({key: readFileSync(tlsKey), cert, minVersion: 'TLSv1.3'}, (req, res) => {
      if (req.url === '/agent/poll' && req.headers.authorization === `Bearer ${agentToken}`) {
        authenticatedPolls++;
        // A real dropped transport must reconnect without replaying a command.
        if (authenticatedPolls === 1) { req.socket.destroy(); return; }
        pollArrived();
      }
      handler(req, res);
    });
    mcp = httpServer(mcpHandler(relay, mcpToken));
    await new Promise(r => agent.listen(0, '127.0.0.1', r));
    await new Promise(r => mcp.listen(0, '127.0.0.1', r));
    const fixture = join(directory, 'fixture.json');
    writeFileSync(fixture, JSON.stringify({endpoint: `https://LOCALHOST:${agent.address().port}`,
      agentToken, commandKey: key.toString('base64'), installationID,
      certificateSHA256: createHash('sha256').update(new X509Certificate(cert).raw).digest('hex')}), {mode: 0o600});
    child = spawn('/bin/zsh', ['./Scripts/check_library_coordinator.sh'], {cwd: resolve('.'),
      env: {...process.env, AIRCILLER_REMOTE_NETWORK_FIXTURE: fixture}, stdio: ['ignore', 'pipe', 'pipe']});
    let output = '';
    child.stdout.on('data', d => { output += d; }); child.stderr.on('data', d => { output += d; });
    const exited = new Promise(r => child.once('exit', code => r(code)));
    await Promise.race([ready, exited.then(() => { throw new Error(`Swift fixture exited before connecting: ${output}`); })]);
    async function call(name, sessionID) {
      const response = await fetch(`http://127.0.0.1:${mcp.address().port}/mcp`, {method: 'POST',
        headers: {Authorization: `Bearer ${mcpToken}`, 'Content-Type': 'application/json'},
        body: JSON.stringify({jsonrpc: '2.0', id: 1, method: 'tools/call', params: {
          name: `airciller_${name}`, arguments: {operationID: randomUUID(), sessionID, arguments: {}}}})});
      const rpc = await response.json();
      assert.ok(rpc.result, JSON.stringify(rpc));
      return JSON.parse(rpc.result.content[0].text);
    }
    const status = await call('status', randomUUID());
    assert.equal(status.disposition, 'result');
    assert.equal(status.snapshot.phase, 'idle');
    const stopped = await call('stop', status.snapshot.sessionID);
    assert.equal(stopped.disposition, 'accepted');
    assert.notEqual(stopped.snapshot.sessionID, status.snapshot.sessionID);
    assert.equal(await exited, 0, output);
    assert.match(output, /Private remote TLS integration: OK/);
    assert.ok(authenticatedPolls >= 2, 'client recovered from the deliberately dropped poll');
  } finally {
    if (child && child.exitCode === null) child.kill('SIGTERM');
    relay.close();
    for (const server of [agent, mcp]) if (server) { server.closeAllConnections(); await new Promise(r => server.close(r)); }
    // Only this test's uniquely-created disposable certificate/config directory.
    rmSync(directory, {recursive: true, force: true});
  }
});
