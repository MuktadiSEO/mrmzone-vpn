/// A free OpenVPN server from the VPN Gate academic project.
class VpnServer {
  const VpnServer({
    required this.hostName,
    required this.ip,
    required this.score,
    required this.ping,
    required this.speed,
    required this.countryName,
    required this.countryCode,
    required this.sessions,
    required this.protocol,
    required this.config,
  });

  final String hostName;
  final String ip;
  final int score;
  final int ping; // ms, 0 when unknown
  final int speed; // bits per second
  final String countryName;
  final String countryCode;
  final int sessions;
  final String protocol; // UDP or TCP
  final String config; // .ovpn content

  String get id => '$hostName-$ip';
}

/// All servers of one country, best first.
class Country {
  Country({required this.code, required this.name, required this.servers});

  final String code;
  final String name;
  final List<VpnServer> servers;

  int get bestPing {
    final pings = servers.map((s) => s.ping).where((p) => p > 0);
    return pings.isEmpty ? 0 : pings.reduce((a, b) => a < b ? a : b);
  }

  int get bestSpeed =>
      servers.isEmpty ? 0 : servers.map((s) => s.speed).reduce((a, b) => a > b ? a : b);

  int get bestScore => servers.isEmpty ? 0 : servers.first.score;
}

/// Converts a 2-letter country code into its flag emoji.
String flagEmoji(String code) {
  final cc = code.toUpperCase();
  if (cc.length != 2 || !RegExp(r'^[A-Z]{2}$').hasMatch(cc)) return '🏳️';
  return String.fromCharCodes(cc.codeUnits.map((c) => 0x1F1E6 + c - 0x41));
}

String formatSpeed(int bps) {
  final mbps = bps / 1e6;
  return mbps >= 10 ? '${mbps.round()} Mbps' : '${mbps.toStringAsFixed(1)} Mbps';
}

String formatBytes(int bytes) {
  if (bytes <= 0) return '0 B';
  const units = ['B', 'KB', 'MB', 'GB', 'TB'];
  var v = bytes.toDouble();
  var i = 0;
  while (v >= 1024 && i < units.length - 1) {
    v /= 1024;
    i++;
  }
  return '${v.toStringAsFixed(i == 0 ? 0 : 1)} ${units[i]}';
}

String formatDuration(Duration d) {
  final s = d.isNegative ? 0 : d.inSeconds;
  String two(int n) => n.toString().padLeft(2, '0');
  return '${two(s ~/ 3600)}:${two((s % 3600) ~/ 60)}:${two(s % 60)}';
}

/// 3.0 – 5.0 star rating from the server speed.
double speedRating(int bps) {
  final mbps = bps / 1e6;
  if (mbps >= 100) return 5;
  if (mbps >= 50) return 4.5;
  if (mbps >= 20) return 4;
  if (mbps >= 5) return 3.5;
  return 3;
}
