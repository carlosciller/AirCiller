import { lstatSync, readFileSync, writeFileSync } from 'node:fs';
import { homedir } from 'node:os';
import { join } from 'node:path';

const [tunnelID, binary] = process.argv.slice(2);
if (!/^tunnel_[a-zA-Z0-9]+$/.test(tunnelID ?? '') || !binary?.startsWith('/')) throw new Error('Invalid tunnel arguments');
const root = join(homedir(), 'Library/Application Support/AirCillerPrivateRelay');
for (const name of ['runtime-key', 'mcp-token']) {
  const info = lstatSync(join(root, name));
  if (!info.isFile() || info.uid !== process.getuid() || (info.mode & 0o077) !== 0) throw new Error('Unsafe key file');
}
const token = readFileSync(join(root, 'mcp-token'), 'utf8').trim();
if (!/^[a-f0-9]{64}$/.test(token)) throw new Error('Invalid private bearer');
writeFileSync(join(root, 'mcp-authorization'), `Bearer ${token}`, {mode: 0o600, flag: 'wx'});
const args = [binary, 'run', '--control-plane.tunnel-id', tunnelID,
  '--control-plane.api-key', `file:${join(root, 'runtime-key')}`,
  '--mcp.server-url', 'http://127.0.0.1:18787/mcp',
  '--mcp.extra-headers', `Authorization: file:${join(root, 'mcp-authorization')}`,
  '--mcp.discovery-extra-headers', `Authorization: file:${join(root, 'mcp-authorization')}`,
  '--mcp.max-concurrent-requests', '4', '--control-plane.max-inflight', '4',
  '--health.listen-addr', '127.0.0.1:18789', '--log.level', 'warn', '--log.format', 'json'];
const xml = x => x.replaceAll('&', '&amp;').replaceAll('<', '&lt;').replaceAll('>', '&gt;');
const label = 'local.airciller.private-tunnel';
writeFileSync(join(root, `${label}.plist`), `<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0"><dict><key>Label</key><string>${label}</string>
<key>ProgramArguments</key><array>${args.map(x => `<string>${xml(x)}</string>`).join('')}</array>
<key>RunAtLoad</key><true/><key>KeepAlive</key><true/><key>ThrottleInterval</key><integer>20</integer>
<key>ProcessType</key><string>Background</string><key>Umask</key><integer>63</integer>
</dict></plist>`, {mode: 0o600, flag: 'wx'});
console.log('Separate private tunnel prepared. Literal keys are not in the launch configuration.');
