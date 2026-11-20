'use strict';

const { app, BrowserWindow, ipcMain, shell, net, Menu } = require('electron');
const fs = require('node:fs');
const path = require('node:path');
const { API_URLS, parseServerList, groupByCountry } = require('./vpngate');
const { OpenVpnSession, findOpenVpn } = require('./openvpn');

const MAX_ATTEMPTS = 3;
const CACHE_MAX_AGE_MS = 6 * 60 * 60 * 1000;
const ALLOWED_EXTERNAL = new Set([
  'https://openvpn.net/community-downloads/',
  'https://www.vpngate.net/en/',
  'https://formulae.brew.sh/formula/openvpn',
]);

let win = null;
let servers = [];
let session = null;
let connectJob = 0;
let quitting = false;

const status = {
  phase: 'disconnected', // disconnected | connecting | connected | disconnecting
  server: null,
  detail: '',
  bytesIn: 0,
  bytesOut: 0,
  connectedAt: null,
  error: null,
  attempt: 0,
};

function publicServer(s) {
  if (!s) return null;
  const { config, ...rest } = s;
  return rest;
}

function setStatus(patch) {
  Object.assign(status, patch);
  if (win && !win.isDestroyed()) win.webContents.send('vpn:status', { ...status });
}

function cachePath() {
  return path.join(app.getPath('userData'), 'servers-cache.json');
}

function readCache() {
  try {
    const data = JSON.parse(fs.readFileSync(cachePath(), 'utf8'));
    if (Array.isArray(data.servers)) return data;
  } catch { /* no cache yet */ }
  return null;
}

async function fetchText(url, timeoutMs = 20000) {
  const res = await net.fetch(url, { signal: AbortSignal.timeout(timeoutMs), cache: 'no-store' });
  if (!res.ok) throw new Error(`HTTP ${res.status}`);
  return res.text();
}

async function loadServers(force) {
  const cache = readCache();
  if (!force && cache && Date.now() - cache.updatedAt < CACHE_MAX_AGE_MS && cache.servers.length) {
    servers = cache.servers;
    return { updatedAt: cache.updatedAt, fromCache: true, error: null };
  }
  let lastError = null;
  for (const url of API_URLS) {
    try {
      const list = parseServerList(await fetchText(url));
      if (list.length) {
        servers = list;
        const updatedAt = Date.now();
        try {
          fs.mkdirSync(app.getPath('userData'), { recursive: true });
          fs.writeFileSync(cachePath(), JSON.stringify({ updatedAt, servers: list }));
        } catch { /* cache is optional */ }
        return { updatedAt, fromCache: false, error: null };
      }
      lastError = 'The server list was empty.';
    } catch (err) {
      lastError = err.message;
    }
  }
  if (cache && cache.servers.length) {
    servers = cache.servers;
    return { updatedAt: cache.updatedAt, fromCache: true, error: `Showing saved list (${lastError})` };
  }
  servers = [];
  return { updatedAt: null, fromCache: false, error: `Could not download the free server list: ${lastError}` };
}

function countriesForRenderer() {
  return groupByCountry(servers).map((c) => ({ ...c, servers: c.servers.map(publicServer) }));
}

function runSession(server, job) {
  return new Promise((resolve) => {
    const s = new OpenVpnSession({ workDir: path.join(app.getPath('userData'), 'run'), binary: findOpenVpn() });
    session = s;
    let settled = false;
    const done = (ok, error) => {
      if (!settled) {
        settled = true;
        resolve({ ok, error });
      }
    };
    s.on('state', ({ state, detail }) => {
      if (job !== connectJob) return;
      if (state === 'CONNECTED' && s.connected) {
        setStatus({ phase: 'connected', detail: 'Connected', connectedAt: Date.now(), error: null });
        done(true);
      } else if (state === 'RECONNECTING' && status.phase === 'connected') {
        setStatus({ phase: 'connecting', detail: 'Reconnecting…', connectedAt: null });
      } else if (state !== 'EXITING' && status.phase === 'connecting') {
        setStatus({ detail: friendlyState(state, detail) });
      }
    });
    s.on('bytes', ({ bytesIn, bytesOut }) => {
      if (job === connectJob) setStatus({ bytesIn, bytesOut });
    });
    s.on('exit', ({ error }) => {
      if (session === s) session = null;
      if (settled && job === connectJob && status.phase !== 'disconnecting') {
        // Dropped after it was connected.
        setStatus({ phase: 'disconnected', connectedAt: null, detail: '', error: error || 'The connection was closed.' });
      }
      done(false, error || 'Connection failed.');
    });
    s.start(server.config).catch((err) => {
      if (session === s) session = null;
      done(false, err.message);
    });
  });
}

function friendlyState(state, detail) {
  const map = {
    STARTING: 'Starting secure tunnel…',
    CONNECTING: 'Contacting server…',
    RESOLVE: 'Looking up server…',
    TCP_CONNECT: 'Opening connection…',
    WAIT: 'Waiting for server…',
    AUTH: 'Authenticating…',
    GET_CONFIG: 'Getting settings…',
    ASSIGN_IP: 'Assigning IP address…',
    ADD_ROUTES: 'Routing traffic…',
    RECONNECTING: 'Retrying…',
  };
  return map[state] || detail || state;
}

