import test from 'node:test';
import assert from 'node:assert/strict';
import {createServer} from 'node:https';
import {mkdtempSync, readFileSync, writeFileSync, rmSync} from 'node:fs';
import {tmpdir} from 'node:os';
import {join} from 'node:path';
import {execFileSync} from 'node:child_process';
import {createHash, X509Certificate, randomBytes, randomUUID} from 'node:crypto';
import {createLifecycleTransport} from './lifecycle-agent.mjs';

test('lifecycle authenticates TLS before sending bearer, including reused connections', async () => {
  const directory = mkdtempSync(join(tmpdir(), 'airciller-lifecycle-tls-'));
  let server;
  const clients = [];
  try {
    const certificatePath = join(directory, 'cert.pem'), keyPath = join(directory, 'key.pem');
    const configPath = join(directory, 'openssl.cnf');
    writeFileSync(configPath, '[req]\ndistinguished_name=dn\nx509_extensions=server\n[dn]\n[server]\n'
      + 'subjectAltName=DNS:localhost\nbasicConstraints=critical,CA:TRUE\n'
      + 'keyUsage=critical,digitalSignature,keyEncipherment,keyCertSign\nextendedKeyUsage=serverAuth\n');
    execFileSync('/usr/bin/openssl', ['req', '-x509', '-newkey', 'rsa:2048', '-nodes',
      '-keyout', keyPath, '-out', certificatePath, '-subj', '/CN=localhost',
      '-days', '1', '-sha256', '-config', configPath], {stdio: 'ignore'});
    const cert = readFileSync(certificatePath), token = randomBytes(32).toString('hex');
    let requests = 0;
    const sockets = new Set();
    server = createServer({key: readFileSync(keyPath), cert, minVersion: 'TLSv1.3'}, (req, res) => {
      requests++;
      sockets.add(req.socket);
      assert.equal(req.headers.authorization, `Bearer ${token}`);
      req.resume();
      req.on('end', () => {
        if (req.url === '/redirect') {
          res.writeHead(307, {Location: '/unexpected'}); res.end('{}');
        } else {
          res.writeHead(200); res.end('null');
        }
      });
    });
    await new Promise(r => server.listen(0, '127.0.0.1', r));
    const config = {endpoint: `https://LOCALHOST:${server.address().port}`, agentToken: token,
      commandKey: randomBytes(32).toString('base64'), installationID: randomUUID(),
      certificateSHA256: createHash('sha256').update(new X509Certificate(cert).raw).digest('hex')};
    const transport = overrides => {
      const client = createLifecycleTransport({...config, ...overrides});
      clients.push(client); return client;
    };
    const client = transport({});
    assert.equal(await client.post('/lifecycle/poll', {}), null);
    assert.equal(await client.post('/lifecycle/poll', {}), null);
    assert.equal(sockets.size, 1, 'exercise certificate verification on a reused socket');
    const beforeRejected = requests;
    await assert.rejects(transport({certificateSHA256: '0'.repeat(64)}).post('/lifecycle/poll', {}));
    await assert.rejects(transport({endpoint: `https://127.0.0.1:${server.address().port}`}).post('/lifecycle/poll', {}));
    assert.equal(requests, beforeRejected, 'neither bad pin nor hostname receives HTTP credentials');
    await assert.rejects(client.post('/redirect', {}));
    assert.equal(requests, beforeRejected + 1, 'redirect is not followed');
    for (const overrides of [{endpoint: 'http://localhost'}, {agentToken: 'short'},
      {endpoint: 'https://localhost/other'}, {commandKey: ''}]) {
      assert.throws(() => createLifecycleTransport({...config, ...overrides}));
    }
  } finally {
    for (const client of clients) client.close();
    if (server) {server.closeAllConnections(); await new Promise(r => server.close(r));}
    // Only this test's newly-created synthetic certificate directory.
    rmSync(directory, {recursive: true, force: true});
  }
});
