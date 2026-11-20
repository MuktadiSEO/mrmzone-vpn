import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:mrmzone_vpn/models/vpn_server.dart';
import 'package:mrmzone_vpn/services/vpngate_parser.dart';

const _config = 'client\r\ndev tun\r\nproto udp\r\nremote 203.0.113.10 1194\r\ncipher AES-128-CBC\r\n'
    '<ca>\r\n-----BEGIN CERTIFICATE-----\r\nMIIBfakefakefakefakefakefakefakefakefakefake\r\n-----END CERTIFICATE-----\r\n</ca>\r\n';
final _b64 = base64.encode(utf8.encode(_config));

String row(String host, String ip, int score, String cc, String name, {int ping = 20, int speed = 50000000, String op = 'op'}) =>
    [host, ip, score, ping, speed, name, cc, 12, 3600000, 1000, 999999, '2weeks', op, '', _b64].join(',');

void main() {
  final csv = [
    '*vpn_servers',
    '#HostName,IP,Score,Ping,Speed,CountryLong,CountryShort,NumVpnSessions,Uptime,TotalUsers,TotalTraffic,LogType,Operator,Message,OpenVPN_ConfigData_Base64',
    row('jp1', '203.0.113.10', 100, 'JP', 'Japan'),
    row('jp2', '203.0.113.11', 900, 'JP', 'Japan', ping: 5),
    row('kr1', '203.0.113.12', 500, 'KR', 'Korea, Republic of', op: "Bob's, server"),
    row('us1', '203.0.113.13', 300, 'US', 'United States'),
    row('bad', '203.0.113.14', 1, 'XX', 'Broken').replaceAll(_b64, 'short'),
    row('jp2', '203.0.113.11', 900, 'JP', 'Japan'),
    '*',
  ].join('\r\n');

  test('parses rows, skipping bad and duplicate ones', () {
    final list = parseServerList(csv);
    expect(list.length, 4);
    final kr = list.firstWhere((s) => s.countryCode == 'KR');
    expect(kr.countryName, 'Korea, Republic of');
    expect(kr.protocol, 'UDP');
    expect(kr.config, contains('remote 203.0.113.10 1194'));
  });

  test('handles garbage input', () {
    expect(parseServerList(''), isEmpty);
    expect(parseServerList('<html>blocked</html>'), isEmpty);
    expect(parseRow('a,b,c'), isNull);
  });

  test('groups by country, best first', () {
    final countries = groupByCountry(parseServerList(csv));
    expect(countries.map((c) => c.code).toList(), ['JP', 'KR', 'US']);
    expect(countries.first.servers.first.hostName, 'jp2');
    expect(countries.first.bestPing, 5);
  });

  test('prepares config for OpenVPN 2.6+', () {
    final out = prepareConfig('$_config\r\ndata-ciphers BF-CBC\r\n');
    expect(out.contains('\r'), isFalse);
    expect(out, contains('data-ciphers AES-256-GCM:AES-128-GCM:CHACHA20-POLY1305:AES-128-CBC'));
    expect(out, contains('data-ciphers-fallback AES-128-CBC'));
    expect(out.contains('data-ciphers BF-CBC'), isFalse);
  });

  test('formatting helpers', () {
    expect(flagEmoji('jp'), '🇯🇵');
    expect(flagEmoji('?'), '🏳️');
    expect(formatBytes(0), '0 B');
    expect(formatBytes(1536), '1.5 KB');
    expect(formatSpeed(123000000), '123 Mbps');
    expect(formatDuration(const Duration(hours: 1, minutes: 2, seconds: 3)), '01:02:03');
    expect(speedRating(200e6.toInt()), 5);
    expect(speedRating(1000), 3);
  });
}
