import 'package:flutter/material.dart';

import '../models/vpn_server.dart';
import '../screens/servers_screen.dart';
import '../services/vpn_controller.dart';
import '../theme.dart';

/// Product-listing style row for one country.
class CountryTile extends StatelessWidget {
  const CountryTile({super.key, required this.controller, required this.country});
  final VpnController controller;
  final Country country;

  @override
  Widget build(BuildContext context) {
    final c = controller;
    final isCurrent = c.server?.countryCode == country.code && c.phase != VpnPhase.disconnected;
    final fav = c.favorites.contains(country.code);
    final count = country.servers.length;

    Widget action;
    if (isCurrent && c.phase == VpnPhase.connected) {
      action = PillButton(label: 'Disconnect', orange: true, dense: true, onPressed: c.disconnect);
    } else if (isCurrent) {
      action = const PillButton(label: 'Connecting…', dense: true, onPressed: null);
    } else {
      action = PillButton(label: 'Connect', dense: true, onPressed: c.busy ? null : () => c.connectCountry(country));
    }

    return Container(
      margin: const EdgeInsets.fromLTRB(12, 0, 12, 10),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: isCurrent ? AppColors.green : Colors.transparent, width: 2),
      ),
      child: Material(
        color: Colors.transparent,
        child: InkWell(
          borderRadius: BorderRadius.circular(8),
          onTap: () => Navigator.of(context).push(ServersScreen.route(c, country)),
          child: Padding(
            padding: const EdgeInsets.fromLTRB(12, 12, 4, 12),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Container(
                  width: 64,
                  height: 64,
                  alignment: Alignment.center,
                  decoration: BoxDecoration(color: const Color(0xFFF7F8F8), borderRadius: BorderRadius.circular(6)),
                  child: Text(flagEmoji(country.code), style: const TextStyle(fontSize: 36)),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(country.name,
                          maxLines: 2, overflow: TextOverflow.ellipsis,
                          style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w600, height: 1.2)),
                      const SizedBox(height: 3),
                      Row(children: [
                        StarRating(value: speedRating(country.bestSpeed), size: 15),
                        const SizedBox(width: 4),
                        Text('$count ${count == 1 ? 'server' : 'servers'}',
                            style: const TextStyle(color: AppColors.link, fontSize: 12)),
                      ]),
                      const SizedBox(height: 2),
                      Text(
                        'Up to ${formatSpeed(country.bestSpeed)}${country.bestPing > 0 ? ' · ${country.bestPing} ms' : ''}',
                        style: const TextStyle(color: AppColors.muted, fontSize: 12),
                      ),
                      const SizedBox(height: 2),
                      const Text.rich(TextSpan(children: [
                        TextSpan(text: 'FREE ', style: TextStyle(color: AppColors.red, fontWeight: FontWeight.w700, fontSize: 16)),
                        TextSpan(text: 'no sign-up', style: TextStyle(color: Color(0xFF00A8E1), fontStyle: FontStyle.italic, fontWeight: FontWeight.w700, fontSize: 12)),
                      ])),
                      const SizedBox(height: 8),
                      action,
                    ],
                  ),
                ),
                IconButton(
                  tooltip: fav ? 'Remove from favorites' : 'Add to favorites',
                  icon: Icon(fav ? Icons.star_rounded : Icons.star_outline_rounded,
                      color: fav ? AppColors.star : const Color(0xFFB0B0B0)),
                  onPressed: () => c.toggleFavorite(country.code),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
