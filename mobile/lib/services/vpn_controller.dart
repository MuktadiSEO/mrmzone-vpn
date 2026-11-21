import 'dart:async';
import 'dart:convert';
import 'dart:io' show Platform;

import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:http/http.dart' as http;
import 'package:openvpn_flutter/openvpn_flutter.dart';
import 'package:permission_handler/permission_handler.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../models/vpn_server.dart';
import 'vpngate_parser.dart';

enum VpnPhase { disconnected, connecting, connected, disconnecting }

class PublicIp {
  const PublicIp(this.ip, this.country, this.countryCode);
  final String? ip;
  final String country;
  final String countryCode;
}

List<VpnServer> _parseInBackground(String csv) => parseServerList(csv);

/// Turns raw OpenVPN messages into something a person can act on.
String friendlyError(String? raw) {
  final msg = raw?.trim() ?? '';
  final rules = <RegExp, String>{
    RegExp(r'connect-retry|Connection reset|TLS key negotiation|TLS Error|Bad encapsulated|timed? ?out', caseSensitive: false):
        'The server did not answer. It may be busy or blocked on your network. Try another server.',
    RegExp(r'resolve', caseSensitive: false): 'Could not find the server. Check your internet connection.',
    RegExp(r'refused', caseSensitive: false): 'The server refused the connection. Try another server.',
    RegExp(r'AUTH_FAILED', caseSensitive: false): 'The server refused the login (it may be full). Try another server.',
    RegExp(r'cipher', caseSensitive: false): 'This server uses an unsupported encryption. Try another server.',
  };
  for (final e in rules.entries) {
    if (e.key.hasMatch(msg)) return e.value;
  }
  return msg.isEmpty ? 'Connection failed. Try another country.' : 'Connection failed: $msg';
}

/// App state: the free server list and the VPN connection.
class VpnController extends ChangeNotifier {
  VpnController({OpenVPN? engine, http.Client? client})
      : _client = client ?? http.Client(),
        _injectedEngine = engine;

  /// Official API first, then a copy refreshed every 30 minutes on GitHub
  /// (.github/workflows/server-list.yml) for networks that block vpngate.net.
  static const apiUrls = [
    'https://www.vpngate.net/api/iphone/',
    'https://raw.githubusercontent.com/MuktadiSEO/mrmzone-vpn/server-list/servers.csv',
    'http://www.vpngate.net/api/iphone/',
    'https://cdn.jsdelivr.net/gh/MuktadiSEO/mrmzone-vpn@server-list/servers.csv',
  ];
  static const _cacheKey = 'servers_csv';
  static const _cacheTimeKey = 'servers_time';
  static const _favoritesKey = 'favorites';
  static const _lastCountryKey = 'last_country';
  static const maxAttempts = 3;
  static const connectTimeout = Duration(seconds: 30);
  static const cacheMaxAge = Duration(hours: 6);

  final http.Client _client;
  final OpenVPN? _injectedEngine;
  late final OpenVPN _engine;
  SharedPreferences? _prefs;
  bool _engineReady = false;
  StreamSubscription<VPNStage>? _stageSub;
  StreamSubscription<VpnStatus>? _statusSub;
  bool _disposed = false;

  // ---- server list ----
  List<Country> countries = [];
  bool loadingServers = false;
  String? serverError;
  DateTime? serversUpdatedAt;
  bool fromCache = false;

  // ---- connection ----
  VpnPhase phase = VpnPhase.disconnected;
  VpnServer? server;
  String detail = '';
  String? error;
  int attempt = 0;
  DateTime? connectedAt;
  int bytesIn = 0;
  int bytesOut = 0;
  int _job = 0;
  bool _userStopping = false;

  // ---- misc ----
  Set<String> favorites = {};
  String? lastCountry;
  PublicIp? publicIp;
  bool checkingIp = false;

