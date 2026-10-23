import { mkdirSync, writeFileSync, readFileSync, copyFileSync, chmodSync, existsSync } from 'node:fs';
import { homedir } from 'node:os';
import { join, dirname } from 'node:path';
import { fileURLToPath } from 'node:url';
import { randomBytes, randomUUID, X509Certificate, createHash } from 'node:crypto';
import { execFileSync } from 'node:child_process';

// Run on the home server as its ordinary logged-in service owner. Never writes
// another service's configuration, requests sudo, or installs a root daemon.
const [host, nodePath] = process.argv.slice(2);
if (!host || !/^[a-zA-Z0-9][a-zA-Z0-9.-]{0,252}$/.test(host) || !host.includes('.')
    || !nodePath?.startsWith('/') || !existsSync(nodePath)) throw new Error('Expected private DNS host and absolute Node path');
const root = join(homedir(), 'Library/Application Support/AirCillerPrivateRelay');
if (existsSync(root)) throw new Error('Existing installation preserved; inspect before reprovisioning');
mkdirSync(root, {recursive: true, mode: 0o700});
chmodSync(root, 0o700);
const source = dirname(fileURLToPath(import.meta.url));
for (const file of ['server.mjs', 'relay.mjs', 'http.mjs', 'listener-address.mjs']) {
  copyFileSync(join(source, file), join(root, file)); chmodSync(join(root, file), 0o600);
}
const privateWrite = (name, value) => writeFileSync(join(root, name), value, {mode: 0o600, flag: 'wx'});
privateWrite('openssl.cnf', '[req]\ndistinguished_name=dn\nx509_extensions=server\n[dn]\n[server]\n'
  + `subjectAltName=DNS:${host}\nbasicConstraints=critical,CA:TRUE\n`
  + 'keyUsage=critical,digitalSignature,keyEncipherment,keyCertSign\nextendedKeyUsage=serverAuth\n');
execFileSync('/usr/bin/openssl', ['req', '-x509', '-newkey', 'rsa:2048', '-nodes', '-keyout', join(root, 'tls.key'),
  '-out', join(root, 'tls.pem'), '-subj', `/CN=${host}`, '-days', '365', '-sha256', '-config', join(root, 'openssl.cnf')],
  {stdio: 'ignore'});
chmodSync(join(root, 'tls.key'), 0o600);
const commandKey = randomBytes(32).toString('base64'), installationID = randomUUID();
const agentToken = randomBytes(32).toString('hex'), mcpToken = randomBytes(32).toString('hex');
const mcpPort = 18787, agentPort = 18788;
privateWrite('relay.json', JSON.stringify({mcpToken, agentToken, commandKey, installationID, mcpPort, agentPort,
  agentHost: host, tlsKey: join(root, 'tls.key'), tlsCertificate: join(root, 'tls.pem')}));
const certificateSHA256 = createHash('sha256').update(new X509Certificate(readFileSync(join(root, 'tls.pem'))).raw).digest('hex');
privateWrite('client.json', JSON.stringify({endpoint: `https://${host}:${agentPort}`, agentToken, commandKey,
  installationID, certificateSHA256}));
// The MCP bearer is provided to the tunnel through an environment reference,
// never a command argument, published file, or diagnostic response.
privateWrite('mcp-token', mcpToken);
const xml = x => x.replaceAll('&', '&amp;').replaceAll('<', '&lt;').replaceAll('>', '&gt;');
const label = 'local.airciller.private-relay';
privateWrite(`${label}.plist`, `<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0"><dict><key>Label</key><string>${label}</string>
<key>ProgramArguments</key><array><string>${xml(nodePath)}</string><string>${xml(join(root, 'server.mjs'))}</string><string>${xml(join(root, 'relay.json'))}</string></array>
<key>RunAtLoad</key><true/><key>KeepAlive</key><true/><key>ThrottleInterval</key><integer>10</integer>
<key>ProcessType</key><string>Background</string><key>Umask</key><integer>63</integer>
</dict></plist>`);
console.log('Private relay prepared, not started. No tunnel key or other service was changed.');
