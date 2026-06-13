import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'screens/tela_importando_listas.dart';
import 'screens/tela_inicial.dart';
import 'screens/tela_login.dart';
import 'screens/tela_perfis.dart';
import 'state/conta_provider.dart';
import 'state/iptv_provider.dart';
import 'state/perfil_provider.dart';
import 'state/preferencias_provider.dart';
import 'theme/app_theme.dart';
import 'utils/nav_keys.dart';
import 'widgets/mini_player_overlay.dart';

class IptvApp extends StatelessWidget {
  const IptvApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'Hero Play',
      debugShowCheckedModeBanner: false,
      navigatorKey: rootNavigatorKey,
      theme: AppTheme.dark,
      themeMode: ThemeMode.dark,
      builder: (context, child) => MiniPlayerOverlay(child: child!),
      home: const _TelaRaiz(),
    );
  }
}

/// Gerencia qual tela raiz exibir com base no estado dos providers.
/// Usa [AnimatedSwitcher] para crossfade suave entre as transicoes de estado
/// (login → importacao → perfis → app) em vez de substituicao abrupta.
class _TelaRaiz extends StatelessWidget {
  const _TelaRaiz();

  @override
  Widget build(BuildContext context) {
    final pulouLogin =
        context.select<PreferenciasProvider, bool>((p) => p.pulouLogin);
    final disponivel =
        context.select<ContaProvider, bool>((c) => c.disponivel);
    final logado = context.select<ContaProvider, bool>((c) => c.estaLogado);
    final aguardandoMfa =
        context.select<ContaProvider, bool>((c) => c.aguardandoMfa);
    final resolvendoLogin =
        context.select<ContaProvider, bool>((c) => c.resolvendoLogin);
    final primeiraSync =
        context.select<IptvProvider, bool>((p) => p.primeiraSync);
    final perfilConfirmado =
        context.select<PerfilProvider, bool>((p) => p.perfilConfirmado);

    // Mantem na tela de login enquanto o 2o fator (MFA) nao foi cumprido — mesmo
    // com sessao AAL1 ativa — e durante a checagem logo apos logar.
    final precisaLogin = disponivel &&
        !pulouLogin &&
        (!logado || aguardandoMfa || resolvendoLogin);
    final importandoPrimeiraVez = logado && primeiraSync;

    final Widget tela;
    if (precisaLogin) {
      tela = const TelaLogin();
    } else if (importandoPrimeiraVez) {
      tela = const TelaImportandoListas();
    } else if (!perfilConfirmado) {
      // "Quem esta assistindo?" — sempre exibida ao abrir o app, antes da home.
      tela = const TelaPerfis();
    } else {
      tela = const TelaInicial();
    }

    return AnimatedSwitcher(
      duration: const Duration(milliseconds: 320),
      switchInCurve: Curves.easeOut,
      switchOutCurve: Curves.easeIn,
      transitionBuilder: (child, animation) => FadeTransition(
        opacity: animation,
        child: child,
      ),
      child: KeyedSubtree(
        key: ValueKey(tela.runtimeType),
        child: tela,
      ),
    );
  }
}
