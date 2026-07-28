import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_dotenv/flutter_dotenv.dart';
import 'package:media_kit/media_kit.dart';
import 'package:provider/provider.dart';
import 'app.dart';
import 'services/armazenamento.dart';
import 'services/dispositivo.dart';
import 'services/servico_epg.dart';
import 'services/tmdb_service.dart';
import 'state/dispositivo_provider.dart';
import 'state/iptv_provider.dart';
import 'state/mini_player_provider.dart';
import 'state/perfil_provider.dart';
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

  // Tela cheia edge-to-edge: o conteudo ocupa a tela toda, por baixo das barras
  // do sistema (transparentes). A barra de navegacao (rodape) e escondida de
  // forma nativa na MainActivity (modo transitorio, sem layout shift) — aqui so
  // dizemos ao Flutter para desenhar edge-to-edge e deixamos as barras claras.
  SystemChrome.setEnabledSystemUIMode(SystemUiMode.edgeToEdge);
  SystemChrome.setSystemUIOverlayStyle(const SystemUiOverlayStyle(
    statusBarColor: Colors.transparent,
    statusBarIconBrightness: Brightness.light,
    statusBarBrightness: Brightness.dark,
    systemNavigationBarColor: Colors.transparent,
    systemNavigationBarContrastEnforced: false,
  ));

  await dotenv.load(fileName: '.env');
  MediaKit.ensureInitialized();

  final armazenamento = Armazenamento();
  await armazenamento.inicializar();

  // Identidade do APARELHO (MAC + Key), no lugar de conta por e-mail. Tudo o
  // que o usuario cria (perfis, favoritos, historico, progresso) e LOCAL.
  final dispositivo = Dispositivo(
    armazenamento,
    api: dotenv.get('ATIVACAO_API', fallback: ''),
    anonKey: dotenv.get('ATIVACAO_ANON_KEY', fallback: ''),
  );

  final servicoEpg = ServicoEpg(armazenamento: armazenamento);

  final provider = IptvProvider(
    armazenamento: armazenamento,
    epg: servicoEpg,
    dispositivo: dispositivo,
  );
  await provider.inicializar();

  // A lista fica no cache local entre sessoes: o boot NAO re-baixa. A consulta
  // de ativacao roda em background (abaixo) e so baixa se a playlist do painel
  // mudou; "Atualizar" continua sendo o caminho manual.
  final dispositivoProvider = DispositivoProvider(dispositivo);
  unawaited(dispositivoProvider.inicializar().then((_) {
    return provider.sincronizarComDispositivo();
  }));

  // Perfis: carregados do disco aqui; nenhum e ativado ainda — a tela
  // "Quem esta assistindo" (TelaPerfis) decide qual perfil entra na sessao.
  final perfis = PerfilProvider(armazenamento)..inicializar();

  // As preferencias por perfil (idioma, auto-qualidade, ordenacoes) saem do
  // perfil ativo — por isso o PreferenciasProvider recebe o PerfilProvider.
  final preferencias = PreferenciasProvider(armazenamento, perfis);

  final tmdb = TmdbService(
    dotenv.get('TMDB_PROXY_URL', fallback: ''),
    armazenamento: armazenamento,
  );

  runApp(
    MultiProvider(
      providers: [
        ChangeNotifierProvider<IptvProvider>.value(value: provider),
        ChangeNotifierProvider<PerfilProvider>.value(value: perfis),
        ChangeNotifierProvider<PreferenciasProvider>.value(value: preferencias),
        ChangeNotifierProvider<ServicoEpg>.value(value: servicoEpg),
        Provider<TmdbService>.value(value: tmdb),
        ChangeNotifierProvider<MiniPlayerProvider>(
          create: (_) => MiniPlayerProvider(),
        ),
        ChangeNotifierProvider<DispositivoProvider>.value(
          value: dispositivoProvider,
        ),
      ],
      child: const IptvApp(),
    ),
  );
}