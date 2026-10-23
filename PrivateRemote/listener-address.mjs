import {lookup} from 'node:dns/promises';
import {networkInterfaces} from 'node:os';
import {isIP} from 'node:net';

// macOS can resolve its own Bonjour name to loopback before its LAN address.
// Bind one actual non-internal interface advertised by that configured name,
// never every interface or an unrelated address. The MCP listener stays local.
export function selectAgentAddress(resolved, interfaces) {
  const local = new Set(Object.values(interfaces).flatMap(entries => entries ?? [])
    .filter(entry => entry.internal === false).map(entry => entry.address));
  const candidates = resolved.map(entry => entry.address).filter(address => {
    if (!local.has(address)) return false;
    if (isIP(address) === 4) return address !== '0.0.0.0' && !address.startsWith('127.');
    if (isIP(address) === 6) {
      // Unscoped link-local addresses cannot identify an interface reliably.
      return address !== '::' && address !== '::1' && !/^fe[89ab]/i.test(address)
        && !address.toLowerCase().startsWith('::ffff:');
    }
    return false;
  });
  const selected = candidates.find(address => isIP(address) === 4) ?? candidates[0];
  if (!selected) throw Error('no_reachable_local_agent_address');
  return selected;
}

export async function resolveAgentAddress(host) {
  return selectAgentAddress(await lookup(host, {all: true}), networkInterfaces());
}
