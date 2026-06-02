import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'screens/tela_importando_listas.dart';
import 'screens/tela_inicial.dart';
import 'screens/tela_login.dart';
import 'screens/tela_onboarding.dart';
import 'state/conta_provider.dart';
import 'state/iptv_provider.dart';
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
/// (onboarding → login → app) em vez de substituicao abrupta.
class _TelaRaiz extends StatelessWidget {
  const _TelaRaiz();

  @override
  Widget build(BuildContext context) {
    final temIdioma =
        context.select<PreferenciasProvider, bool>((p) => p.idiomaDefinido);
    final pulouLogin =
        context.select<PreferenciasProvider, bool>((p) => p.pulouLogin);
    final disponivel =
        context.select<ContaProvider, bool>((c) => c.disponivel);
    final logado = context.select<ContaProvider, bool>((c) => c.estaLogado);
    final primeiraSync =
        context.select<IptvProvider, bool>((p) => p.primeiraSync);

    final precisaLogin = disponivel && !logado && !pulouLogin;
    final importandoPrimeiraVez = logado && primeiraSync;

    final Widget tela;
    if (!temIdioma) {
      tela = const TelaOnboarding();
    } else if (precisaLogin) {
      tela = const TelaLogin();
    } else if (importandoPrimeiraVez) {
      tela = const TelaImportandoListas();
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
