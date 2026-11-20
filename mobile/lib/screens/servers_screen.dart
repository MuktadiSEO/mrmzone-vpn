import 'package:flutter/material.dart';

import '../models/vpn_server.dart';
import '../services/vpn_controller.dart';
import '../theme.dart';

/// All free servers of one country.
class ServersScreen extends StatelessWidget {
  const ServersScreen({super.key, required this.controller, required this.country});
  final VpnController controller;
  final Country country;

  static Route<void> route(VpnController controller, Country country) =>
      MaterialPageRoute(builder: (_) => ServersScreen(controller: controller, country: country));

  @override
  Widget build(BuildContext context) {
    return ListenableBuilder(
      listenable: controller,
      builder: (context, _) {
        final c = controller;
        // The list may have been refreshed meanwhile; use the latest data.
        final current = c.countryByCode(country.code) ?? country;
        final fav = c.favorites.contains(current.code);
        return Scaffold(
          appBar: AppBar(
            backgroundColor: AppColors.navy2,
            foregroundColor: Colors.white,
            title: Text('${flagEmoji(current.code)}  ${current.name}'),
            actions: [
              IconButton(
                tooltip: fav ? 'Remove from favorites' : 'Add to favorites',
                icon: Icon(fav ? Icons.star_rounded : Icons.star_outline_rounded,
                    color: fav ? AppColors.orange : Colors.white),
                onPressed: () => c.toggleFavorite(current.code),
              ),
            ],
          ),
          body: ListView(
            padding: const EdgeInsets.only(bottom: 24),
            children: [
              Container(
                color: Colors.white,
                padding: const EdgeInsets.all(16),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text('${current.servers.length} free ${current.servers.length == 1 ? 'server' : 'servers'}',
                        style: const TextStyle(fontSize: 18, fontWeight: FontWeight.w700)),
                    const SizedBox(height: 4),
                    const Text(
                      'Best servers are listed first. "Connect to best" automatically tries the next server if one does not answer.',
                      style: TextStyle(color: AppColors.muted),
                    ),
                    const SizedBox(height: 12),
                    PillButton(
                      label: 'Connect to best server',
                      expand: true,
                      onPressed: c.busy || current.servers.isEmpty
                          ? null
                          : () {
                              c.connectCountry(current);
                              Navigator.of(context).pop();
                            },
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 8),
              for (final s in current.servers) _ServerRow(controller: c, server: s),
            ],
          ),
        );
      },
    );
  }
}

class _ServerRow extends StatelessWidget {
  const _ServerRow({required this.controller, required this.server});
  final VpnController controller;
  final VpnServer server;

  @override
  Widget build(BuildContext context) {
    final c = controller;
    final isCurrent = c.server?.id == server.id && c.phase != VpnPhase.disconnected;
    Widget button;
    if (isCurrent && c.phase == VpnPhase.connected) {
      button = PillButton(label: 'Disconnect', orange: true, dense: true, onPressed: c.disconnect);
    } else if (isCurrent) {
      button = const PillButton(label: 'Connecting…', dense: true, onPressed: null);
    } else {
      button = PillButton(
        label: 'Connect',
        dense: true,
        onPressed: c.busy
            ? null
            : () {
                c.connectServer(server);
                Navigator.of(context).pop();
              },
      );
    }
    return Container(
      margin: const EdgeInsets.fromLTRB(12, 0, 12, 8),
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: isCurrent ? AppColors.green : Colors.transparent, width: 2),
      ),
      child: Row(
        children: [
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(server.hostName, style: const TextStyle(fontWeight: FontWeight.w700)),
                const SizedBox(height: 2),
                Text(
                  '${formatSpeed(server.speed)} · ${server.ping > 0 ? '${server.ping} ms' : '— ms'} · ${server.protocol}',
                  style: const TextStyle(fontSize: 12, color: AppColors.muted),
                ),
                Text('${server.sessions} people online · ${server.ip}',
                    style: const TextStyle(fontSize: 12, color: AppColors.muted)),
              ],
            ),
          ),
          const SizedBox(width: 8),
          button,
        ],
      ),
    );
  }
}
