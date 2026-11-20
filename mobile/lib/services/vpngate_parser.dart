import 'dart:convert';

import '../models/vpn_server.dart';

final _countryCode = RegExp(r'^[A-Z]{2}$');
final _integer = RegExp(r'^-?\d+$');
final _tcp = RegExp(r'^\s*proto\s+tcp', multiLine: true);

int _toInt(String v) => int.tryParse(v.trim()) ?? 0;

/// Parses one CSV row of the VPN Gate API. Returns null when not usable.
///
/// Columns: HostName,IP,Score,Ping,Speed,CountryLong,CountryShort,
/// NumVpnSessions,Uptime,TotalUsers,TotalTraffic,LogType,Operator,Message,
/// OpenVPN_ConfigData_Base64. Free-text columns may contain commas, so the
/// country code is located by shape.
VpnServer? parseRow(String line) {
  final f = line.split(',');
  if (f.length < 15) return null;
  final b64 = f.last.trim();
  if (b64.length < 100) return null;

  var cc = -1;
  for (var i = 6; i < f.length - 1; i++) {
    if (_countryCode.hasMatch(f[i]) && _integer.hasMatch(f[i + 1])) {
      cc = i;
      break;
    }
  }
  if (cc == -1) return null;

  String config;
  try {
    config = utf8.decode(base64.decode(base64.normalize(b64)), allowMalformed: true);
  } catch (_) {
    return null;
  }
  if (!config.contains('remote ')) return null;

  final ip = f[1].trim();
  if (ip.isEmpty) return null;

  return VpnServer(
    hostName: f[0].trim(),
    ip: ip,
    score: _toInt(f[2]),
    ping: _toInt(f[3]),
    speed: _toInt(f[4]),
    countryName: f.sublist(5, cc).join(',').trim(),
    countryCode: f[cc].toUpperCase(),
    sessions: _toInt(f[cc + 1]),
    protocol: _tcp.hasMatch(config) ? 'TCP' : 'UDP',
    config: config,
  );
}

/// Parses the whole API response.
List<VpnServer> parseServerList(String csv) {
  final servers = <VpnServer>[];
  final seen = <String>{};
  for (final raw in const LineSplitter().convert(csv)) {
    final line = raw.trim();
    if (line.isEmpty || line.startsWith('*') || line.startsWith('#')) continue;
    final s = parseRow(line);
    if (s != null && seen.add(s.id)) servers.add(s);
  }
  return servers;
}

/// Groups servers by country (A–Z), best server first in each.
List<Country> groupByCountry(List<VpnServer> servers) {
  final map = <String, Country>{};
  for (final s in servers) {
    map
        .putIfAbsent(
          s.countryCode,
          () => Country(
            code: s.countryCode,
            name: s.countryName.isEmpty ? s.countryCode : s.countryName,
            servers: [],
          ),
        )
        .servers
        .add(s);
  }
  final list = map.values.toList();
  for (final c in list) {
    c.servers.sort((a, b) => b.score.compareTo(a.score));
  }
  list.sort((a, b) => a.name.toLowerCase().compareTo(b.name.toLowerCase()));
  return list;
}

/// Normalises line endings and asks OpenVPN 2.6+ to accept the server's
/// legacy cipher (VPN Gate servers do not negotiate ciphers).
String prepareConfig(String config) {
  final lines = config
      .replaceAll('\r\n', '\n')
      .replaceAll('\r', '\n')
      .split('\n')
      .where((l) => !RegExp(r'^\s*(data-ciphers|data-ciphers-fallback|ncp-ciphers)\b').hasMatch(l))
      .toList();
  final cipherLine = lines.firstWhere(
    (l) => RegExp(r'^\s*cipher\s+\S+').hasMatch(l),
    orElse: () => '',
  );
  final cipher = cipherLine.isEmpty ? 'AES-128-CBC' : cipherLine.trim().split(RegExp(r'\s+'))[1];
  return '${lines.join('\n').trimRight()}\n'
      'data-ciphers AES-256-GCM:AES-128-GCM:CHACHA20-POLY1305:$cipher\n'
      'data-ciphers-fallback $cipher\n';
}
