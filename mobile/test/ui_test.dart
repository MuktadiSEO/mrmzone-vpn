import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mrmzone_vpn/main.dart';
import 'package:mrmzone_vpn/models/vpn_server.dart';
import 'package:mrmzone_vpn/services/vpn_controller.dart';

VpnServer server(String cc, String name, int i) => VpnServer(
      hostName: 'public-vpn-$cc$i',
      ip: '203.0.113.$i',
      score: 1000 - i,
      ping: 10 + i,
      speed: (100 - i) * 1000000,
      countryName: name,
      countryCode: cc,
      sessions: 5,
      protocol: 'UDP',
      config: utf8.decode(utf8.encode('client\nremote 203.0.113.$i 1194\n')),
    );

void main() {
  testWidgets('home, countries search, favorites and server list render', (tester) async {
    final c = VpnController();
    c.countries = [
      Country(code: 'DE', name: 'Germany', servers: [server('DE', 'Germany', 1)]),
      Country(code: 'JP', name: 'Japan', servers: [server('JP', 'Japan', 2), server('JP', 'Japan', 3)]),
      Country(code: 'KR', name: 'Korea Republic of', servers: [server('KR', 'Korea Republic of', 4)]),
    ];
    c.serversUpdatedAt = DateTime(2026, 1, 1, 10);
    await tester.pumpWidget(MrmzoneVpnApp(controller: c));
    await tester.pump();

    expect(find.text('Not connected'), findsOneWidget);
    expect(find.text('Quick connect'), findsOneWidget);
    expect(find.text('Fastest right now'), findsOneWidget);

    // Search switches to the Countries tab and filters.
    await tester.tap(find.byType(TextField));
    await tester.enterText(find.byType(TextField), 'jap');
    await tester.pump();
    expect(find.text('1 result for "jap"'), findsOneWidget);

    // Favorite it, then check the Favorites tab.
    await tester.tap(find.byTooltip('Add to favorites').hitTestable().first);
    await tester.pump();
    expect(c.favorites.contains('JP'), isTrue);
    await tester.enterText(find.byType(TextField), '');
    await tester.tap(find.text('Favorites'));
    await tester.pump();
    expect(find.text('Japan').hitTestable(), findsWidgets);

    // Open the server list.
    await tester.tap(find.text('Japan').hitTestable().first);
    await tester.pumpAndSettle();
    expect(find.text('2 free servers'), findsOneWidget);
    expect(find.text('public-vpn-JP2'), findsOneWidget);
    await tester.pageBack();
    await tester.pumpAndSettle();

    // Connection card states.
    c.phase = VpnPhase.connected;
    c.server = c.countries[1].servers.first;
    c.connectedAt = DateTime.now().subtract(const Duration(seconds: 65));
    c.bytesIn = 2048;
    c.notifyListeners();
    await tester.tap(find.text('Home'));
    await tester.pump();
    expect(find.text('Protected'), findsOneWidget);
    expect(find.text('Disconnect'), findsWidgets);
    expect(find.text('2.0 KB'), findsOneWidget);
    await tester.pump(const Duration(seconds: 2));
  });
}
