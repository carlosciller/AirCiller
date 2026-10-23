import https from 'node:https';
import { checkServerIdentity } from 'node:tls';
import { readFileSync, lstatSync } from 'node:fs';
import { createDecipheriv, createHash } from 'node:crypto';
import { execFile } from 'node:child_process';
import { promisify } from 'node:util';
import { fileURLToPath } from 'node:url';

const execute = promisify(execFile);
const uuid = /^[a-f0-9]{8}-[a-f0-9]{4}-[a-f0-9]{4}-[a-f0-9]{4}-[a-f0-9]{12}$/i;
const record = value => value !== null && typeof value === 'object' && !Array.isArray(value);
export function decodeLifecycle(payload, config) {
  const bytes = Buffer.from(payload, 'base64');
  if (bytes.length < 29 || bytes.length > 24000) throw Error('invalid_envelope');
  const decipher = createDecipheriv('aes-256-gcm', Buffer.from(config.commandKey, 'base64'), bytes.subarray(0, 12));
  decipher.setAAD(Buffer.from(`AirCiller.remote.command.v1:${config.installationID.toUpperCase()}`));
  decipher.setAuthTag(bytes.subarray(-16));
  const envelope = JSON.parse(Buffer.concat([decipher.update(bytes.subarray(12, -16)), decipher.final()]));
  if (!record(envelope) || !record(envelope.command)) throw Error('invalid_command');
  const keys = Object.keys(envelope.command);
  if (!uuid.test(envelope.operationID) || !uuid.test(envelope.sessionID)
      || !Number.isFinite(envelope.expiresAt) || envelope.expiresAt < Date.now()
      || envelope.expiresAt > Date.now() + 60000 || keys.length !== 1
      || !['openApp', 'closeApp', 'appStatus'].includes(keys[0])
      || !record(envelope.command[keys[0]])
      || Object.keys(envelope.command[keys[0]]).length) throw Error('invalid_command');
  return { ...envelope, action: {openApp: 'open', closeApp: 'close', appStatus: 'status'}[keys[0]] };
}

// Status is a fresh read, so it must not consume the mutation replay budget.
// Retain mutation identities for this process lifetime and fail explicitly when
// full. Evicting an old open/close operation could execute an uncertain retry.
export class LifecycleDispatcher {
  constructor(run, capacity = 1024) {
    this.run = run;
    this.capacity = capacity;
    this.completed = new Map();
  }

  async dispatch(envelope) {
    const operationID = envelope.operationID.toUpperCase();
    const rejected = code => ({operationID, disposition: 'rejected', code});
    const perform = async () => {
      try {
        const state = await this.run(envelope.action);
        if (!['running', 'closed', 'disabled'].includes(state)) throw Error('invalid_state');
        return state === 'disabled' ? rejected('private_control_disabled')
          : {operationID, disposition: 'result', appState: state};
      } catch {return rejected('app_lifecycle_failed');}
    };
    if (envelope.action === 'status') return perform();
    const fingerprint = JSON.stringify([envelope.sessionID.toUpperCase(), envelope.action]);
    const previous = this.completed.get(operationID);
    if (previous) return previous.fingerprint === fingerprint ? previous.promise : rejected('operation_conflict');
    if (this.completed.size >= this.capacity) return rejected('operation_capacity');
    const promise = perform();
    this.completed.set(operationID, {fingerprint, promise});
    return promise;
  }
}

export function createLifecycleTransport(config) {
  const endpoint = new URL(config.endpoint);
  if (endpoint.protocol !== 'https:' || endpoint.username || endpoint.password
      || endpoint.search || endpoint.hash || endpoint.pathname !== '/'
      || typeof config.agentToken !== 'string' || !/^[\x21-\x7e]{32,256}$/.test(config.agentToken)
      || Buffer.from(config.commandKey, 'base64').length !== 32
      || !uuid.test(config.installationID) || !/^[a-f0-9]{64}$/i.test(config.certificateSHA256))
    throw Error('invalid_configuration');
  const agent = new https.Agent({keepAlive: true, ca: undefined});
  function post(path, value) {
    return new Promise((resolve, reject) => {
      const request = https.request(new URL(path, endpoint), {
        method: 'POST', agent, rejectUnauthorized: false,
        headers: {Authorization: `Bearer ${config.agentToken}`, 'Content-Type': 'application/json'},
      }, response => {
        let size = 0; const chunks = [];
        response.on('data', chunk => {size += chunk.length; if (size > 65536) response.destroy(Error('oversized')); else chunks.push(chunk);});
        response.on('error', reject);
        response.on('end', () => {
          if (response.statusCode !== 200) return reject(Error('unavailable'));
          try {resolve(JSON.parse(Buffer.concat(chunks)));} catch {reject(Error('invalid_response'));}
        });
      });
      // The private self-signed endpoint is authenticated by its exact certificate
      // digest. Never send the bearer until the TLS socket's pin is verified.
      request.on('socket', socket => {
        const send = () => {
          const certificate = socket.getPeerCertificate();
          const validTo = Date.parse(certificate.valid_to), validFrom = Date.parse(certificate.valid_from);
          if (!certificate.raw || createHash('sha256').update(certificate.raw).digest('hex') !== config.certificateSHA256.toLowerCase()
              || !Number.isFinite(validTo) || !Number.isFinite(validFrom)
              || validTo < Date.now() || validFrom > Date.now()
              || checkServerIdentity(endpoint.hostname, certificate)) {
            request.destroy(Error('certificate_rejected')); return;
          }
          request.end(JSON.stringify(value));
        };
        if (socket.connecting) socket.once('secureConnect', send); else send();
      });
      request.setTimeout(35000, () => request.destroy(Error('timeout')));
      request.on('error', reject);
    });
  }
  return {post, close: () => agent.destroy()};
}

async function main() {
  const configPath = process.argv[2], helper = fileURLToPath(new URL('./lifecycle-helper', import.meta.url));
  const stat = lstatSync(configPath);
  if (!stat.isFile() || stat.uid !== process.getuid() || (stat.mode & 0o077) || stat.size > 16384)
    throw Error('unsafe_configuration');
  const config = JSON.parse(readFileSync(configPath, 'utf8'));
  const {post} = createLifecycleTransport(config);
  const dispatcher = new LifecycleDispatcher(async action => {
    const output = await execute(helper, [action], {timeout: 15000, maxBuffer: 1024});
    return output.stdout.trim();
  });
  while (true) {
    try {
      const delivery = await post('/lifecycle/poll', {});
      if (!delivery) continue;
      const envelope = decodeLifecycle(delivery.payload, config);
      if (envelope.operationID.toUpperCase() !== delivery.operationID.toUpperCase()) throw Error('identity');
      const result = await dispatcher.dispatch(envelope);
      await post('/lifecycle/result', {...delivery, payload: undefined, result});
    } catch {await new Promise(resolve => setTimeout(resolve, 5000));}
  }
}
if (process.argv[1] === fileURLToPath(import.meta.url)) main().catch(() => {process.stderr.write('Lifecycle configuration unavailable\n'); process.exitCode = 1;});
