import 'dart:io';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'screens/tela_inicial.dart';
import 'screens/tela_onboarding.dart';
import 'state/preferencias_provider.dart';
import 'theme/app_theme.dart';
import 'utils/nav_keys.dart';
import 'widgets/mini_player_overlay.dart';
import 'widgets/shell_desktop.dart';

class IptvApp extends StatelessWidget {
  const IptvApp({super.key});

  static bool get _isDesktopOS =>
      Platform.isWindows || Platform.isMacOS || Platform.isLinux;

  @override
  Widget build(BuildContext context) {
    // Enquanto o usuario nao escolher um idioma, mostramos o onboarding.
    // Assim que ele escolhe, PreferenciasProvider notifica e a home troca.
    final temIdioma = context.watch<PreferenciasProvider>().idiomaDefinido;

    return MaterialApp(
      title: 'IPTV',
      debugShowCheckedModeBanner: false,
      navigatorKey: rootNavigatorKey,
      theme: AppTheme.dark,
      themeMode: ThemeMode.dark,
      builder: (context, child) => MiniPlayerOverlay(child: child!),
      home: !temIdioma
          ? const TelaOnboarding()
          : (_isDesktopOS ? const ShellDesktop() : const TelaInicial()),
    );
  }
}