import 'package:flutter/material.dart';

import '../models/vpn_server.dart';
import '../services/vpn_controller.dart';
import '../theme.dart';
import '../widgets/country_tile.dart';

enum SortBy { name, speed, ping, servers }

class CountryList extends StatefulWidget {
  const CountryList({super.key, required this.controller, required this.query, required this.favoritesOnly});
  final VpnController controller;
  final String query;
  final bool favoritesOnly;

  @override
  State<CountryList> createState() => _CountryListState();
}

class _CountryListState extends State<CountryList> {
  SortBy _sort = SortBy.name;

  List<Country> _visible() {
    final q = widget.query.trim().toLowerCase();
    var list = widget.controller.countries.where((c) {
      if (widget.favoritesOnly && !widget.controller.favorites.contains(c.code)) return false;
      if (q.isEmpty) return true;
      return c.name.toLowerCase().contains(q) || c.code.toLowerCase() == q;
    }).toList();
    switch (_sort) {
      case SortBy.name:
        break; // already A–Z
      case SortBy.speed:
        list.sort((a, b) => b.bestSpeed.compareTo(a.bestSpeed));
      case SortBy.ping:
        int p(Country c) => c.bestPing > 0 ? c.bestPing : 1 << 30;
        list.sort((a, b) => p(a).compareTo(p(b)));
      case SortBy.servers:
        list.sort((a, b) => b.servers.length.compareTo(a.servers.length));
    }
    return list;
  }

  @override
  Widget build(BuildContext context) {
    final c = widget.controller;
    final list = _visible();
    const labels = {SortBy.name: 'A–Z', SortBy.speed: 'Fastest', SortBy.ping: 'Lowest ping', SortBy.servers: 'Most servers'};

    Widget body;
    if (c.loadingServers && c.countries.isEmpty) {
      body = const Center(child: CircularProgressIndicator());
    } else if (list.isEmpty) {
      String msg;
      if (c.countries.isEmpty) {
        msg = c.serverError ?? 'No servers yet. Pull down to refresh.';
      } else if (widget.favoritesOnly && c.favorites.isEmpty) {
        msg = 'No favorites yet.\nTap ☆ on any country to save it here.';
      } else {
        msg = 'No countries match "${widget.query}".';
      }
      body = ListView(
        physics: const AlwaysScrollableScrollPhysics(),
        children: [
          Padding(
            padding: const EdgeInsets.all(40),
            child: Text(msg, textAlign: TextAlign.center, style: const TextStyle(color: AppColors.muted)),
          ),
        ],
      );
    } else {
      body = ListView.builder(
        physics: const AlwaysScrollableScrollPhysics(),
        padding: const EdgeInsets.only(bottom: 16),
        itemCount: list.length + 1,
        itemBuilder: (context, i) {
          if (i == 0) {
            return Padding(
              padding: const EdgeInsets.fromLTRB(16, 4, 16, 8),
              child: Text(
                '${list.length} ${list.length == 1 ? 'result' : 'results'}'
                '${widget.query.trim().isNotEmpty ? ' for "${widget.query.trim()}"' : ''}',
                style: const TextStyle(color: AppColors.muted),
              ),
            );
          }
          final country = list[i - 1];
          return CountryTile(key: ValueKey(country.code), controller: c, country: country);
        },
      );
    }

    return Column(
      children: [
        SizedBox(
          height: 52,
          child: ListView(
            scrollDirection: Axis.horizontal,
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
            children: [
              for (final s in SortBy.values)
                Padding(
                  padding: const EdgeInsets.only(right: 8),
                  child: ChoiceChip(
                    label: Text(labels[s]!),
                    selected: _sort == s,
                    onSelected: (_) => setState(() => _sort = s),
                    selectedColor: const Color(0xFFE3F4F7),
                    backgroundColor: Colors.white,
                    side: BorderSide(color: _sort == s ? AppColors.tabSelected : AppColors.border),
                    showCheckmark: false,
                    labelStyle: TextStyle(
                      color: _sort == s ? AppColors.tabSelected : AppColors.text,
                      fontWeight: _sort == s ? FontWeight.w700 : FontWeight.w400,
                    ),
                  ),
                ),
            ],
          ),
        ),
        Expanded(
          child: RefreshIndicator(
            color: AppColors.orange,
            onRefresh: () => c.loadServers(force: true),
            child: body,
          ),
        ),
      ],
    );
  }
}
