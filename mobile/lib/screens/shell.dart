import 'package:flutter/material.dart';

import '../services/vpn_controller.dart';
import '../theme.dart';
import 'country_list.dart';
import 'home_tab.dart';

/// Main screen: teal header with search, location strip, tabs.
class AppShell extends StatefulWidget {
  const AppShell({super.key, required this.controller});
  final VpnController controller;

  @override
  State<AppShell> createState() => _AppShellState();
}

class _AppShellState extends State<AppShell> {
  int _tab = 0;
  String _query = '';
  final _search = TextEditingController();
  final _searchFocus = FocusNode();
  String? _shownError;

  VpnController get c => widget.controller;

  @override
  void initState() {
    super.initState();
    c.addListener(_onChange);
  }

  @override
  void didUpdateWidget(covariant AppShell oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.controller != widget.controller) {
      oldWidget.controller.removeListener(_onChange);
      widget.controller.addListener(_onChange);
    }
  }

  @override
  void dispose() {
    c.removeListener(_onChange);
    _search.dispose();
    _searchFocus.dispose();
    super.dispose();
  }

  void _onChange() {
    final err = c.error;
    if (err != null && err != _shownError && mounted) {
      _shownError = err;
      ScaffoldMessenger.of(context)
        ..hideCurrentSnackBar()
        ..showSnackBar(SnackBar(
          content: Text(err),
          backgroundColor: AppColors.navy2,
          action: SnackBarAction(label: 'OK', textColor: AppColors.orange, onPressed: () {}),
        ));
    } else if (err == null) {
      _shownError = null;
    }
  }

  void _setTab(int i) {
    setState(() => _tab = i);
    if (i != 1) _searchFocus.unfocus();
  }

  @override
  Widget build(BuildContext context) {
    return ListenableBuilder(
      listenable: c,
      builder: (context, _) {
        return Scaffold(
          body: Column(
            children: [
              _Header(
                controller: _search,
                focusNode: _searchFocus,
                onTap: () {
                  if (_tab != 1) setState(() => _tab = 1);
                },
                onChanged: (v) => setState(() => _query = v),
                onClear: () {
                  _search.clear();
                  setState(() => _query = '');
                },
              ),
              _LocationStrip(controller: c),
              Expanded(
                child: IndexedStack(
                  index: _tab,
                  children: [
                    HomeTab(controller: c, onSeeAll: () => _setTab(1)),
                    CountryList(controller: c, query: _query, favoritesOnly: false),
                    CountryList(controller: c, query: _query, favoritesOnly: true),
                  ],
                ),
              ),
            ],
          ),
          bottomNavigationBar: _BottomBar(index: _tab, onTap: _setTab, connected: c.phase == VpnPhase.connected),
        );
      },
    );
  }
}

class _Header extends StatelessWidget {
  const _Header({
    required this.controller,
    required this.focusNode,
    required this.onTap,
    required this.onChanged,
    required this.onClear,
  });

  final TextEditingController controller;
  final FocusNode focusNode;
  final VoidCallback onTap;
  final ValueChanged<String> onChanged;
  final VoidCallback onClear;

