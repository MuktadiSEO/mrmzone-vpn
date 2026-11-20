'use strict';

/**
 * VPN Gate (https://www.vpngate.net) is a free, academic public VPN relay
 * project run by the University of Tsukuba, Japan. Its public API returns a
 * CSV list of volunteer OpenVPN servers in many countries.
 *
 * This module only contains pure functions so it can be unit-tested.
 */

const API_URLS = [
  'https://www.vpngate.net/api/iphone/',
  'http://www.vpngate.net/api/iphone/',
];

const COUNTRY_CODE = /^[A-Z]{2}$/;
const INTEGER = /^-?\d+$/;

function toInt(value) {
  const n = Number.parseInt(value, 10);
  return Number.isFinite(n) ? n : 0;
}

function decodeBase64(b64) {
  try {
    const text = Buffer.from(b64.trim(), 'base64').toString('utf8');
    return text.includes('remote ') ? text : '';
  } catch {
    return '';
  }
}

/**
 * Parses one CSV data row. Returns null for rows that are not usable.
 * Columns: HostName,IP,Score,Ping,Speed,CountryLong,CountryShort,
 * NumVpnSessions,Uptime,TotalUsers,TotalTraffic,LogType,Operator,Message,
 * OpenVPN_ConfigData_Base64
 * The free-text columns (country name, operator, message) are located
 * defensively in case they ever contain commas.
 */
function parseRow(line) {
  const fields = line.split(',');
  if (fields.length < 15) return null;

  const configB64 = fields[fields.length - 1];
  if (!configB64 || configB64.length < 100) return null;

  // Country code is the first 2-letter column after CountryLong that is
  // followed by the numeric NumVpnSessions column.
  let ccIndex = -1;
  for (let i = 6; i < fields.length - 1; i += 1) {
    if (COUNTRY_CODE.test(fields[i]) && INTEGER.test(fields[i + 1])) {
      ccIndex = i;
      break;
    }
  }
  if (ccIndex === -1) return null;

  const config = decodeBase64(configB64);
  if (!config) return null;

  const ip = fields[1].trim();
  if (!ip) return null;

  return {
    id: `${fields[0]}-${ip}`,
    hostName: fields[0],
    ip,
    score: toInt(fields[2]),
    ping: toInt(fields[3]),
    speed: toInt(fields[4]), // bits per second
    countryName: fields.slice(5, ccIndex).join(',').trim(),
    countryCode: fields[ccIndex].toUpperCase(),
    sessions: toInt(fields[ccIndex + 1]),
    uptime: toInt(fields[ccIndex + 2]), // milliseconds
    protocol: /^\s*proto\s+tcp/m.test(config) ? 'TCP' : 'UDP',
    config,
  };
}

/** Parses the whole API response into a list of servers. */
function parseServerList(csvText) {
  if (typeof csvText !== 'string') return [];
  const servers = [];
  const seen = new Set();
  for (const raw of csvText.split(/\r?\n/)) {
    const line = raw.trim();
    if (!line || line.startsWith('*') || line.startsWith('#')) continue;
    const server = parseRow(line);
    if (server && !seen.has(server.id)) {
      seen.add(server.id);
      servers.push(server);
    }
  }
  return servers;
}

/** Groups servers by country, best servers first. */
function groupByCountry(servers) {
  const map = new Map();
  for (const s of servers) {
    if (!map.has(s.countryCode)) {
      map.set(s.countryCode, {
        code: s.countryCode,
        name: s.countryName || s.countryCode,
        servers: [],
      });
    }
    map.get(s.countryCode).servers.push(s);
  }
  const countries = [...map.values()];
  for (const c of countries) {
    c.servers.sort((a, b) => b.score - a.score);
    c.bestPing = Math.min(...c.servers.map((s) => (s.ping > 0 ? s.ping : 9999)));
    c.bestSpeed = Math.max(...c.servers.map((s) => s.speed));
  }
  countries.sort((a, b) => a.name.localeCompare(b.name));
  return countries;
}

/**
 * Makes a VPN Gate config work with modern OpenVPN (2.5/2.6+), which no
 * longer falls back to the legacy `cipher` line on its own.
 */
function prepareConfig(config, { disableDco = false } = {}) {
  const lines = config
    .replace(/\r\n?/g, '\n')
    .split('\n')
    .filter((l) => !/^\s*(data-ciphers|data-ciphers-fallback|ncp-ciphers|disable-dco|management)\b/.test(l));

  const cipherLine = lines.find((l) => /^\s*cipher\s+\S+/.test(l));
  const cipher = cipherLine ? cipherLine.trim().split(/\s+/)[1] : 'AES-128-CBC';

  const extra = [
    '',
    '# Added by MRMZone VPN for compatibility with OpenVPN 2.5+',
    `data-ciphers AES-256-GCM:AES-128-GCM:CHACHA20-POLY1305:${cipher}`,
    `data-ciphers-fallback ${cipher}`,
  ];
  if (disableDco) extra.push('disable-dco');
  return `${lines.join('\n').trimEnd()}\n${extra.join('\n')}\n`;
}

/** Parses "OpenVPN 2.6.12 x86_64..." into [2, 6, 12]. */
function parseOpenVpnVersion(text) {
  const m = /OpenVPN\s+(\d+)\.(\d+)(?:\.(\d+))?/.exec(text || '');
  if (!m) return null;
  return [toInt(m[1]), toInt(m[2]), toInt(m[3] || '0')];
}

module.exports = {
  API_URLS,
  parseRow,
  parseServerList,
  groupByCountry,
  prepareConfig,
  parseOpenVpnVersion,
};
