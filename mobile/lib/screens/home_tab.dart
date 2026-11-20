import 'dart:async';

import 'package:flutter/material.dart';

import '../models/vpn_server.dart';
import '../services/vpn_controller.dart';
import '../theme.dart';
import '../widgets/country_tile.dart';
import 'servers_screen.dart';

class HomeTab extends StatelessWidget {
  const HomeTab({super.key, required this.controller, required this.onSeeAll});
  final VpnController controller;
  final VoidCallback onSeeAll;

  @override
  Widget build(BuildContext context) {
    final c = controller;
    final fastest = c.fastestCountries;
    return RefreshIndicator(
      color: AppColors.orange,
      onRefresh: () => c.loadServers(force: true),
      child: ListView(
        physics: const AlwaysScrollableScrollPhysics(),
        padding: const EdgeInsets.only(bottom: 24),
        children: [
          ConnectionCard(controller: c),
          _SectionTitle(
            title: 'Fastest right now',
            action: c.countries.isEmpty ? null : 'See all countries',
            onAction: onSeeAll,
          ),
          if (c.loadingServers && c.countries.isEmpty)
            const Padding(
              padding: EdgeInsets.all(32),
              child: Center(child: CircularProgressIndicator()),
            )
          else if (c.countries.isEmpty)
            _EmptyServers(controller: c)
          else
            SizedBox(
              height: 196,
              child: ListView.separated(
                scrollDirection: Axis.horizontal,
                padding: const EdgeInsets.symmetric(horizontal: 12),
                itemCount: fastest.length,
                separatorBuilder: (_, _) => const SizedBox(width: 10),
                itemBuilder: (context, i) => _DealCard(controller: c, country: fastest[i], rank: i),
              ),
            ),
          if (c.countries.isNotEmpty) ...[
            _SectionTitle(title: 'Your favorites', action: null, onAction: null),
            if (c.favorites.isEmpty)
              const Padding(
                padding: EdgeInsets.symmetric(horizontal: 16),
                child: Text('Tap ☆ on any country to keep it here.', style: TextStyle(color: AppColors.muted)),
              )
            else
              for (final country in c.countries.where((x) => c.favorites.contains(x.code)))
                CountryTile(controller: c, country: country),
          ],
          if (c.serversUpdatedAt != null)
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 16, 16, 0),
              child: Text(
                '${c.countries.length} countries · list updated ${TimeOfDay.fromDateTime(c.serversUpdatedAt!).format(context)}'
                '${c.fromCache ? ' (saved)' : ''} · pull down to refresh',
                style: const TextStyle(color: AppColors.muted, fontSize: 12),
                textAlign: TextAlign.center,
              ),
            ),
        ],
      ),
    );
  }
}

class _SectionTitle extends StatelessWidget {
  const _SectionTitle({required this.title, required this.action, required this.onAction});
  final String title;
  final String? action;
  final VoidCallback? onAction;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 18, 8, 8),
      child: Row(
        children: [
          Expanded(child: Text(title, style: const TextStyle(fontSize: 19, fontWeight: FontWeight.w700))),
          if (action != null)
            TextButton(
              onPressed: onAction,
              style: TextButton.styleFrom(foregroundColor: AppColors.link),
              child: Text(action!),
            ),
        ],
      ),
    );
  }
}

class _EmptyServers extends StatelessWidget {
  const _EmptyServers({required this.controller});
  final VpnController controller;

  @override
  Widget build(BuildContext context) {
    return Container(
      margin: const EdgeInsets.symmetric(horizontal: 12),
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(color: Colors.white, borderRadius: BorderRadius.circular(8)),
      child: Column(
        children: [
          const Icon(Icons.cloud_off, size: 40, color: AppColors.muted),
          const SizedBox(height: 8),
          Text(
            controller.serverError ?? 'No free servers found.',
            textAlign: TextAlign.center,
            style: const TextStyle(color: AppColors.muted),
          ),
          const SizedBox(height: 12),
          PillButton(label: 'Try again', onPressed: () => controller.loadServers(force: true)),
        ],
      ),
    );
  }
}

class _DealCard extends StatelessWidget {
  const _DealCard({required this.controller, required this.country, required this.rank});
  final VpnController controller;
  final Country country;
  final int rank;

