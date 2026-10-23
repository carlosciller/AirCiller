import { createCipheriv, randomBytes, randomUUID, timingSafeEqual } from 'node:crypto';

const UUID = /^[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}$/i;
export const fields = {
  openApp: [], closeApp: [], appStatus: [],
  status: [], search: ['query'], play: ['itemID', 'fromBeginning'], pause: [], resume: [], stop: [], next: [],
  seek: ['seconds'], skip: ['seconds'], receivers: [], selectReceiver: ['id'], tracks: [],
  selectTracks: ['audioID', 'subtitleID'], synchronize: ['audio', 'subtitles'], preferences: [],
  setLanguages: ['audio', 'subtitles', 'persistent'],
  resolveConversion: ['decisionID', 'approve', 'equivalentEpisodes'], operation: ['id'], cancelOperation: ['id'],
};

export function authorized(header, token) {
  if (typeof token !== 'string' || token.length < 32 || typeof header !== 'string') return false;
  const actual = Buffer.from(header), expected = Buffer.from(`Bearer ${token}`);
  return actual.length === expected.length && timingSafeEqual(actual, expected);
}

export function command(name, args) {
  if (!Object.hasOwn(fields, name) || !args || Array.isArray(args) || typeof args !== 'object') {
    throw new Error('invalid_command');
  }
  if (Object.keys(args).some(k => !fields[name].includes(k))
      || fields[name].some(k => !Object.hasOwn(args, k))) throw new Error('invalid_arguments');
  for (const [key, value] of Object.entries(args)) {
    if (['itemID', 'id', 'decisionID'].includes(key) && (typeof value !== 'string' || !UUID.test(value)))
      throw new Error('invalid_identifier');
    if (['fromBeginning', 'persistent', 'approve', 'equivalentEpisodes'].includes(key) && typeof value !== 'boolean')
      throw new Error('invalid_boolean');
  }
  if (name === 'search' && (typeof args.query !== 'string' || !args.query.trim()
      || Buffer.byteLength(args.query) > 256)) throw new Error('invalid_query');
  if (['skip', 'seek'].includes(name) && (!Number.isFinite(args.seconds)
      || (name === 'skip' ? Math.abs(args.seconds) > 3600 : args.seconds < 0 || args.seconds > 604800)))
    throw new Error('invalid_seconds');
  if (name === 'synchronize' && (!Number.isFinite(args.audio) || Math.abs(args.audio) > 5
      || !Number.isFinite(args.subtitles) || Math.abs(args.subtitles) > 10)) throw new Error('invalid_sync');
  if (name === 'setLanguages' && [args.audio, args.subtitles].some(x => typeof x !== 'string' || !/^(|[a-z]{3})$/.test(x)))
    throw new Error('invalid_language');
  if (name === 'selectTracks' && [args.audioID, args.subtitleID].some(x => x !== null
      && (typeof x !== 'string' || !UUID.test(x)))) throw new Error('invalid_track');
  return { [name]: args };
}

export function seal(envelope, key, installationID) {
  if (key.length !== 32 || !UUID.test(installationID)) throw new Error('invalid_configuration');
  const nonce = randomBytes(12);
  const cipher = createCipheriv('aes-256-gcm', key, nonce);
  cipher.setAAD(Buffer.from(`AirCiller.remote.command.v1:${installationID.toUpperCase()}`));
  const encrypted = Buffer.concat([cipher.update(JSON.stringify(envelope)), cipher.final()]);
  return Buffer.concat([nonce, encrypted, cipher.getAuthTag()]).toString('base64');
}

/** Bounded relay; no files, media, shell, automatic pairing or arbitrary URL access. */
export class Relay {
  constructor({ key, installationID, capacity = 32, timeoutMS = 25000 }) {
    if (key.length !== 32 || !UUID.test(installationID) || capacity < 1) throw new Error('invalid_configuration');
    this.key = key; this.installationID = installationID; this.capacity = capacity; this.timeoutMS = timeoutMS;
    this.pending = new Map(); this.waiter = null;
  }

  submit({ name, arguments: args, operationID, sessionID }) {
    if (!UUID.test(operationID ?? '') || !UUID.test(sessionID ?? '')) throw new Error('missing_request_identity');
    operationID = operationID.toUpperCase();
    sessionID = sessionID.toUpperCase();
    const payload = command(name, args);
    const fingerprint = JSON.stringify([name, Object.entries(args).sort(), sessionID]);
    const existing = this.pending.get(operationID);
    if (existing) {
      if (existing.fingerprint !== fingerprint) throw new Error('conflicting_operation');
      return existing.promise;
    }
    if (this.pending.size >= this.capacity) throw new Error('relay_busy');
    // Client operation/session IDs survive transport retries. Never generate a
    // replacement identity after a timeout, which could repeat a relative seek.
    const envelope = { operationID, sessionID, expiresAt: Date.now() + 45000, command: payload };
    let resolve;
    const promise = new Promise(r => { resolve = r; });
    const entry = { fingerprint, promise, resolve, delivered: false, response: null,
      deliveryID: randomUUID(), payload: seal(envelope, this.key, this.installationID) };
    entry.timer = setTimeout(() => {
      entry.response ??= { disposition: 'unknown', code: 'mac_response_timeout', operationID };
      resolve(entry.response);
      // Retain identity for the entire envelope validity period, including a
      // delivered command whose response was lost. No automatic resubmission.
      entry.cleanup = setTimeout(() => this.pending.delete(operationID), 60000);
      entry.cleanup.unref();
    }, this.timeoutMS);
    this.pending.set(operationID, entry);
    this.wake();
    return promise;
  }

  take() {
    for (const [operationID, entry] of this.pending) {
      if (!entry.delivered && !entry.response) {
        entry.delivered = true;
        return { operationID, deliveryID: entry.deliveryID, payload: entry.payload };
      }
    }
    return null;
  }

  poll() {
    if (this.waiter) throw new Error('agent_already_connected');
    const available = this.take();
    if (available) return Promise.resolve(available);
    return new Promise(resolve => {
      const timer = setTimeout(() => { this.waiter = null; resolve(null); }, this.timeoutMS);
      this.waiter = { resolve, timer };
    });
  }

  wake() {
    if (!this.waiter) return;
    const available = this.take();
    if (!available) return;
    const waiter = this.waiter; this.waiter = null;
    clearTimeout(waiter.timer); waiter.resolve(available);
  }

  complete({ operationID, deliveryID, result }) {
    operationID = typeof operationID === 'string' ? operationID.toUpperCase() : '';
    const entry = this.pending.get(operationID);
    if (!entry || !entry.delivered || typeof deliveryID !== 'string'
        || entry.deliveryID.toUpperCase() !== deliveryID.toUpperCase() || entry.response
        || !result || typeof result.operationID !== 'string'
        || result.operationID.toLowerCase() !== operationID.toLowerCase() || JSON.stringify(result).length > 262144)
      throw new Error('unknown_delivery');
    entry.response = result;
    clearTimeout(entry.timer); entry.resolve(result);
    entry.cleanup = setTimeout(() => this.pending.delete(operationID), 60000);
    entry.cleanup.unref();
  }

  close() {
    if (this.waiter) { clearTimeout(this.waiter.timer); this.waiter.resolve(null); this.waiter = null; }
    for (const entry of this.pending.values()) {
      clearTimeout(entry.timer); clearTimeout(entry.cleanup);
      entry.resolve({ disposition: 'unknown', code: 'relay_stopped' });
    }
    this.pending.clear();
  }
}
