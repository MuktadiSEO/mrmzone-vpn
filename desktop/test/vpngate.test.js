'use strict';

const test = require('node:test');
const assert = require('node:assert/strict');
const {
  parseRow,
  parseServerList,
  groupByCountry,
  prepareConfig,
  parseOpenVpnVersion,
} = require('../src/vpngate');

const CONFIG = [
  'client',
  'dev tun',
  'proto udp',
  'remote 203.0.113.10 1194',
  'cipher AES-128-CBC',
  'auth SHA1',
  '<ca>',
  '-----BEGIN CERTIFICATE-----',
  'MIIBfakefakefakefakefakefakefakefakefakefakefakefakefakefakefakefake',
  '-----END CERTIFICATE-----',
  '</ca>',
].join('\r\n');
const B64 = Buffer.from(CONFIG).toString('base64');

function row(host, ip, score, cc, name, opts = {}) {
  return [
    host, ip, score, opts.ping ?? 20, opts.speed ?? 50000000, name, cc,
    12, 3600000, 1000, 999999, '2weeks', opts.operator ?? 'op', '', B64,
  ].join(',');
}

const CSV = [
  '*vpn_servers',
  '#HostName,IP,Score,Ping,Speed,CountryLong,CountryShort,NumVpnSessions,Uptime,TotalUsers,TotalTraffic,LogType,Operator,Message,OpenVPN_ConfigData_Base64',
  row('jp1', '203.0.113.10', 100, 'JP', 'Japan'),
  row('jp2', '203.0.113.11', 900, 'JP', 'Japan', { ping: 5 }),
  row('kr1', '203.0.113.12', 500, 'KR', 'Korea Republic of'),
  row('us1', '203.0.113.13', 300, 'US', 'United States', { operator: "Bob's, server" }),
  row('bad', '203.0.113.14', 1, 'XX', 'Broken').replace(B64, 'short'),
  row('jp2', '203.0.113.11', 900, 'JP', 'Japan'), // duplicate
  '*',
  '',
].join('\r\n');

test('parses a valid row', () => {
  const s = parseRow(row('jp1', '203.0.113.10', 100, 'JP', 'Japan'));
  assert.equal(s.hostName, 'jp1');
  assert.equal(s.countryCode, 'JP');
  assert.equal(s.countryName, 'Japan');
  assert.equal(s.score, 100);
  assert.equal(s.protocol, 'UDP');
  assert.ok(s.config.includes('remote 203.0.113.10 1194'));
});

test('handles commas in free-text columns', () => {
  const s = parseRow(row('x', '203.0.113.20', 1, 'KR', 'Korea, Republic of', { operator: 'a,b,c' }));
  assert.equal(s.countryCode, 'KR');
  assert.equal(s.countryName, 'Korea, Republic of');
});

test('rejects broken rows', () => {
  assert.equal(parseRow('a,b,c'), null);
  assert.equal(parseRow(''), null);
});

test('parses the full list, skipping headers, bad rows and duplicates', () => {
  const list = parseServerList(CSV);
  assert.equal(list.length, 4);
  assert.deepEqual(parseServerList(undefined), []);
  assert.deepEqual(parseServerList('<html>blocked</html>'), []);
});

test('groups by country with best server first', () => {
  const countries = groupByCountry(parseServerList(CSV));
  assert.deepEqual(countries.map((c) => c.code), ['JP', 'KR', 'US']);
  const jp = countries[0];
  assert.equal(jp.servers.length, 2);
  assert.equal(jp.servers[0].hostName, 'jp2');
  assert.equal(jp.bestPing, 5);
});

test('prepares config for modern OpenVPN', () => {
  const out = prepareConfig(CONFIG + '\r\ndata-ciphers BF-CBC\r\n', { disableDco: true });
  assert.ok(!out.includes('\r'));
  assert.ok(out.includes('data-ciphers AES-256-GCM:AES-128-GCM:CHACHA20-POLY1305:AES-128-CBC'));
  assert.ok(out.includes('data-ciphers-fallback AES-128-CBC'));
  assert.ok(out.includes('disable-dco'));
  assert.ok(!out.includes('data-ciphers BF-CBC'));
  assert.ok(!prepareConfig(CONFIG).includes('disable-dco'));
});

test('parses OpenVPN version', () => {
  assert.deepEqual(parseOpenVpnVersion('OpenVPN 2.6.12 x86_64-w64-mingw32'), [2, 6, 12]);
  assert.deepEqual(parseOpenVpnVersion('OpenVPN 2.5 [git]'), [2, 5, 0]);
  assert.equal(parseOpenVpnVersion('nope'), null);
});
