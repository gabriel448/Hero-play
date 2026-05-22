import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../models/lista_m3u.dart';
import '../state/iptv_provider.dart';
import '../theme/app_theme.dart';
import '../utils/layout.dart';
import '../utils/nav_keys.dart';
import '../screens/tela_favoritos.dart';
import '../screens/tela_historico.dart';
import '../screens/tela_importar.dart';
import '../screens/tela_selecao.dart';

/// Shell para PC: sidebar persistente + área de conteúdo com Navigator aninhado.
///
/// A sidebar mostra as listas IPTV salvas e atalhos (Favoritos, Histórico).
/// A área de conteúdo é um Navigator independente — sub-telas (TelaCanais,
/// TelaFilmes, TelaPlayer…) continuam usando push/pop normalmente dentro dele.
class ShellDesktop extends StatefulWidget {
  const ShellDesktop({super.key});

  @override
  State<ShellDesktop> createState() => _ShellDesktopState();
}

enum _Secao { lista, favoritos, historico }

class _ShellDesktopState extends State<ShellDesktop> {
  _Secao _secao = _Secao.lista;

  // ─── navegação do conteúdo ────────────────────────────────────────────────

  void _abrirLista(ListaM3U lista) {
    context.read<IptvProvider>().selecionarLista(lista);
    setState(() => _secao = _Secao.lista);
    _replacePrincipal(const TelaSelecao());
  }

  void _irFavoritos() {
    setState(() => _secao = _Secao.favoritos);
    _replacePrincipal(const TelaFavoritos());
  }

  void _irHistorico() {
    setState(() => _secao = _Secao.historico);
    _replacePrincipal(const TelaHistorico());
  }

  void _irImportar() {
    // Importar empilha sobre o que está mostrando (não troca a seção ativa).
    desktopContentNavigatorKey.currentState?.push(
      MaterialPageRoute(builder: (_) => const TelaImportar()),
    );
  }

  /// Substitui toda a pilha do Navigator de conteúdo por [screen].
  void _replacePrincipal(Widget screen) {
    desktopContentNavigatorKey.currentState?.pushAndRemoveUntil(
      MaterialPageRoute(builder: (_) => screen),
      (r) => false,
    );
  }

  // ─── build ────────────────────────────────────────────────────────────────

