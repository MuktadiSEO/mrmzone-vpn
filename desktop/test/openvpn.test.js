'use strict';

const test = require('node:test');
const assert = require('node:assert/strict');
const os = require('node:os');
const path = require('node:path');
const fs = require('node:fs');
const { OpenVpnSession } = require('../src/openvpn');

const FAKE = path.join(__dirname, 'fake-openvpn.js');
const skip = process.platform === 'win32' || (typeof process.getuid === 'function' && process.getuid() !== 0)
  ? 'needs a POSIX system running as root (spawns the binary directly)' : false;

function makeSession() {
  const workDir = fs.mkdtempSync(path.join(os.tmpdir(), 'mrmz-'));
  return { s: new OpenVpnSession({ workDir, binary: FAKE }), workDir };
}

test('connects, reports traffic and disconnects cleanly', { skip, timeout: 15000 }, async () => {
  const { s, workDir } = makeSession();
  const states = [];
  let bytes = null;
  s.on('state', (e) => states.push(e.state));
  s.on('bytes', (b) => { bytes = b; });
  const connected = new Promise((resolve) => s.on('state', (e) => e.state === 'CONNECTED' && resolve()));
  const exited = new Promise((resolve) => s.once('exit', resolve));
  await s.start('client\nremote ok 1194\ncipher AES-128-CBC\n');
  await connected;
  assert.equal(s.connected, true);
  assert.deepEqual(bytes, { bytesIn: 2048, bytesOut: 1024 });
  // Secrets must be written privately while running.
  assert.equal(fs.statSync(path.join(workDir, 'management.pw')).mode & 0o077, 0);
  await s.stop();
  const { error } = await exited;
  assert.equal(error, null);
  assert.ok(states.includes('CONNECTING'));
  assert.ok(!fs.existsSync(path.join(workDir, 'management.pw')), 'temp files removed');
});

test('reports a readable error when the server fails', { skip, timeout: 15000 }, async () => {
  const { s } = makeSession();
  const exited = new Promise((resolve) => s.once('exit', resolve));
  await s.start('client\nremote fail 1194\n');
  const { error } = await exited;
  assert.match(error, /TLS Error/);
  assert.equal(s.connected, false);
});

test('can be cancelled while still connecting', { skip, timeout: 15000 }, async () => {
  const { s } = makeSession();
  const exited = new Promise((resolve) => s.once('exit', resolve));
  await s.start('client\nremote silent 1194\n');
  await new Promise((r) => setTimeout(r, 600));
  await s.stop();
  const { error } = await exited;
  assert.equal(error, null);
});
