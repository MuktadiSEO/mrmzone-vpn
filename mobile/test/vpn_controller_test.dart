import 'dart:async';
import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:mrmzone_vpn/services/vpn_controller.dart';
import 'package:openvpn_flutter/openvpn_flutter.dart';
import 'package:shared_preferences/shared_preferences.dart';

String b64(String remote) =>
    base64.encode(utf8.encode('client\nproto udp\nremote $remote 1194\ncipher AES-128-CBC\n${'#' * 80}\n'));
String row(String host, int score, String cc, String name, String remote) =>
    [host, '203.0.113.$score', score, 10, 50000000, name, cc, 1, 1, 1, 1, 'x', 'op', '', b64(remote)].join(',');

final csv = [
  '*vpn_servers',
  '#h',
  row('jp-bad', 99, 'JP', 'Japan', 'fail'),
  row('jp-good', 50, 'JP', 'Japan', 'ok'),
  row('kr-deny', 10, 'KR', 'Korea Republic of', 'deny'),
  '*',
].join('\n');

/// Fake engine: behaviour depends on the `remote` host in the config.
class FakeEngine implements OpenVPN {
  final _stages = StreamController<VPNStage>.broadcast();
  VPNStage _stage = VPNStage.disconnected;
  final connects = <String>[];
  int disconnects = 0;

  void _emit(VPNStage s) {
    _stage = s;
    _stages.add(s);
  }

  @override
  Stream<VPNStage> get stageStream => _stages.stream;
  @override
  VPNStage get currentStage => _stage;
  @override
  Stream<VpnStatus> get statusStream => const Stream.empty();

  @override
  Future<void> initialize({
    String? providerBundleIdentifier,
    String? localizedDescription,
    String? groupIdentifier,
    Function(VpnStatus status)? lastStatus,
    Function(VPNStage stage)? lastStage,
    bool? showTrafficInNotification,
    bool? disconnectOnTaskRemoved,
  }) async {}

  @override
  Future<bool> connect(String config, String name,
      {String? username,
      String? password,
      List<String>? bypassPackages,
      List<String>? allowedPackages,
      bool? certIsRequired,
      String? privateKeyPassword,
      DateTime? expireAt}) async {
    final remote = RegExp(r'remote (\S+)').firstMatch(config)!.group(1)!;
    connects.add(remote);
    expect(config, contains('data-ciphers-fallback AES-128-CBC'));
    if (remote == 'deny') {
      _emit(VPNStage.denied);
      return false;
    }
    scheduleMicrotask(() async {
      _emit(VPNStage.connecting);
      await Future<void>.delayed(const Duration(milliseconds: 10));
      _emit(remote == 'ok' ? VPNStage.connected : VPNStage.error);
    });
    return true;
  }

  @override
  Future<void> disconnect() async {
    disconnects++;
    if (_stage != VPNStage.disconnected) _emit(VPNStage.disconnected);
  }

  @override
  Future<String?> lastError() async => 'TLS handshake failed';

  @override
  void dispose() {}

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

void main() {
  late FakeEngine engine;
  late VpnController c;

  setUp(() async {
    SharedPreferences.setMockInitialValues({});
    engine = FakeEngine();
    final client = MockClient((req) async {
      if (req.url.host == 'www.vpngate.net') return http.Response(csv, 200);
      return http.Response(jsonEncode({'success': true, 'ip': '198.51.100.7', 'country': 'Bangladesh', 'country_code': 'BD'}), 200);
    });
    c = VpnController(engine: engine, client: client);
    await c.init();
  });

  test('loads the list and fails over to the next server', () async {
    expect(c.countries.map((x) => x.code), ['JP', 'KR']);
    await c.connectCountry(c.countries.first);
    expect(engine.connects, ['fail', 'ok']);
    expect(c.phase, VpnPhase.connected);
    expect(c.server!.hostName, 'jp-good');
    expect(c.attempt, 2);
    expect(c.error, isNull);

    await c.disconnect();
    expect(c.phase, VpnPhase.disconnected);
    expect(c.server, isNull);
  });

  test('permission denied stops trying and shows a message', () async {
    await c.connectCountry(c.countries.last);
    expect(engine.connects, ['deny']);
    expect(c.phase, VpnPhase.disconnected);
    expect(c.error, contains('permission'));
  });

  test('connection lost while connected is reported', () async {
    await c.connectCountry(c.countries.first);
    expect(c.phase, VpnPhase.connected);
    engine._emit(VPNStage.error);
    await Future<void>.delayed(Duration.zero);
    expect(c.phase, VpnPhase.disconnected);
    expect(c.error, contains('closed'));
  });

  test('quick connect remembers the last country', () async {
    await c.connectCountry(c.countries.first);
    await c.disconnect();
    engine.connects.clear();
    await c.quickConnect();
    expect(c.server!.countryCode, 'JP');
  });

  test('friendly errors', () {
    expect(friendlyError('TLS Error: TLS key negotiation failed'), contains('did not answer'));
    expect(friendlyError(null), 'Connection failed. Try another country.');
    expect(friendlyError('weird'), 'Connection failed: weird');
  });

  test('uses the GitHub mirror when vpngate.net is blocked', () async {
    SharedPreferences.setMockInitialValues({});
    final hosts = <String>[];
    final client = MockClient((req) async {
      hosts.add(req.url.host);
      if (req.url.host == 'www.vpngate.net') throw http.ClientException('Connection reset by peer');
      if (req.url.host == 'raw.githubusercontent.com') return http.Response(csv, 200);
      return http.Response('{}', 200);
    });
    final m = VpnController(engine: FakeEngine(), client: client);
    await m.init();
    expect(m.countries.map((x) => x.code), ['JP', 'KR']);
    expect(m.serverError, isNull);
    expect(hosts, containsAllInOrder(['www.vpngate.net', 'raw.githubusercontent.com']));
  });

  test('clear message when every source is blocked', () async {
    SharedPreferences.setMockInitialValues({});
    final client = MockClient((req) async => throw http.ClientException('SocketException: Connection reset'));
    final m = VpnController(engine: FakeEngine(), client: client);
    await m.init();
    expect(m.countries, isEmpty);
    expect(m.serverError, contains('server unreachable'));
  });

  test('favorites persist', () async {
    c.toggleFavorite('KR');
    final prefs = await SharedPreferences.getInstance();
    expect(prefs.getStringList('favorites'), ['KR']);
    c.toggleFavorite('KR');
    expect(c.favorites, isEmpty);
  });
}