  @override
  Widget build(BuildContext context) {
    final provider = context.watch<IptvProvider>();

    return Scaffold(
      body: Row(
        children: [
          _SidebarDesktop(
            listas: provider.listas,
            listaAtiva: provider.listaAtiva,
            secao: _secao,
            onLista: _abrirLista,
            onFavoritos: _irFavoritos,
            onHistorico: _irHistorico,
            onImportar: _irImportar,
          ),
          const VerticalDivider(
            width: 1,
            thickness: 1,
            color: AppColors.divider,
          ),
          Expanded(
            child: Navigator(
              key: desktopContentNavigatorKey,
              onGenerateRoute: (_) => MaterialPageRoute(
                builder: (_) => const _BemVindoDesktop(),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

// ─── Tela inicial do conteúdo (nada selecionado ainda) ────────────────────────

class _BemVindoDesktop extends StatelessWidget {
  const _BemVindoDesktop();

  @override
  Widget build(BuildContext context) {
    final temListas = context.watch<IptvProvider>().listas.isNotEmpty;
    return Scaffold(
      body: Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Container(
              width: 80,
              height: 80,
              decoration: BoxDecoration(
                color: AppColors.surface1,
                borderRadius: BorderRadius.circular(AppRadius.lg),
              ),
              child: const Icon(
                Icons.playlist_play_rounded,
                size: 40,
                color: AppColors.accent,
              ),
            ),
            const SizedBox(height: AppSpacing.xl),
            Text(
              temListas ? 'Selecione uma lista' : 'Bem-vindo',
              style: Theme.of(context).textTheme.headlineMedium,
            ),
            const SizedBox(height: AppSpacing.sm),
            Text(
              temListas
                  ? 'Escolha uma lista no painel lateral para começar'
                  : 'Importe sua primeira lista IPTV pelo botão no painel lateral',
              style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                    color: AppColors.textSecondary,
                  ),
              textAlign: TextAlign.center,
            ),
          ],
        ),
      ),
    );
  }
}

// ─── Sidebar ──────────────────────────────────────────────────────────────────

class _SidebarDesktop extends StatelessWidget {
  final List<ListaM3U> listas;
  final ListaM3U? listaAtiva;
  final _Secao secao;
  final ValueChanged<ListaM3U> onLista;
  final VoidCallback onFavoritos;
  final VoidCallback onHistorico;
  final VoidCallback onImportar;

  const _SidebarDesktop({
    required this.listas,
    required this.listaAtiva,
    required this.secao,
    required this.onLista,
    required this.onFavoritos,
    required this.onHistorico,
    required this.onImportar,
  });

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      width: kDesktopSidebarWidth,
      child: ColoredBox(
        color: AppColors.surface1,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            // ── Cabeçalho ────────────────────────────────────────────────────
            Padding(
              padding: const EdgeInsets.fromLTRB(
                AppSpacing.lg,
                AppSpacing.xl,
                AppSpacing.lg,
                AppSpacing.lg,
              ),
              child: Row(
                children: [
                  const Icon(
                    Icons.live_tv_rounded,
                    color: AppColors.accent,
                    size: 20,
                  ),
                  const SizedBox(width: AppSpacing.sm),
                  Text(
                    'IPTV',
                    style: Theme.of(context).textTheme.titleLarge,
                  ),
                ],
              ),
            ),

            // ── Atalhos globais ───────────────────────────────────────────────
            _ItemSidebar(
              icon: Icons.star_rounded,
              label: 'Favoritos',
              ativo: secao == _Secao.favoritos,
              onTap: onFavoritos,
            ),
            _ItemSidebar(
              icon: Icons.history_rounded,
              label: 'Histórico',
              ativo: secao == _Secao.historico,
              onTap: onHistorico,
            ),
            Padding(
              padding: const EdgeInsets.symmetric(
                horizontal: AppSpacing.lg,
                vertical: AppSpacing.sm,
              ),
              child: const Divider(height: 1),
            ),

            // ── Label da seção listas ─────────────────────────────────────────
            Padding(
              padding: const EdgeInsets.fromLTRB(
                AppSpacing.lg,
                AppSpacing.xs,
                AppSpacing.lg,
                AppSpacing.xs,
              ),
              child: Text(
                'LISTAS',
                style: Theme.of(context).textTheme.labelSmall?.copyWith(
                      color: AppColors.textTertiary,
                      letterSpacing: 0.6,
                    ),
              ),
            ),

            // ── Lista de listas IPTV ──────────────────────────────────────────
            Expanded(
              child: listas.isEmpty
                  ? Padding(
                      padding: const EdgeInsets.all(AppSpacing.lg),
                      child: Text(
                        'Nenhuma lista importada',
                        style: Theme.of(context).textTheme.bodySmall?.copyWith(
                              color: AppColors.textTertiary,
                            ),
                        textAlign: TextAlign.center,
                      ),
                    )
                  : ListView.builder(
                      padding: const EdgeInsets.symmetric(
                        horizontal: AppSpacing.sm,
                        vertical: AppSpacing.xs,
                      ),
                      itemCount: listas.length,
                      itemBuilder: (_, i) {
                        final lista = listas[i];
                        final ativo = secao == _Secao.lista &&
                            listaAtiva?.id == lista.id;
                        return _ItemLista(
                          lista: lista,
                          ativo: ativo,
                          onTap: () => onLista(lista),
                        );
                      },
                    ),
            ),

            // ── Botão importar ────────────────────────────────────────────────
            const Divider(height: 1),
            Padding(
              padding: const EdgeInsets.all(AppSpacing.md),
              child: OutlinedButton.icon(
                onPressed: onImportar,
                icon: const Icon(Icons.add_rounded, size: 16),
                label: const Text('Importar lista'),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

// ─── Item de atalho (Favoritos / Histórico) ───────────────────────────────────

class _ItemSidebar extends StatelessWidget {
  final IconData icon;
  final String label;
  final bool ativo;
  final VoidCallback onTap;

  const _ItemSidebar({
    required this.icon,
    required this.label,
    required this.ativo,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(
        horizontal: AppSpacing.sm,
        vertical: 1,
      ),
      child: Material(
        color: ativo ? AppColors.accentDim : Colors.transparent,
        borderRadius: BorderRadius.circular(AppRadius.sm),
        child: InkWell(
          onTap: onTap,
          borderRadius: BorderRadius.circular(AppRadius.sm),
          child: Padding(
            padding: const EdgeInsets.symmetric(
              horizontal: AppSpacing.md,
              vertical: AppSpacing.sm,
            ),
            child: Row(
              children: [
                Icon(
                  icon,
                  size: 18,
                  color:
                      ativo ? AppColors.accent : AppColors.textSecondary,
                ),
                const SizedBox(width: AppSpacing.sm),
                Text(
                  label,
                  style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                        color: ativo
                            ? AppColors.textPrimary
                            : AppColors.textSecondary,
                        fontWeight:
                            ativo ? FontWeight.w600 : FontWeight.w500,
                      ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

// ─── Item de lista IPTV na sidebar ───────────────────────────────────────────

class _ItemLista extends StatelessWidget {
  final ListaM3U lista;
  final bool ativo;
  final VoidCallback onTap;

  const _ItemLista({
    required this.lista,
    required this.ativo,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return Material(
      color: ativo ? AppColors.accentDim : Colors.transparent,
      borderRadius: BorderRadius.circular(AppRadius.sm),
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(AppRadius.sm),
        child: Padding(
          padding: const EdgeInsets.symmetric(
            horizontal: AppSpacing.md,
            vertical: AppSpacing.sm,
          ),
          child: Row(
            children: [
              // Indicador ativo
              if (ativo)
                Container(
                  width: 3,
                  height: 32,
                  margin: const EdgeInsets.only(right: AppSpacing.sm),
                  decoration: BoxDecoration(
                    color: AppColors.accent,
                    borderRadius: BorderRadius.circular(AppRadius.pill),
                  ),
                )
              else
                const SizedBox(width: 11),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      lista.nome,
                      style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                            color: ativo
                                ? AppColors.textPrimary
                                : AppColors.textSecondary,
                            fontWeight:
                                ativo ? FontWeight.w600 : FontWeight.w500,
                          ),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                    Text(
                      '${lista.totalCanais} canais',
                      style: Theme.of(context).textTheme.bodySmall?.copyWith(
                            color: ativo
                                ? AppColors.accentBright
                                : AppColors.textTertiary,
                          ),
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
