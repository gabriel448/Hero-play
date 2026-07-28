import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'screens/tela_ativacao.dart';
import 'screens/tela_importando_listas.dart';
import 'screens/tela_inicial.dart';
import 'screens/tela_perfis.dart';
import 'state/dispositivo_provider.dart';
import 'state/iptv_provider.dart';
import 'state/perfil_provider.dart';
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
/// (ativacao → download da lista → perfis → app) em vez de substituicao abrupta.
///
/// Nao existe login: a identidade e o proprio aparelho (MAC+Key). Sem lista
/// vinculada nem lista adicionada a mao, o app abre no estado NEUTRO
/// ([TelaAtivacao]) — ver conformidade de loja.
class _TelaRaiz extends StatelessWidget {
  const _TelaRaiz();

  @override
  Widget build(BuildContext context) {
    final prontoDispositivo =
        context.select<DispositivoProvider, bool>((d) => d.pronto);
    final temListaNaNuvem =
        context.select<DispositivoProvider, bool>((d) => d.temLista);
    final temListaLocal =
        context.select<IptvProvider, bool>((p) => p.listas.isNotEmpty);
    final baixandoPrimeiraVez =
        context.select<IptvProvider, bool>((p) => p.primeiroDownload);
    final perfilConfirmado =
        context.select<PerfilProvider, bool>((p) => p.perfilConfirmado);

    // Enquanto a identidade nao foi resolvida, nao decidimos nada (evita
    // piscar a tela de ativacao para quem ja tem lista).
    final precisaAtivar =
        prontoDispositivo && !temListaNaNuvem && !temListaLocal;

    final Widget tela;
    if (!prontoDispositivo && !temListaLocal) {
      // Aparelho novo: espera a consulta de ativacao antes de decidir, senao o
      // usuario passaria pelos perfis e cairia numa home vazia por um instante.
      tela = const _TelaAguardando();
    } else if (precisaAtivar) {
      tela = const TelaAtivacao();
    } else if (baixandoPrimeiraVez) {
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

/// Splash curto do boot: so aparece no primeiro uso, enquanto a identidade do
/// aparelho e resolvida e a nuvem e consultada (8s no pior caso, offline-first).
class _TelaAguardando extends StatelessWidget {
  const _TelaAguardando();

  @override
  Widget build(BuildContext context) {
    return const Scaffold(
      body: Center(child: CircularProgressIndicator()),
    );
  }
}
