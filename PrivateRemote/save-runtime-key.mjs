import { openSync, writeFileSync, closeSync, lstatSync } from 'node:fs';
import { homedir } from 'node:os';
import { join } from 'node:path';

// Receives only from the owner's hidden terminal input over verified SSH.
// Never accepts a literal credential as an argument or prints it on failure.
const root = join(homedir(), 'Library/Application Support/AirCillerPrivateRelay');
const info = lstatSync(root);
if (!info.isDirectory() || info.isSymbolicLink() || info.uid !== process.getuid()
    || (info.mode & 0o077) !== 0) throw new Error('Unsafe private directory');
let value = '';
for await (const chunk of process.stdin) {
  value += chunk.toString('utf8');
  if (value.length > 512) { process.stderr.write('Invalid key input\n'); process.exit(1); }
}
value = value.trim();
if (!/^sk-[A-Za-z0-9_-]{20,500}$/.test(value)) {
  process.stderr.write('Invalid key format; nothing saved\n'); process.exit(1);
}
const descriptor = openSync(join(root, 'runtime-key'), 'wx', 0o600);
try { writeFileSync(descriptor, value); } finally { closeSync(descriptor); }
value = '';
process.stdout.write('Clave guardada de forma privada en Ciller Home Server.\n');