  Future<void> init() async {
    try {
      _prefs = await SharedPreferences.getInstance();
      favorites = (_prefs!.getStringList(_favoritesKey) ?? const []).toSet();
      lastCountry = _prefs!.getString(_lastCountryKey);
    } catch (_) {
      // Preferences are a convenience only.
    }
    _engine = _injectedEngine ?? OpenVPN();
    _stageSub = _engine.stageStream.listen(_onStage);
    _statusSub = _engine.statusStream.listen(_onStatus);
    try {
      await _engine.initialize(
        groupIdentifier: 'group.com.mrmzone.vpn',
        providerBundleIdentifier: 'com.mrmzone.vpn.VPNExtension',
        localizedDescription: 'MRMZone VPN',
        lastStage: _onStage,
        lastStatus: _onStatus,
      );
      _engineReady = true;
    } catch (e) {
      error = 'The VPN engine could not start on this device: $e';
    }
    if (!kIsWeb && Platform.isAndroid) {
      // Android 13+: allow the connection notification. Optional.
      unawaited(Permission.notification.request().then((_) {}, onError: (_) {}));
    }
    _notify();
    unawaited(refreshIp());
    await loadServers();
  }

  void _notify() {
    if (!_disposed) notifyListeners();
  }

  // ======================= servers =======================

  Future<void> loadServers({bool force = false}) async {
    if (loadingServers) return;
    loadingServers = true;
    serverError = null;
    _notify();
    try {
      final cachedCsv = _prefs?.getString(_cacheKey);
      final cachedTime = _prefs?.getInt(_cacheTimeKey);
      final cacheFresh = cachedCsv != null &&
          cachedTime != null &&
          DateTime.now().difference(DateTime.fromMillisecondsSinceEpoch(cachedTime)) < cacheMaxAge;

      if (!force && cacheFresh) {
        final list = await compute(_parseInBackground, cachedCsv);
        if (list.isNotEmpty) {
          _setServers(list, DateTime.fromMillisecondsSinceEpoch(cachedTime), true);
          return;
        }
      }

      String? lastError;
      for (final url in apiUrls) {
        try {
          final res = await _client.get(Uri.parse(url)).timeout(const Duration(seconds: 15));
          if (res.statusCode != 200) {
            lastError = 'HTTP ${res.statusCode}';
            continue;
          }
          final csv = utf8.decode(res.bodyBytes, allowMalformed: true);
          final list = await compute(_parseInBackground, csv);
          if (list.isEmpty) {
            lastError = 'empty list';
            continue;
          }
          final now = DateTime.now();
          try {
            await _prefs?.setString(_cacheKey, csv);
            await _prefs?.setInt(_cacheTimeKey, now.millisecondsSinceEpoch);
          } catch (_) {}
          _setServers(list, now, false);
          return;
        } catch (e) {
          lastError = _shortReason(e);
        }
      }

      if (cachedCsv != null) {
        final list = await compute(_parseInBackground, cachedCsv);
        if (list.isNotEmpty) {
          _setServers(list, cachedTime == null ? null : DateTime.fromMillisecondsSinceEpoch(cachedTime), true);
          serverError = 'Showing the saved server list (could not refresh: $lastError).';
          return;
        }
      }
      if (countries.isEmpty) {
        serverError = 'Could not download the free server list ($lastError). '
            'Check your internet connection and try again.';
      }
    } finally {
      loadingServers = false;
      _notify();
    }
  }

  static String _shortReason(Object e) {
    if (e is TimeoutException) return 'timed out';
    final text = e.toString().split('\n').first;
    if (RegExp(r'Failed host lookup|SocketException|Connection (refused|reset|closed)|Network is unreachable', caseSensitive: false)
        .hasMatch(text)) {
      return 'server unreachable';
    }
    if (RegExp(r'Handshake|CERTIFICATE', caseSensitive: false).hasMatch(text)) return 'secure connection failed';
    return text.length > 80 ? '${text.substring(0, 80)}…' : text;
  }

  void _setServers(List<VpnServer> list, DateTime? time, bool cached) {
    countries = groupByCountry(list);
    serversUpdatedAt = time;
    fromCache = cached;
  }

  Country? countryByCode(String? code) {
    if (code == null) return null;
    for (final c in countries) {
      if (c.code == code) return c;
    }
    return null;
  }

  List<Country> get fastestCountries {
    final list = [...countries]..sort((a, b) => b.bestSpeed.compareTo(a.bestSpeed));
    return list.take(10).toList();
  }

  void toggleFavorite(String code) {
    if (!favorites.remove(code)) favorites.add(code);
    _prefs?.setStringList(_favoritesKey, favorites.toList()).ignore();
    _notify();
  }

