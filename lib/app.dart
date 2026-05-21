import 'dart:io';
import 'package:flutter/material.dart';
import 'screens/tela_inicial.dart';
import 'theme/app_theme.dart';
import 'widgets/mini_player_overlay.dart';
import 'widgets/shell_desktop.dart';

class IptvApp extends StatelessWidget {
  const IptvApp({super.key});

  static bool get _isDesktopOS =>
      Platform.isWindows || Platform.isMacOS || Platform.isLinux;

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'IPTV',
      debugShowCheckedModeBanner: false,
      theme: AppTheme.dark,
      themeMode: ThemeMode.dark,
      builder: (context, child) => MiniPlayerOverlay(child: child!),
      home: _isDesktopOS ? const ShellDesktop() : const TelaInicial(),
    );
  }
}