import { mkdirSync, copyFileSync, writeFileSync, existsSync } from 'node:fs';
import { homedir } from 'node:os';
import { dirname, join } from 'node:path';
import { fileURLToPath } from 'node:url';
import { execFileSync } from 'node:child_process';

const source=dirname(fileURLToPath(import.meta.url));
const root=join(homedir(),'Library/Application Support/AirCiller/PrivateRemote');
const helper=process.argv[2];
const label='local.airciller.private-lifecycle';
const agents=join(homedir(),'Library/LaunchAgents');
const plist=join(agents,`${label}.plist`);
if(existsSync(plist)) throw Error('Existing service preserved; inspect before replacing');
if (!helper?.startsWith('/') || !existsSync(helper) || !existsSync(join(root,'client.json')))
  throw Error('Compiled helper and provisioned private configuration required');
for (const [from,to] of [[helper,'lifecycle-helper'],[join(source,'lifecycle-agent.mjs'),'lifecycle-agent.mjs']])
  copyFileSync(from,join(root,to));
execFileSync('/bin/chmod',['700',join(root,'lifecycle-helper')]);
execFileSync('/bin/chmod',['600',join(root,'lifecycle-agent.mjs')]);
const xml=s=>s.replaceAll('&','&amp;').replaceAll('<','&lt;').replaceAll('>','&gt;');
mkdirSync(agents,{recursive:true});
writeFileSync(plist,`<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0"><dict><key>Label</key><string>${label}</string>
<key>ProgramArguments</key><array>${[process.execPath,join(root,'lifecycle-agent.mjs'),join(root,'client.json')].map(s=>`<string>${xml(s)}</string>`).join('')}</array>
<key>RunAtLoad</key><true/><key>KeepAlive</key><true/><key>ThrottleInterval</key><integer>15</integer>
<key>ProcessType</key><string>Background</string><key>Umask</key><integer>63</integer>
</dict></plist>`,{mode:0o600,flag:'wx'});
console.log('Lifecycle service prepared; bootstrap in the logged-in user domain.');
