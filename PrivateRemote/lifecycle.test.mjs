import test from 'node:test';
import assert from 'node:assert/strict';
import { randomBytes, randomUUID } from 'node:crypto';
import { seal, Relay } from './relay.mjs';
import { decodeLifecycle, LifecycleDispatcher } from './lifecycle-agent.mjs';

test('lifecycle accepts only authenticated, unexpired fixed actions', () => {
  const key = randomBytes(32), installationID = randomUUID();
  const config = {commandKey: key.toString('base64'), installationID};
  const envelope = {operationID: randomUUID(), sessionID: randomUUID(), expiresAt: Date.now()+30000, command: {openApp:{}}};
  const encoded = seal(envelope,key,installationID);
  assert.equal(decodeLifecycle(encoded,config).action,'open');
  assert.throws(()=>decodeLifecycle(encoded,{...config,commandKey:randomBytes(32).toString('base64')}));
  assert.throws(()=>decodeLifecycle(seal({...envelope,expiresAt:Date.now()-1},key,installationID),config));
  for (const command of [{play:{}},{openApp:{path:'/tmp/other.app'}},{openApp:{},closeApp:{}},
    {openApp: []}, {openApp: null}, {openApp: 1}, {openApp: ''}])
    assert.throws(()=>decodeLifecycle(seal({...envelope,command},key,installationID),config));
});

test('lifecycle reads stay fresh without exhausting mutation capacity', async () => {
  const calls = [];
  const dispatcher = new LifecycleDispatcher(async action => {
    calls.push(action);
    return calls.length % 2 ? 'running' : 'closed';
  }, 1);
  const envelope = {operationID: randomUUID(), sessionID: randomUUID(), action: 'status'};
  for (let i = 0; i < 1030; i++) {
    const result = await dispatcher.dispatch({...envelope, operationID: randomUUID()});
    assert.equal(result.appState, i % 2 ? 'closed' : 'running');
  }
  assert.equal(dispatcher.completed.size, 0);
  const close = {...envelope, operationID: randomUUID(), action: 'close'};
  const first = await dispatcher.dispatch(close);
  assert.equal(first.disposition, 'result');
  assert.deepEqual(await dispatcher.dispatch({...close, operationID: close.operationID.toUpperCase()}), first);
  assert.equal(calls.length, 1031, 'retry must not run the helper twice');
  assert.equal((await dispatcher.dispatch({...close, action: 'open'})).code, 'operation_conflict');
  assert.equal((await dispatcher.dispatch({...close, operationID: randomUUID()})).code, 'operation_capacity');
  assert.equal((await dispatcher.dispatch(envelope)).disposition, 'result', 'status still works at mutation capacity');
});

test('concurrent lifecycle retries share execution and retain failures', async () => {
  let calls = 0;
  let finish;
  const dispatcher = new LifecycleDispatcher(() => {calls++; return new Promise(r => {finish = r;});});
  const envelope = {operationID: randomUUID(), sessionID: randomUUID(), action: 'open'};
  const a = dispatcher.dispatch(envelope), b = dispatcher.dispatch(envelope);
  finish('disabled');
  assert.equal((await a).code, 'private_control_disabled');
  assert.deepEqual(await a, await b);
  assert.equal(calls, 1);
});

test('lifecycle queue is independent of playback and retries retain identity', async () => {
  const key=randomBytes(32), installationID=randomUUID();
  const playback=new Relay({key,installationID}), lifecycle=new Relay({key,installationID});
  try {
    const request={name:'closeApp',arguments:{},operationID:randomUUID(),sessionID:randomUUID()};
    const result=lifecycle.submit(request);
    assert.equal(playback.take(),null);
    const delivery=lifecycle.take();
    assert.ok(delivery);
    assert.equal(lifecycle.take(),null);
    assert.equal(lifecycle.submit(request),result);
    lifecycle.complete({...delivery,result:{operationID:delivery.operationID,disposition:'result',appState:'closed'}});
    assert.equal((await result).appState,'closed');
  } finally {playback.close();lifecycle.close();}
});
