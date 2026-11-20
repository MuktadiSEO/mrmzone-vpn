'use strict';

const { EventEmitter } = require('node:events');
const { spawn, execFile } = require('node:child_process');
const crypto = require('node:crypto');
const fs = require('node:fs');
const net = require('node:net');
const path = require('node:path');
const { prepareConfig, parseOpenVpnVersion } = require('./vpngate');

const CONNECT_TIMEOUT_MS = 30000;
const MGMT_CONNECT_TIMEOUT_MS = 60000; // includes time for the password prompt
const DISCONNECT_TIMEOUT_MS = 6000;

function candidatePaths() {
  if (process.platform === 'win32') {
    const roots = [process.env.ProgramFiles, process.env['ProgramFiles(x86)'], process.env.ProgramW6432,
      'C:\\Program Files', 'C:\\Program Files (x86)'].filter(Boolean);
    return [...new Set(roots)].map((r) => path.join(r, 'OpenVPN', 'bin', 'openvpn.exe'));
  }
  if (process.platform === 'darwin') {
    return ['/opt/homebrew/sbin/openvpn', '/usr/local/sbin/openvpn', '/usr/local/opt/openvpn/sbin/openvpn',
      '/opt/local/sbin/openvpn', '/Applications/Tunnelblick.app/Contents/Resources/openvpn/default'];
  }
  return ['/usr/sbin/openvpn', '/usr/bin/openvpn', '/usr/local/sbin/openvpn', '/usr/local/bin/openvpn', '/snap/bin/openvpn'];
}

function findOpenVpn() {
  const override = process.env.MRMZONE_OPENVPN_PATH;
  for (const p of override ? [override] : candidatePaths()) {
    try {
      fs.accessSync(p, fs.constants.X_OK);
      return p;
    } catch { /* keep looking */ }
  }
  return null;
}

function getVersion(binary) {
  return new Promise((resolve) => {
    execFile(binary, ['--version'], { timeout: 5000, windowsHide: true }, (_err, stdout, stderr) => {
      resolve(parseOpenVpnVersion(`${stdout || ''}${stderr || ''}`));
    });
  });
}

function freePort() {
  return new Promise((resolve, reject) => {
    const srv = net.createServer();
    srv.unref();
    srv.on('error', reject);
    srv.listen(0, '127.0.0.1', () => {
      const { port } = srv.address();
      srv.close(() => resolve(port));
    });
  });
}

function shellQuote(s) {
  return `'${String(s).replace(/'/g, "'\\''")}'`;
}

function isElevated() {
  if (process.platform === 'win32') {
    return new Promise((resolve) => {
      execFile('net', ['session'], { windowsHide: true }, (err) => resolve(!err));
    });
  }
  return Promise.resolve(typeof process.getuid === 'function' && process.getuid() === 0);
}

/**
 * Runs one OpenVPN connection and reports its state through events:
 *  - 'state'  { state, detail, localIp, remoteIp }
 *  - 'bytes'  { bytesIn, bytesOut }
 *  - 'log'    string
 *  - 'exit'   { error?: string }   (always emitted exactly once)
 */
class OpenVpnSession extends EventEmitter {
  constructor({ workDir, binary }) {
    super();
    this.workDir = workDir;
    this.binary = binary;
    this.proc = null;
    this.socket = null;
    this.connected = false;
    this.exited = false;
    this.stopping = false;
    this.lastError = null;
    this.timers = [];
    this.buffer = '';
    this.files = [];
  }

