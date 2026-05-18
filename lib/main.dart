import 'package:flutter/material.dart';
import 'package:media_kit/media_kit.dart';
import 'package:provider/provider.dart';
import 'app.dart';
import 'services/armazenamento.dart';
import 'state/iptv_provider.dart';

/// Ponto de entrada da aplicacao.
///
/// Antes de chamar runApp(), inicializamos:
///  1. WidgetsFlutterBinding - obrigatorio se chamamos algo async antes de runApp.
///  2. MediaKit - inicializa libmpv para o player de video.
///  3. Hive (banco local) atraves do Armazenamento.
///  4. IptvProvider, que carrega listas/favoritos/historico salvos.
Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();

  // Inicializa o engine de video (libmpv).
  MediaKit.ensureInitialized();

  final armazenamento = Armazenamento();
  await armazenamento.inicializar();

  final provider = IptvProvider(armazenamento: armazenamento);
  await provider.inicializar();

  runApp(
    ChangeNotifierProvider<IptvProvider>.value(
      value: provider,
      child: const IptvApp(),
    ),
  );
}