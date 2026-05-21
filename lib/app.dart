import 'package:flutter/material.dart';
import 'screens/tela_inicial.dart';
import 'theme/app_theme.dart';
import 'widgets/mini_player_overlay.dart';

class IptvApp extends StatelessWidget {
  const IptvApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'IPTV',
      debugShowCheckedModeBanner: false,
      theme: AppTheme.dark,
      themeMode: ThemeMode.dark,
      builder: (context, child) => MiniPlayerOverlay(child: child!),
      home: const TelaInicial(),
    );
  }
}