  async start(serverConfig) {
    fs.mkdirSync(this.workDir, { recursive: true });
    const version = await getVersion(this.binary);
    const disableDco = !!version && (version[0] > 2 || (version[0] === 2 && version[1] >= 6));

    const port = await freePort();
    const password = crypto.randomBytes(18).toString('hex');
    const configPath = path.join(this.workDir, 'connection.ovpn');
    const pwPath = path.join(this.workDir, 'management.pw');
    fs.writeFileSync(configPath, prepareConfig(serverConfig, { disableDco }), { mode: 0o600 });
    fs.writeFileSync(pwPath, `${password}\n`, { mode: 0o600 });
    this.files = [configPath, pwPath];
    this.password = password;
    this.port = port;

    const args = [
      '--config', configPath,
      '--management', '127.0.0.1', String(port), pwPath,
      '--management-hold',
      '--management-query-passwords',
      '--auth-nocache',
      '--connect-retry-max', '2',
      '--verb', '3',
    ];

    const elevated = await isElevated();
    if (process.platform === 'win32') {
      if (!elevated) {
        throw new Error('Administrator rights are required. Close the app and run it with "Run as administrator".');
      }
      this.proc = spawn(this.binary, args, { windowsHide: true });
    } else if (process.platform === 'darwin' && !elevated) {
      // Ask for the admin password once via the native macOS dialog and run
      // OpenVPN as a background daemon; it is controlled through management.
      const cmd = [this.binary, ...args, '--daemon', 'mrmzone-vpn'].map(shellQuote).join(' ');
      const script = `do shell script ${JSON.stringify(cmd)} with administrator privileges`;
      this.proc = spawn('osascript', ['-e', script]);
      this.daemonized = true;
    } else if (!elevated) {
      this.proc = spawn('pkexec', [this.binary, ...args]);
    } else {
      this.proc = spawn(this.binary, args);
    }

    this.proc.on('error', (err) => this.finish(`Could not start OpenVPN: ${err.message}`));
    this.proc.stdout?.on('data', (d) => this.emit('log', d.toString()));
    this.proc.stderr?.on('data', (d) => this.emit('log', d.toString()));
    this.proc.on('exit', (code) => {
      if (this.daemonized) {
        // osascript launcher: 0 means the daemon started (management follows),
        // 1 means the user cancelled the password dialog.
        if (code !== 0 && !this.socket) {
          this.finish(code === 1 ? 'Administrator permission was cancelled.' : `Could not start OpenVPN (code ${code}).`);
        }
        return;
      }
      if (process.platform === 'linux' && (code === 126 || code === 127) && !this.socket && !this.connected) {
        this.finish('Administrator permission was cancelled.');
        return;
      }
      this.finish(this.lastError || (this.stopping ? null : `OpenVPN stopped (code ${code}).`));
    });

    this.emit('state', { state: 'STARTING', detail: 'Starting OpenVPN' });
    this.connectManagement(Date.now());
    this.timers.push(setTimeout(() => {
      if (!this.connected && !this.exited) {
        this.lastError = 'The server did not respond in time.';
        this.stop();
      }
    }, CONNECT_TIMEOUT_MS + MGMT_CONNECT_TIMEOUT_MS));
  }

  connectManagement(startedAt) {
    if (this.exited || this.stopping) return;
    const socket = net.connect({ host: '127.0.0.1', port: this.port });
    socket.setEncoding('utf8');
    socket.once('connect', () => {
      this.socket = socket;
      // Start the connection timeout once OpenVPN is actually running.
      this.timers.push(setTimeout(() => {
        if (!this.connected && !this.exited) {
          this.lastError = 'The server did not respond in time.';
          this.stop();
        }
      }, CONNECT_TIMEOUT_MS));
    });
    socket.on('data', (chunk) => this.onData(chunk));
    socket.on('error', () => { /* handled by close */ });
    socket.on('close', () => {
      if (this.socket === socket) {
        this.socket = null;
        // With a daemon there is no child process to watch: the closed
        // management socket means OpenVPN is gone.
        if (this.daemonized) {
          this.finish(this.stopping ? null : (this.lastError || 'OpenVPN stopped.'));
        } else if (!this.exited && this.stopping) {
          this.killProcess();
        }
        return;
      }
      if (!this.socket && !this.exited && Date.now() - startedAt < MGMT_CONNECT_TIMEOUT_MS) {
        this.timers.push(setTimeout(() => this.connectManagement(startedAt), 400));
      } else if (!this.socket && !this.exited) {
        this.finish('Could not talk to OpenVPN.');
        this.killProcess();
      }
    });
  }