  @override
  Widget build(BuildContext context) {
    final current = controller.server?.countryCode == country.code && controller.phase != VpnPhase.disconnected;
    return SizedBox(
      width: 150,
      child: Material(
        color: Colors.white,
        borderRadius: BorderRadius.circular(8),
        child: InkWell(
          borderRadius: BorderRadius.circular(8),
          onTap: () => Navigator.of(context).push(ServersScreen.route(controller, country)),
          child: Padding(
            padding: const EdgeInsets.all(10),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                if (rank < 3)
                  Container(
                    padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                    decoration: BoxDecoration(color: const Color(0xFFCC0C39), borderRadius: BorderRadius.circular(3)),
                    child: Text('#${rank + 1} Fastest', style: const TextStyle(color: Colors.white, fontSize: 11)),
                  )
                else
                  const SizedBox(height: 18),
                const SizedBox(height: 6),
                Text(flagEmoji(country.code), style: const TextStyle(fontSize: 34)),
                Text(country.name, maxLines: 1, overflow: TextOverflow.ellipsis,
                    style: const TextStyle(fontWeight: FontWeight.w700)),
                const SizedBox(height: 2),
                StarRating(value: speedRating(country.bestSpeed), size: 14),
                Text('Up to ${formatSpeed(country.bestSpeed)}', style: const TextStyle(fontSize: 12, color: AppColors.muted)),
                const Spacer(),
                PillButton(
                  label: current ? (controller.phase == VpnPhase.connected ? 'Connected' : 'Connecting…') : 'Connect',
                  dense: true,
                  expand: true,
                  onPressed: controller.busy || current ? null : () => controller.connectCountry(country),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

/// Big power button with status and traffic.
class ConnectionCard extends StatefulWidget {
  const ConnectionCard({super.key, required this.controller});
  final VpnController controller;

  @override
  State<ConnectionCard> createState() => _ConnectionCardState();
}

class _ConnectionCardState extends State<ConnectionCard> {
  Timer? _ticker;

  @override
  void initState() {
    super.initState();
    _ticker = Timer.periodic(const Duration(seconds: 1), (_) {
      if (mounted && widget.controller.phase == VpnPhase.connected) setState(() {});
    });
  }

  @override
  void dispose() {
    _ticker?.cancel();
    super.dispose();
  }

  void _onPower() {
    final c = widget.controller;
    switch (c.phase) {
      case VpnPhase.disconnected:
        c.quickConnect();
      case VpnPhase.connecting:
      case VpnPhase.connected:
        c.disconnect();
      case VpnPhase.disconnecting:
        break;
    }
  }

  @override
  Widget build(BuildContext context) {
    final c = widget.controller;
    final phase = c.phase;
    final ringColor = switch (phase) {
      VpnPhase.connected => AppColors.green,
      VpnPhase.connecting || VpnPhase.disconnecting => AppColors.yellow,
      VpnPhase.disconnected => const Color(0xFFE7E9EC),
    };
    final iconColor = switch (phase) {
      VpnPhase.connected => AppColors.green,
      VpnPhase.connecting || VpnPhase.disconnecting => AppColors.orange,
      VpnPhase.disconnected => const Color(0xFF8D9096),
    };
    final title = switch (phase) {
      VpnPhase.connected => 'Protected',
      VpnPhase.connecting => 'Connecting…',
      VpnPhase.disconnecting => 'Disconnecting…',
      VpnPhase.disconnected => 'Not connected',
    };
    var subtitle = switch (phase) {
      VpnPhase.connected => 'Your traffic goes through ${c.server?.countryName ?? 'the VPN'}.',
      VpnPhase.connecting => c.detail + (c.attempt > 1 ? ' (server ${c.attempt})' : ''),
      VpnPhase.disconnecting => c.detail,
      VpnPhase.disconnected => 'Tap the button to connect to a free server.',
    };
    if (subtitle.isEmpty) subtitle = ' ';
    final elapsed = phase == VpnPhase.connected && c.connectedAt != null
        ? DateTime.now().difference(c.connectedAt!)
        : Duration.zero;

    return Container(
      margin: const EdgeInsets.fromLTRB(12, 12, 12, 0),
      padding: const EdgeInsets.all(18),
      decoration: BoxDecoration(color: Colors.white, borderRadius: BorderRadius.circular(8)),
      child: Column(
        children: [
          Semantics(
            button: true,
            label: phase == VpnPhase.disconnected ? 'Connect' : 'Disconnect',
            child: GestureDetector(
              onTap: phase == VpnPhase.disconnecting ? null : _onPower,
              child: AnimatedContainer(
                duration: const Duration(milliseconds: 250),
                width: 136,
                height: 136,
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  color: phase == VpnPhase.connected ? const Color(0xFFE9F6F2) : const Color(0xFFF7F8F8),
                  border: Border.all(color: ringColor, width: 8),
                ),
                child: phase == VpnPhase.connecting || phase == VpnPhase.disconnecting
                    ? Stack(alignment: Alignment.center, children: [
                        const SizedBox(
                          width: 120, height: 120,
                          child: CircularProgressIndicator(strokeWidth: 3, color: AppColors.orange),
                        ),
                        Icon(Icons.power_settings_new_rounded, size: 58, color: iconColor),
                      ])
                    : Icon(Icons.power_settings_new_rounded, size: 58, color: iconColor),
              ),
            ),
          ),
          const SizedBox(height: 12),
          Text(title,
              style: TextStyle(
                fontSize: 21,
                fontWeight: FontWeight.w700,
                color: phase == VpnPhase.connected ? AppColors.green : AppColors.text,
              )),
          const SizedBox(height: 2),
          Text(subtitle, textAlign: TextAlign.center, style: const TextStyle(color: AppColors.muted)),
          if (c.server != null && phase != VpnPhase.disconnected) ...[
            const SizedBox(height: 12),
            Container(
              padding: const EdgeInsets.all(10),
              decoration: BoxDecoration(
                border: Border.all(color: AppColors.border),
                borderRadius: BorderRadius.circular(8),
              ),
              child: Row(
                children: [
                  Text(flagEmoji(c.server!.countryCode), style: const TextStyle(fontSize: 28)),
                  const SizedBox(width: 10),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(c.server!.countryName, style: const TextStyle(fontWeight: FontWeight.w700)),
                        Text('${c.server!.hostName} · ${c.server!.protocol}',
                            maxLines: 1, overflow: TextOverflow.ellipsis,
                            style: const TextStyle(fontSize: 12, color: AppColors.muted)),
                      ],
                    ),
                  ),
                ],
              ),
            ),
          ],
          const SizedBox(height: 12),
          Row(
            children: [
              _Stat(label: 'Time', value: formatDuration(elapsed)),
              const SizedBox(width: 8),
              _Stat(label: 'Download', value: formatBytes(c.bytesIn)),
              const SizedBox(width: 8),
              _Stat(label: 'Upload', value: formatBytes(c.bytesOut)),
            ],
          ),
          const SizedBox(height: 14),
          if (phase == VpnPhase.disconnected)
            PillButton(label: 'Quick connect', expand: true, onPressed: c.quickConnect)
          else
            PillButton(
              label: phase == VpnPhase.connecting ? 'Cancel' : 'Disconnect',
              orange: true,
              expand: true,
              onPressed: phase == VpnPhase.disconnecting ? null : c.disconnect,
            ),
        ],
      ),
    );
  }
}

class _Stat extends StatelessWidget {
  const _Stat({required this.label, required this.value});
  final String label;
  final String value;

  @override
  Widget build(BuildContext context) {
    return Expanded(
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 8),
        decoration: BoxDecoration(
          color: const Color(0xFFF7FAFA),
          border: Border.all(color: const Color(0xFFE3E6E6)),
          borderRadius: BorderRadius.circular(8),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(label, style: const TextStyle(fontSize: 11, color: AppColors.muted)),
            FittedBox(
              fit: BoxFit.scaleDown,
              alignment: Alignment.centerLeft,
              child: Text(value, style: const TextStyle(fontWeight: FontWeight.w700, fontFeatures: [FontFeature.tabularFigures()])),
            ),
          ],
        ),
      ),
    );
  }
}