  // ======================= connection =======================

  bool get busy => phase == VpnPhase.connecting || phase == VpnPhase.disconnecting;

  Future<void> quickConnect() async {
    if (countries.isEmpty) {
      error = loadingServers ? 'The server list is still loading…' : 'No servers yet. Pull down to refresh.';
      _notify();
      if (!loadingServers) unawaited(loadServers(force: true));
      return;
    }
    final last = countryByCode(lastCountry);
    final target = last ??
        countries.reduce((a, b) => a.bestScore >= b.bestScore ? a : b);
    await connectCountry(target);
  }

  Future<void> connectCountry(Country c) => _connect(c.servers.take(maxAttempts).toList());

  Future<void> connectServer(VpnServer s) => _connect([s]);

  Future<void> _connect(List<VpnServer> candidates) async {
    if (busy || candidates.isEmpty) return;
    if (!_engineReady) {
      error = 'The VPN engine is not available on this device.';
      _notify();
      return;
    }
    lastCountry = candidates.first.countryCode;
    _prefs?.setString(_lastCountryKey, lastCountry!).ignore();

    final job = ++_job;
    if (phase == VpnPhase.connected) {
      _userStopping = true;
      phase = VpnPhase.connecting;
      detail = 'Switching server…';
      _notify();
      await _engine.disconnect();
      _userStopping = false;
    }

    String? lastError;
    for (var i = 0; i < candidates.length; i++) {
      if (job != _job) return; // cancelled
      final s = candidates[i];
      server = s;
      attempt = i + 1;
      phase = VpnPhase.connecting;
      detail = 'Contacting server…';
      error = null;
      bytesIn = 0;
      bytesOut = 0;
      connectedAt = null;
      _notify();

      final result = await _attempt(s, job);
      if (job != _job) return;
      if (result == null) {
        phase = VpnPhase.connected;
        connectedAt ??= DateTime.now();
        detail = 'Connected';
        _notify();
        unawaited(refreshIp(delay: const Duration(seconds: 2)));
        return;
      }
      lastError = result;
      if (result == _permissionDenied) break;
    }
    if (job != _job) return;
    phase = VpnPhase.disconnected;
    server = null;
    detail = '';
    error = lastError ?? 'Could not connect. Please try another country.';
    _notify();
  }

  static const _permissionDenied = 'VPN permission was not granted. Tap Connect and allow the VPN request.';

  /// Returns null when connected, otherwise an error message.
  Future<String?> _attempt(VpnServer s, int job) async {
    final outcome = Completer<VPNStage>();
    var sawProgress = false;
    final sub = _engine.stageStream.listen((stage) {
      if (outcome.isCompleted) return;
      if (stage.isConnecting) sawProgress = true;
      if (stage.isConnected ||
          stage == VPNStage.error ||
          stage == VPNStage.denied ||
          stage == VPNStage.auth_failed ||
          (stage == VPNStage.disconnected && sawProgress)) {
        outcome.complete(stage);
      }
    });
    try {
      final started = await _engine.connect(
        prepareConfig(s.config),
        '${s.countryName} · MRMZone VPN',
      );
      if (!started) return _permissionDenied;
      if (_engine.currentStage.isConnected && !outcome.isCompleted) {
        outcome.complete(VPNStage.connected);
      }
      final stage = await outcome.future.timeout(connectTimeout, onTimeout: () => VPNStage.unknown);
      if (stage.isConnected) return null;
      if (stage == VPNStage.denied) return _permissionDenied;

      String? reason;
      try {
        reason = await _engine.lastError();
      } catch (_) {}
      if (job == _job) {
        _userStopping = true;
        await _engine.disconnect();
        _userStopping = false;
      }
      if (stage == VPNStage.unknown) return 'The server did not respond in time. Try another country.';
      if (stage == VPNStage.auth_failed) return 'The server refused the connection (it may be full).';
      return friendlyError(reason);
    } on PlatformException catch (e) {
      return 'Connection failed: ${e.message ?? e.code}';
    } catch (e) {
      return 'Connection failed: $e';
    } finally {
      await sub.cancel();
    }
  }

