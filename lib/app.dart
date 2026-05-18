import 'package:flutter/material.dart';
import 'screens/tela_inicial.dart';
import 'theme/app_theme.dart';

/// Widget raiz da aplicacao.
///
/// Dark mode forcado por design - ver PRODUCT.md (cena fisica de uso a noite).
class IptvApp extends StatelessWidget {
  const IptvApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'IPTV',
      debugShowCheckedModeBanner: false,
      theme: AppTheme.dark,
      themeMode: ThemeMode.dark,
      home: const TelaInicial(),
    );
  }
}