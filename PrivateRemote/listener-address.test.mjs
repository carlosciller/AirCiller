import test from 'node:test';
import assert from 'node:assert/strict';
import {selectAgentAddress} from './listener-address.mjs';

const interfaces = {
  lo0: [{address: '::1', internal: true}, {address: '127.0.0.1', internal: true}],
  en0: [{address: '10.0.0.8', internal: false}, {address: 'fe80::12', internal: false},
    {address: 'fd12::8', internal: false}],
  other: [{address: '10.0.1.8', internal: false}],
};
const entries = (...addresses) => addresses.map(address => ({address}));

test('Bonjour self-resolution skips loopback and binds one advertised local address', () => {
  const resolved = entries('::1', '127.0.0.1', 'fd12::8', '10.0.0.8', 'fe80::12');
  assert.equal(resolved[0].address, '::1', 'old listen(hostname) selects unreachable loopback');
  assert.equal(selectAgentAddress(resolved, interfaces), '10.0.0.8');
  assert.equal(selectAgentAddress(entries('fd12::8'), interfaces), 'fd12::8');
  assert.equal(selectAgentAddress(entries('10.0.1.8'), interfaces), '10.0.1.8');
});

test('listener fails closed without a resolved non-internal interface', () => {
  for (const resolved of [[], entries('::1'), entries('127.0.0.1'), entries('fe80::12'),
    entries('10.0.0.99'), entries('0.0.0.0'), entries('::')]) {
    assert.throws(() => selectAgentAddress(resolved, interfaces), /no_reachable_local_agent_address/);
  }
  assert.throws(() => selectAgentAddress(entries('10.0.0.8'), {lo0: [{address: '10.0.0.8', internal: true}]}));
  assert.throws(() => selectAgentAddress(entries('127.0.0.2'), {bad: [{address: '127.0.0.2', internal: false}]}));
});