  Future<void> disconnect() async {
    _job++; // cancels a connect in progress
    _userStopping = true;
    phase = VpnPhase.disconnecting;
    detail = 'Disconnecting…';
    _notify();
    try {
      await _engine.disconnect();
    } catch (_) {}
    _userStopping = false;
    phase = VpnPhase.disconnected;
    server = null;
    connectedAt = null;
    bytesIn = 0;
    bytesOut = 0;
    detail = '';
    error = null;
    _notify();
    unawaited(refreshIp(delay: const Duration(seconds: 1)));
  }

  void _onStage(VPNStage stage) {
    if (phase == VpnPhase.connecting) {
      final labels = {
        VPNStage.prepare: 'Waiting for permission…',
        VPNStage.vpn_generate_config: 'Preparing…',
        VPNStage.resolve: 'Looking up server…',
        VPNStage.tcp_connect: 'Opening connection…',
        VPNStage.udp_connect: 'Opening connection…',
        VPNStage.wait_connection: 'Waiting for server…',
        VPNStage.authenticating: 'Authenticating…',
        VPNStage.authentication: 'Authenticating…',
        VPNStage.get_config: 'Getting settings…',
        VPNStage.assign_ip: 'Assigning IP address…',
        VPNStage.add_routes: 'Routing traffic…',
        VPNStage.reconnect: 'Retrying…',
        VPNStage.no_network: 'Waiting for network…',
      };
      final label = labels[stage];
      if (label != null) {
        detail = label;
        _notify();
      }
    } else if (phase == VpnPhase.connected && !_userStopping) {
      if (stage == VPNStage.reconnect || stage == VPNStage.no_network) {
        detail = stage == VPNStage.no_network ? 'Waiting for network…' : 'Reconnecting…';
        _notify();
      } else if (stage.isConnected) {
        detail = 'Connected';
        _notify();
      } else if (stage.isDisconnected) {
        phase = VpnPhase.disconnected;
        server = null;
        connectedAt = null;
        error = 'The VPN connection was closed.';
        _notify();
        unawaited(refreshIp(delay: const Duration(seconds: 1)));
      }
    } else if (phase == VpnPhase.disconnected && stage.isConnected && server == null) {
      // The app was reopened while the VPN was still running.
      phase = VpnPhase.connected;
      detail = 'Connected';
      _notify();
    }
  }

  void _onStatus(VpnStatus? status) {
    if (status == null) return;
    final inB = int.tryParse(status.byteIn ?? '') ?? 0;
    final outB = int.tryParse(status.byteOut ?? '') ?? 0;
    if (phase == VpnPhase.connected) {
      bytesIn = inB;
      bytesOut = outB;
      if (status.connectedOn != null) connectedAt = status.connectedOn;
      _notify();
    }
  }

  void clearError() {
    if (error != null) {
      error = null;
      _notify();
    }
  }

  // ======================= public IP =======================

  int _ipRequest = 0;
  Future<void> refreshIp({Duration delay = Duration.zero}) async {
    final req = ++_ipRequest;
    if (delay > Duration.zero) await Future<void>.delayed(delay);
    if (req != _ipRequest || _disposed) return;
    checkingIp = true;
    _notify();
    PublicIp? result;
    try {
      final res = await _client.get(Uri.parse('https://ipwho.is/')).timeout(const Duration(seconds: 10));
      final data = jsonDecode(res.body);
      if (data is Map && data['success'] != false && data['ip'] is String) {
        result = PublicIp(data['ip'] as String, '${data['country'] ?? ''}', '${data['country_code'] ?? ''}');
      }
    } catch (_) {}
    if (result == null) {
      try {
        final res = await _client.get(Uri.parse('https://api.ipify.org?format=json')).timeout(const Duration(seconds: 10));
        final data = jsonDecode(res.body);
        if (data is Map && data['ip'] is String) result = PublicIp(data['ip'] as String, '', '');
      } catch (_) {}
    }
    if (req != _ipRequest || _disposed) return;
    publicIp = result ?? const PublicIp(null, '', '');
    checkingIp = false;
    _notify();
  }

  @override
  void dispose() {
    _disposed = true;
    _stageSub?.cancel();
    _statusSub?.cancel();
    _client.close();
    if (_engineReady) _engine.dispose();
    super.dispose();
  }
}