  send(cmd) {
    if (this.socket && !this.socket.destroyed) this.socket.write(`${cmd}\n`);
  }

  onData(chunk) {
    this.buffer += chunk;
    let idx;
    while ((idx = this.buffer.indexOf('\n')) !== -1) {
      const line = this.buffer.slice(0, idx).replace(/\r$/, '');
      this.buffer = this.buffer.slice(idx + 1);
      this.onLine(line);
    }
    // The password prompt has no trailing newline.
    if (this.buffer.startsWith('ENTER PASSWORD:')) {
      this.buffer = '';
      this.send(this.password);
      this.send('state on');
      this.send('log on');
      this.send('bytecount 1');
      this.send('hold release');
    }
  }

  onLine(line) {
    if (line.startsWith('>STATE:')) {
      const [, state, detail, localIp, remoteIp] = line.slice(7).split(',');
      if (state === 'CONNECTED') {
        if (detail === 'SUCCESS' || !detail) {
          this.connected = true;
        } else {
          this.lastError = `Connected with errors: ${detail}`;
        }
      }
      if (state === 'EXITING' && detail && !this.stopping) {
        this.lastError = this.lastError || `Disconnected (${detail}).`;
      }
      this.emit('state', { state, detail, localIp, remoteIp });
    } else if (line.startsWith('>BYTECOUNT:')) {
      const [bytesIn, bytesOut] = line.slice(11).split(',').map((n) => Number.parseInt(n, 10) || 0);
      this.emit('bytes', { bytesIn, bytesOut });
    } else if (line.startsWith('>LOG:')) {
      const msg = line.slice(5).split(',').slice(2).join(',');
      this.emit('log', msg);
      if (/AUTH_FAILED|TLS Error|Cannot resolve|Connection refused|No usable data channel cipher|Cannot open TUN|There are no TAP-Windows|All TAP-Windows|Exiting due to fatal error/i.test(msg)) {
        this.lastError = msg.trim();
      }
    } else if (line.startsWith('>FATAL:')) {
      this.lastError = line.slice(7).trim();
    } else if (line.startsWith('>PASSWORD:Need')) {
      // VPN Gate servers need no username/password; cancel cleanly.
      this.lastError = 'This server requires a login. Please choose another server.';
      this.stop();
    } else if (line.startsWith('>HOLD:')) {
      this.send('hold release');
    }
  }

  stop() {
    if (this.exited) return Promise.resolve();
    this.stopping = true;
    return new Promise((resolve) => {
      this.once('exit', () => resolve());
      if (this.socket) {
        this.send('signal SIGTERM');
      } else {
        this.killProcess();
      }
      this.timers.push(setTimeout(() => {
        this.killProcess();
        // Give up waiting; the process is either gone or not ours to kill.
        setTimeout(() => this.finish(this.lastError), 1000);
      }, DISCONNECT_TIMEOUT_MS));
    });
  }

  killProcess() {
    if (this.proc && this.proc.exitCode === null && !this.proc.killed && !this.daemonized) {
      try { this.proc.kill(); } catch { /* ignore */ }
    }
  }

  finish(error) {
    if (this.exited) return;
    this.exited = true;
    for (const t of this.timers) clearTimeout(t);
    this.timers = [];
    if (this.socket) {
      this.socket.destroy();
      this.socket = null;
    }
    for (const f of this.files) {
      try { fs.rmSync(f, { force: true }); } catch { /* ignore */ }
    }
    this.emit('exit', { error: this.stopping && !this.lastError ? null : error || null });
  }
}

module.exports = { OpenVpnSession, findOpenVpn };
