import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_dotenv/flutter_dotenv.dart';
import 'package:media_kit/media_kit.dart';
import 'package:provider/provider.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'app.dart';
import 'services/armazenamento.dart';
import 'services/servico_conta.dart';
import 'services/servico_epg.dart';
import 'services/tmdb_service.dart';
import 'state/conta_provider.dart';
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

  // Supabase: contas e sincronizacao de listas. Se as credenciais nao
  // estiverem no .env, o app segue funcionando 100% local (sem conta).
  ServicoConta? servicoConta;
  final supabaseUrl = dotenv.get('SUPABASE_URL', fallback: '');
  final supabaseAnonKey = dotenv.get('SUPABASE_ANON_KEY', fallback: '');
  if (supabaseUrl.isNotEmpty && supabaseAnonKey.isNotEmpty) {
    await Supabase.initialize(url: supabaseUrl, anonKey: supabaseAnonKey);
    servicoConta = ServicoConta(Supabase.instance.client);
  }

  final armazenamento = Armazenamento();
  await armazenamento.inicializar();

  final servicoEpg = ServicoEpg(armazenamento: armazenamento);

  final provider = IptvProvider(
    armazenamento: armazenamento,
    epg: servicoEpg,
    conta: servicoConta,
  );
  await provider.inicializar();

  // Nao sincronizamos no startup: as listas ficam no cache local entre
  // sessoes. O sync acontece no login e quando o usuario toca em
  // "Atualizar listas" no gerenciador.

  // Perfis: carregados do disco aqui; nenhum e ativado ainda — a tela
  // "Quem esta assistindo" (TelaPerfis) decide qual perfil entra na sessao.
  final perfis = PerfilProvider(armazenamento, servicoConta)..inicializar();

  // As preferencias por perfil (idioma, auto-qualidade, ordenacoes) saem do
  // perfil ativo — por isso o PreferenciasProvider recebe o PerfilProvider.
  final preferencias = PreferenciasProvider(armazenamento, perfis);

  final tmdb = TmdbService(dotenv.get('TMDB_PROXY_URL', fallback: ''));

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
        ChangeNotifierProvider<ContaProvider>(
          create: (_) => ContaProvider(servicoConta),
        ),
      ],
      child: const IptvApp(),
    ),
  );
}