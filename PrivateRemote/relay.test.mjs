import { test } from 'node:test';
import assert from 'node:assert/strict';
import { randomUUID, createDecipheriv } from 'node:crypto';
import { authorized, command, Relay } from './relay.mjs';

test('authentication and closed command arguments', () => {
  assert.equal(authorized('Bearer ' + 'x'.repeat(32), 'x'.repeat(32)), true);
  assert.equal(authorized('Bearer wrong', 'x'.repeat(32)), false);
  assert.equal(authorized(undefined, 'x'.repeat(32)), false);
  assert.throws(() => command('shell', {command: 'ls'}));
  assert.throws(() => command('pause', {extra: true}));
  assert.throws(() => command('play', {itemID: '/private/movie', fromBeginning: false}));
  assert.throws(() => command('skip', {seconds: Infinity}));
  assert.throws(() => command('synchronize', {audio: 6, subtitles: 0}));
  assert.deepEqual(command('pause', {}), {pause: {}});
});

test('encrypted delivery, matching result, duplicate and conflict', async () => {
  const key = Buffer.alloc(32, 7), installationID = randomUUID();
  const relay = new Relay({key, installationID});
  try {
    const request = {name: 'skip', arguments: {seconds: 30}, operationID: randomUUID(), sessionID: randomUUID()};
    const pendingPoll = relay.poll();
    const result = relay.submit(request);
    assert.equal(relay.submit(request), result);
    assert.throws(() => relay.submit({...request, arguments: {seconds: 60}}));
    const delivered = await pendingPoll;
    const bytes = Buffer.from(delivered.payload, 'base64');
    const decipher = createDecipheriv('aes-256-gcm', key, bytes.subarray(0, 12));
    decipher.setAAD(Buffer.from(`AirCiller.remote.command.v1:${installationID.toUpperCase()}`));
    decipher.setAuthTag(bytes.subarray(-16));
    const decoded = JSON.parse(Buffer.concat([decipher.update(bytes.subarray(12, -16)), decipher.final()]));
    assert.equal(decoded.operationID, request.operationID.toUpperCase());
    assert.deepEqual(decoded.command, {skip: {seconds: 30}});
    assert.equal(relay.take(), null);
    const response = {operationID: request.operationID, disposition: 'accepted'};
    assert.throws(() => relay.complete({...delivered, deliveryID: randomUUID(), result: response}));
    relay.complete({...delivered, result: response});
    assert.deepEqual(await result, response);
    assert.deepEqual(await relay.submit(request), response);
  } finally { relay.close(); }
});

test('timeout does not execute again, capacity and shutdown are bounded', async () => {
  const relay = new Relay({key: Buffer.alloc(32, 1), installationID: randomUUID(), timeoutMS: 5, capacity: 1});
  try {
    const request = {name: 'pause', arguments: {}, operationID: randomUUID(), sessionID: randomUUID()};
    const pending = relay.submit(request);
    assert.throws(() => relay.submit({...request, operationID: randomUUID()}));
    assert.equal((await pending).disposition, 'unknown');
    assert.equal(relay.take(), null);
    assert.equal((await relay.submit(request)).code, 'mac_response_timeout');
  } finally { relay.close(); }
});

test('completed delivery releases capacity regardless of UUID letter case', async t => {
  t.mock.timers.enable({apis: ['setTimeout']});
  const relay = new Relay({key: Buffer.alloc(32, 1), installationID: randomUUID(), capacity: 1});
  try {
    const request = {name: 'pause', arguments: {}, operationID: randomUUID(), sessionID: randomUUID()};
    const pending = relay.submit(request);
    const delivery = relay.take();
    const lowerID = delivery.operationID.toLowerCase();
    relay.complete({...delivery, operationID: lowerID,
      result: {operationID: lowerID, disposition: 'accepted'}});
    await pending;
    t.mock.timers.tick(60001);
    assert.equal(relay.pending.size, 0, 'completed response must not permanently occupy the relay');
    const next = relay.submit({...request, operationID: randomUUID()});
    assert.ok(relay.take());
    relay.close();
    await next;
  } finally {relay.close();}
});