  @override
  Widget build(BuildContext context) {
    final top = MediaQuery.paddingOf(context).top;
    return Container(
      padding: EdgeInsets.fromLTRB(12, top + 8, 12, 10),
      decoration: const BoxDecoration(
        gradient: LinearGradient(
          colors: [AppColors.headerTop, AppColors.headerBottom],
          begin: Alignment.centerLeft,
          end: Alignment.centerRight,
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              const Icon(Icons.shield_rounded, color: AppColors.navy, size: 26),
              const SizedBox(width: 4),
              RichText(
                text: const TextSpan(
                  style: TextStyle(fontSize: 22, fontWeight: FontWeight.w800, letterSpacing: -0.5, color: AppColors.navy),
                  children: [
                    TextSpan(text: 'mrmzone'),
                    TextSpan(text: 'vpn', style: TextStyle(color: Color(0xFFE47911))),
                  ],
                ),
              ),
              const Spacer(),
              IconButton(
                tooltip: 'About',
                icon: const Icon(Icons.info_outline, color: AppColors.navy),
                onPressed: () => showAbout(context),
              ),
            ],
          ),
          const SizedBox(height: 6),
          Material(
            elevation: 2,
            borderRadius: BorderRadius.circular(10),
            child: SizedBox(
              height: 46,
              child: ValueListenableBuilder<TextEditingValue>(
                valueListenable: controller,
                builder: (context, value, _) => TextField(
                  controller: controller,
                  focusNode: focusNode,
                  onTap: onTap,
                  onChanged: onChanged,
                  textInputAction: TextInputAction.search,
                  decoration: InputDecoration(
                    hintText: 'Search countries',
                    prefixIcon: const Icon(Icons.search, color: AppColors.text),
                    suffixIcon: value.text.isEmpty
                        ? null
                        : IconButton(icon: const Icon(Icons.close), tooltip: 'Clear', onPressed: onClear),
                    border: OutlineInputBorder(borderRadius: BorderRadius.circular(10), borderSide: BorderSide.none),
                    filled: true,
                    fillColor: Colors.white,
                    contentPadding: EdgeInsets.zero,
                  ),
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

void showAbout(BuildContext context) {
  showModalBottomSheet<void>(
    context: context,
    showDragHandle: true,
    backgroundColor: Colors.white,
    builder: (context) => const SafeArea(
      child: Padding(
        padding: EdgeInsets.fromLTRB(20, 0, 20, 20),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text('MRMZone VPN', style: TextStyle(fontSize: 20, fontWeight: FontWeight.w700)),
            SizedBox(height: 8),
            Text(
              'Free VPN with servers in many countries. No account, no payment.\n\n'
              'Servers are run by volunteers through the VPN Gate academic project '
              '(University of Tsukuba, Japan), so speed and availability change during the day. '
              'If a country does not connect, the app automatically tries the next server; '
              'you can also pick another server or country.\n\n'
              'Tip: Android Settings › Network › VPN lets you turn on "Always-on VPN" and '
              '"Block connections without VPN" for extra safety.',
              style: TextStyle(color: AppColors.muted, height: 1.4),
            ),
          ],
        ),
      ),
    ),
  );
}

class _LocationStrip extends StatelessWidget {
  const _LocationStrip({required this.controller});
  final VpnController controller;

  @override
  Widget build(BuildContext context) {
    final ip = controller.publicIp;
    String text;
    if (controller.checkingIp && ip == null) {
      text = 'Checking your IP address…';
    } else if (ip?.ip == null) {
      text = 'IP address unavailable';
    } else {
      final where = ip!.country.isNotEmpty ? ' · ${ip.country}' : '';
      text = 'Your IP ${ip.ip}$where';
    }
    final connected = controller.phase == VpnPhase.connected;
    return Material(
      color: AppColors.locationStrip,
      child: InkWell(
        onTap: () => controller.refreshIp(),
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 9),
          child: Row(
            children: [
              Icon(connected ? Icons.lock_rounded : Icons.location_on_outlined, size: 18, color: AppColors.text),
              const SizedBox(width: 6),
              Expanded(
                child: Text(text, maxLines: 1, overflow: TextOverflow.ellipsis, style: const TextStyle(fontSize: 13)),
              ),
              if (controller.checkingIp)
                const SizedBox(width: 14, height: 14, child: CircularProgressIndicator(strokeWidth: 2))
              else
                const Icon(Icons.refresh, size: 18, color: AppColors.muted),
            ],
          ),
        ),
      ),
    );
  }
}

class _BottomBar extends StatelessWidget {
  const _BottomBar({required this.index, required this.onTap, required this.connected});
  final int index;
  final ValueChanged<int> onTap;
  final bool connected;

  @override
  Widget build(BuildContext context) {
    final items = [
      (connected ? Icons.shield : Icons.shield_outlined, 'Home'),
      (Icons.public, 'Countries'),
      (Icons.star_border_rounded, 'Favorites'),
    ];
    return Container(
      decoration: const BoxDecoration(
        color: Colors.white,
        border: Border(top: BorderSide(color: AppColors.border)),
      ),
      child: SafeArea(
        top: false,
        child: SizedBox(
          height: 58,
          child: Row(
            children: [
              for (var i = 0; i < items.length; i++)
                Expanded(
                  child: InkWell(
                    onTap: () => onTap(i),
                    child: Column(
                      children: [
                        Container(
                          height: 3,
                          width: 48,
                          color: index == i ? AppColors.tabSelected : Colors.transparent,
                        ),
                        const SizedBox(height: 6),
                        Icon(items[i].$1, color: index == i ? AppColors.tabSelected : AppColors.text, size: 24),
                        Text(
                          items[i].$2,
                          style: TextStyle(
                            fontSize: 11,
                            color: index == i ? AppColors.tabSelected : AppColors.text,
                            fontWeight: index == i ? FontWeight.w700 : FontWeight.w400,
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
            ],
          ),
        ),
      ),
    );
  }
}
