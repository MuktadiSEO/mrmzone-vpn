#!/usr/bin/env node
'use strict';
// Minimal stand-in for the openvpn binary that speaks the management protocol.
const fs = require('node:fs');
const net = require('node:net');

const args = process.argv.slice(2);
if (args.includes('--version')) {
  process.stdout.write('OpenVPN 2.6.12 x86_64-pc-linux-gnu\n');
  process.exit(0);
}
const i = args.indexOf('--management');
const port = Number(args[i + 2]);
const password = fs.readFileSync(args[i + 3], 'utf8').trim();
const config = fs.readFileSync(args[args.indexOf('--config') + 1], 'utf8');
const mode = /remote (\S+)/.exec(config)[1]; // ok | silent | fail

const server = net.createServer((sock) => {
  sock.setEncoding('utf8');
  sock.write('ENTER PASSWORD:');
  let authed = false;
  let buf = '';
  sock.on('data', (d) => {
    buf += d;
    let n;
    while ((n = buf.indexOf('\n')) !== -1) {
      const line = buf.slice(0, n).trim();
      buf = buf.slice(n + 1);
      if (!authed) {
        if (line !== password) { sock.end('ERROR: bad password\n'); process.exit(3); }
        authed = true;
        sock.write('SUCCESS: password is correct\n');
        continue;
      }
      if (line === 'hold release') {
        sock.write('>STATE:1,CONNECTING,,,,,,\n');
        if (mode === 'ok') {
          setTimeout(() => sock.write('>STATE:2,ASSIGN_IP,,10.8.0.2,,,,\n'), 50);
          setTimeout(() => sock.write('>STATE:3,CONNECTED,SUCCESS,10.8.0.2,203.0.113.5,1194,,\n>BYTECOUNT:2048,1024\n'), 100);
        } else if (mode === 'fail') {
          setTimeout(() => {
            sock.write('>LOG:4,N,TLS Error: TLS key negotiation failed to occur within 60 seconds\n');
            sock.write('>STATE:5,EXITING,tls-error,,,,,\n');
            process.exit(1);
          }, 50);
        }
      } else if (line === 'signal SIGTERM') {
        sock.write('>STATE:9,EXITING,SIGTERM,,,,,\n');
        setTimeout(() => process.exit(0), 20);
      }
    }
  });
});
server.listen(port, '127.0.0.1');
process.on('SIGTERM', () => process.exit(0));