async function connect({ countryCode, serverId }) {
  if (status.phase === 'connecting' || status.phase === 'disconnecting') {
    return { ok: false, error: 'Please wait…' };
  }
  if (!findOpenVpn()) {
    return { ok: false, error: 'OPENVPN_MISSING' };
  }
  if (!servers.length) await loadServers(false);

  let candidates;
  if (serverId) {
    candidates = servers.filter((s) => s.id === serverId);
  } else {
    candidates = servers.filter((s) => s.countryCode === countryCode).sort((a, b) => b.score - a.score);
  }
  if (!candidates.length) return { ok: false, error: 'No free servers are available for this country right now.' };

  // Switching servers: stop the current tunnel first.
  if (session) await disconnect({ keepStatus: true });

  const job = ++connectJob;
  let lastError = null;
  const attempts = candidates.slice(0, serverId ? 1 : MAX_ATTEMPTS);
  for (let i = 0; i < attempts.length; i += 1) {
    if (job !== connectJob) return { ok: false, error: null }; // cancelled
    const server = attempts[i];
    setStatus({
      phase: 'connecting', server: publicServer(server), detail: 'Starting secure tunnel…',
      bytesIn: 0, bytesOut: 0, connectedAt: null, error: null, attempt: i + 1,
    });
    const result = await runSession(server, job);
    if (result.ok) return { ok: true };
    lastError = result.error;
    // Problems on this computer will not be fixed by trying another server.
    if (/Administrator|permission was cancelled|Could not start OpenVPN|Could not talk to OpenVPN/i.test(lastError || '')) break;
  }
  if (job === connectJob) {
    setStatus({ phase: 'disconnected', connectedAt: null, detail: '', error: lastError || 'Could not connect.' });
  }
  return { ok: false, error: lastError };
}

async function disconnect({ keepStatus = false } = {}) {
  connectJob += 1; // cancels any connect loop in progress
  const s = session;
  if (!keepStatus) setStatus({ phase: 'disconnecting', detail: 'Disconnecting…' });
  if (s) await s.stop();
  session = null;
  if (!keepStatus) {
    setStatus({ phase: 'disconnected', detail: '', connectedAt: null, bytesIn: 0, bytesOut: 0, error: null });
  }
  return { ok: true };
}

async function publicIp() {
  try {
    const data = JSON.parse(await fetchText('https://ipwho.is/', 10000));
    if (data && data.success !== false && data.ip) {
      return { ip: data.ip, country: data.country || '', countryCode: data.country_code || '' };
    }
  } catch { /* try fallback */ }
  try {
    const data = JSON.parse(await fetchText('https://api.ipify.org?format=json', 10000));
    return { ip: data.ip, country: '', countryCode: '' };
  } catch {
    return { ip: null, country: '', countryCode: '' };
  }
}

function createWindow() {
  win = new BrowserWindow({
    width: 1180,
    height: 760,
    minWidth: 900,
    minHeight: 600,
    backgroundColor: '#EAEDED',
    title: 'MRMZone VPN',
    icon: path.join(__dirname, '..', 'build', 'icon.png'),
    show: false,
    webPreferences: {
      preload: path.join(__dirname, 'preload.js'),
      contextIsolation: true,
      nodeIntegration: false,
      sandbox: true,
    },
  });
  win.once('ready-to-show', () => win.show());
  win.webContents.setWindowOpenHandler(() => ({ action: 'deny' }));
  win.webContents.on('will-navigate', (e) => e.preventDefault());
  win.loadFile(path.join(__dirname, 'renderer', 'index.html'));
  win.on('closed', () => { win = null; });
}

const gotLock = app.requestSingleInstanceLock();
if (!gotLock) {
  app.quit();
} else {
  app.on('second-instance', () => {
    if (win) {
      if (win.isMinimized()) win.restore();
      win.focus();
    }
  });

  app.whenReady().then(() => {
    Menu.setApplicationMenu(null);

    ipcMain.handle('servers:list', async (_e, force) => {
      const meta = await loadServers(!!force);
      return { ...meta, countries: countriesForRenderer() };
    });
    ipcMain.handle('vpn:connect', (_e, args) => connect(args || {}));
    ipcMain.handle('vpn:disconnect', () => disconnect());
    ipcMain.handle('vpn:getStatus', () => ({ ...status }));
    ipcMain.handle('net:publicIp', () => publicIp());
    ipcMain.handle('openvpn:check', () => ({ installed: !!findOpenVpn(), platform: process.platform }));
    ipcMain.handle('app:openExternal', (_e, url) => {
      if (ALLOWED_EXTERNAL.has(url)) shell.openExternal(url);
    });

    createWindow();
    app.on('activate', () => {
      if (BrowserWindow.getAllWindows().length === 0) createWindow();
    });
  });

  // Always take the tunnel down before quitting.
  app.on('before-quit', (e) => {
    if (quitting || !session) return;
    e.preventDefault();
    quitting = true;
    disconnect().finally(() => app.quit());
  });

  app.on('window-all-closed', () => {
    app.quit();
  });
}
