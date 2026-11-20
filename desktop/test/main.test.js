'use strict';

// Loads src/main.js with a stubbed `electron` module to test the connect flow:
// server selection, failover to the next server, cancel and disconnect.
const test = require('node:test');
const assert = require('node:assert/strict');
const Module = require('node:module');
const os = require('node:os');
const fs = require('node:fs');
const path = require('node:path');

const skip = process.platform === 'win32' || (typeof process.getuid === 'function' && process.getuid() !== 0)
  ? 'needs a POSIX system running as root' : false;

function b64(remote) {
  return Buffer.from(`client\ndev tun\nproto udp\nremote ${remote} 1194\ncipher AES-128-CBC\n${'#'.repeat(80)}\n`).toString('base64');
}
function row(host, ip, score, cc, name, remote) {
  return [host, ip, score, 10, 5e7, name, cc, 1, 1, 1, 1, 'x', 'op', '', b64(remote)].join(',');
}
const CSV = ['*vpn_servers', '#header',
  row('jp-bad', '203.0.113.1', 999, 'JP', 'Japan', 'fail'),
  row('jp-good', '203.0.113.2', 500, 'JP', 'Japan', 'ok'),
  row('kr-slow', '203.0.113.3', 100, 'KR', 'Korea Republic of', 'silent'),
  '*'].join('\n');

const handlers = {};
const sent = [];
const userData = fs.mkdtempSync(path.join(os.tmpdir(), 'mrmz-main-'));
const electronStub = {
  app: {
    requestSingleInstanceLock: () => true,
    on: () => {},
    whenReady: () => Promise.resolve(),
    getPath: () => userData,
    quit: () => {},
  },
  BrowserWindow: class {
    constructor() { this.webContents = { send: (ch, s) => sent.push(s), setWindowOpenHandler() {}, on() {} }; }
    once() {} on() {} loadFile() {} isDestroyed() { return false; }
    static getAllWindows() { return []; }
  },
  ipcMain: { handle: (ch, fn) => { handlers[ch] = fn; } },
  shell: { openExternal: () => {} },
  Menu: { setApplicationMenu: () => {} },
  net: { fetch: async () => ({ ok: true, text: async () => CSV }) },
};

const origLoad = Module._load;
Module._load = function load(request, ...rest) {
  if (request === 'electron') return electronStub;
  return origLoad.call(this, request, ...rest);
};
process.env.MRMZONE_OPENVPN_PATH = path.join(__dirname, 'fake-openvpn.js');
require('../src/main');

const call = (ch, arg) => handlers[ch]({}, arg);

test('lists countries without leaking configs to the UI', { skip }, async () => {
  await new Promise((r) => setImmediate(r));
  const res = await call('servers:list', true);
  assert.equal(res.error, null);
  assert.deepEqual(res.countries.map((c) => c.code), ['JP', 'KR']);
  assert.equal(res.countries[0].servers[0].config, undefined);
});

test('fails over to the next server in the country', { skip, timeout: 20000 }, async () => {
  const res = await call('vpn:connect', { countryCode: 'JP' });
  assert.deepEqual(res, { ok: true });
  const st = await call('vpn:getStatus');
  assert.equal(st.phase, 'connected');
  assert.equal(st.server.hostName, 'jp-good');
  assert.equal(st.attempt, 2);
  assert.ok(sent.some((s) => s.phase === 'connecting' && s.server.hostName === 'jp-bad'));
});

test('switching country replaces the tunnel, cancel works', { skip, timeout: 20000 }, async () => {
  const pending = call('vpn:connect', { countryCode: 'KR' });
  await new Promise((r) => setTimeout(r, 800));
  assert.equal((await call('vpn:getStatus')).phase, 'connecting');
  await call('vpn:disconnect');
  const res = await pending;
  assert.equal(res.ok, false);
  const st = await call('vpn:getStatus');
  assert.equal(st.phase, 'disconnected');
  assert.equal(st.error, null);
});

test('reconnect then disconnect', { skip, timeout: 20000 }, async () => {
  assert.deepEqual(await call('vpn:connect', { countryCode: 'JP' }), { ok: true });
  assert.deepEqual(await call('vpn:disconnect'), { ok: true });
  assert.equal((await call('vpn:getStatus')).phase, 'disconnected');
});

test('unknown country gives a clear error', { skip }, async () => {
  const res = await call('vpn:connect', { countryCode: 'ZZ' });
  assert.equal(res.ok, false);
  assert.match(res.error, /No free servers/);
});
