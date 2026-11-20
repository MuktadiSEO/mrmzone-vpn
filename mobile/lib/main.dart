import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import 'screens/shell.dart';
import 'services/vpn_controller.dart';
import 'theme.dart';

void main() {
  WidgetsFlutterBinding.ensureInitialized();
  SystemChrome.setSystemUIOverlayStyle(const SystemUiOverlayStyle(
    statusBarColor: Colors.transparent,
    statusBarIconBrightness: Brightness.dark,
  ));
  final controller = VpnController();
  controller.init();
  runApp(MrmzoneVpnApp(controller: controller));
}

class MrmzoneVpnApp extends StatelessWidget {
  const MrmzoneVpnApp({super.key, required this.controller});
  final VpnController controller;

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'MRMZone VPN',
      debugShowCheckedModeBanner: false,
      theme: buildTheme(),
      home: AppShell(controller: controller),
    );
  }
}
