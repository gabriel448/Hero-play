import 'package:flutter/material.dart';
import 'package:flutter_dotenv/flutter_dotenv.dart';
import 'package:media_kit/media_kit.dart';
import 'package:provider/provider.dart';
import 'app.dart';
import 'services/armazenamento.dart';
import 'services/tmdb_service.dart';
import 'state/iptv_provider.dart';
import 'state/mini_player_provider.dart';
import 'state/preferencias_provider.dart';

/// Ponto de entrada da aplicacao.
///
/// Antes de chamar runApp(), inicializamos:
///  1. WidgetsFlutterBinding - obrigatorio se chamamos algo async antes de runApp.
///  2. MediaKit - inicializa libmpv para o player de video.
///  3. Hive (banco local) atraves do Armazenamento.
///  4. IptvProvider, que carrega listas/favoritos/historico salvos.
Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();

  await dotenv.load(fileName: '.env');
  MediaKit.ensureInitialized();

  final armazenamento = Armazenamento();
  await armazenamento.inicializar();

  final provider = IptvProvider(armazenamento: armazenamento);
  await provider.inicializar();

  final preferencias = PreferenciasProvider(armazenamento);

  final tmdb = TmdbService(dotenv.get('TMDB_API_KEY', fallback: ''));

  runApp(
    MultiProvider(
      providers: [
        ChangeNotifierProvider<IptvProvider>.value(value: provider),
        ChangeNotifierProvider<PreferenciasProvider>.value(value: preferencias),
        Provider<TmdbService>.value(value: tmdb),
        ChangeNotifierProvider<MiniPlayerProvider>(
          create: (_) => MiniPlayerProvider(),
        ),
      ],
      child: const IptvApp(),
    ),
  );
}