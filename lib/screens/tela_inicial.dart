import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../models/lista_m3u.dart';
import '../state/iptv_provider.dart';
import '../theme/app_theme.dart';
import 'tela_selecao.dart';
import 'tela_favoritos.dart';
import 'tela_historico.dart';
import 'tela_importar.dart';

/// Tela inicial: lista as listas IPTV salvas e atalhos para favoritos / historico.
///
/// Empty state composto - nao basta colocar so um texto. Quando vazio, mostra
/// um "primeiro passo" claro com CTA grande, dispensando o FAB.
class TelaInicial extends StatelessWidget {
  const TelaInicial({super.key});

  @override
  Widget build(BuildContext context) {
    final provider = context.watch<IptvProvider>();
    final listas = provider.listas;
    final temListas = listas.isNotEmpty;

    return Scaffold(
      body: SafeArea(
        child: temListas
            ? _BodyComListas(listas: listas)
            : const _BodyVazio(),
      ),
      floatingActionButton: temListas
          ? FloatingActionButton.extended(
              onPressed: () => Navigator.of(context).push(
                MaterialPageRoute(builder: (_) => const TelaImportar()),
              ),
              icon: const Icon(Icons.add_rounded),
              label: const Text('Importar lista'),
            )
          : null,
    );
  }
}

class _BodyComListas extends StatelessWidget {
  final List<ListaM3U> listas;
  const _BodyComListas({required this.listas});

  @override
  Widget build(BuildContext context) {
    return CustomScrollView(
      slivers: [
        SliverToBoxAdapter(
          child: Padding(
            padding: const EdgeInsets.fromLTRB(
              AppSpacing.lg,
              AppSpacing.lg,
              AppSpacing.lg,
              AppSpacing.sm,
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'Boa noite',
                  style: Theme.of(context).textTheme.bodySmall?.copyWith(
                        color: AppColors.textTertiary,
                      ),
                ),
                const SizedBox(height: 2),
                Text(
                  'Minhas listas',
                  style: Theme.of(context).textTheme.headlineMedium,
                ),
              ],
            ),
          ),
        ),
        SliverToBoxAdapter(
          child: Padding(
            padding: const EdgeInsets.fromLTRB(
              AppSpacing.lg,
              AppSpacing.base,
              AppSpacing.lg,
              AppSpacing.base,
            ),
            child: Row(
              children: [
                Expanded(
                  child: _AtalhoCard(
                    icone: Icons.star_rounded,
                    iconColor: AppColors.accent,
                    titulo: 'Favoritos',
                    onTap: () => Navigator.of(context).push(
                      MaterialPageRoute(builder: (_) => const TelaFavoritos()),
                    ),
                  ),
                ),
                const SizedBox(width: AppSpacing.md),
                Expanded(
                  child: _AtalhoCard(
                    icone: Icons.history_rounded,
                    iconColor: AppColors.textPrimary,
                    titulo: 'Historico',
                    onTap: () => Navigator.of(context).push(
                      MaterialPageRoute(builder: (_) => const TelaHistorico()),
                    ),
                  ),
                ),
              ],
            ),
          ),
        ),
        SliverPadding(
          padding: const EdgeInsets.fromLTRB(
            AppSpacing.lg,
            AppSpacing.base,
            AppSpacing.lg,
            AppSpacing.sm,
          ),
          sliver: SliverToBoxAdapter(
            child: Text(
              'LISTAS',
              style: Theme.of(context).textTheme.labelSmall?.copyWith(
                    color: AppColors.textTertiary,
                  ),
            ),
          ),
        ),
        SliverList.separated(
          itemCount: listas.length,
          separatorBuilder: (_, _) => const Padding(
            padding: EdgeInsets.symmetric(horizontal: AppSpacing.lg),
            child: Divider(height: 1),
          ),
          itemBuilder: (_, i) => _ItemLista(lista: listas[i]),
        ),
        // Padding para o FAB nao cobrir o ultimo item.
        const SliverToBoxAdapter(child: SizedBox(height: 88)),
      ],
    );
  }
}

class _AtalhoCard extends StatelessWidget {
  final IconData icone;
  final Color iconColor;
  final String titulo;
  final VoidCallback onTap;

  const _AtalhoCard({
    required this.icone,
    required this.iconColor,
    required this.titulo,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return Material(
      color: AppColors.surface1,
      borderRadius: BorderRadius.circular(AppRadius.base),
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(AppRadius.base),
        child: Padding(
          padding: const EdgeInsets.symmetric(
            horizontal: AppSpacing.base,
            vertical: AppSpacing.base,
          ),
          child: Row(
            children: [
              Icon(icone, color: iconColor, size: 20),
              const SizedBox(width: AppSpacing.sm),
              Text(
                titulo,
                style: Theme.of(context).textTheme.titleSmall,
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _ItemLista extends StatelessWidget {
  final ListaM3U lista;
  const _ItemLista({required this.lista});

  @override
  Widget build(BuildContext context) {
    final origem = lista.origem == OrigemLista.url ? 'URL' : 'Arquivo';
    return InkWell(
      onTap: () {
        context.read<IptvProvider>().selecionarLista(lista);
        Navigator.of(context).push(
          MaterialPageRoute(builder: (_) => const TelaSelecao()),
        );
      },
      child: Padding(
        padding: const EdgeInsets.symmetric(
          horizontal: AppSpacing.lg,
          vertical: AppSpacing.md,
        ),
        child: Row(
          children: [
            Container(
              width: 48,
              height: 48,
              decoration: BoxDecoration(
                color: AppColors.surface1,
                borderRadius: BorderRadius.circular(AppRadius.base),
                border: Border.all(color: AppColors.divider),
              ),
              alignment: Alignment.center,
              child: Text(
                '${lista.totalCanais > 9999 ? "${lista.totalCanais ~/ 1000}k" : lista.totalCanais}',
                style: tabular(
                  Theme.of(context).textTheme.labelMedium?.copyWith(
                        color: AppColors.textPrimary,
                      ),
                ),
              ),
            ),
            const SizedBox(width: AppSpacing.base),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    lista.nome,
                    style: Theme.of(context).textTheme.titleSmall,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
                  const SizedBox(height: 2),
                  Text(
                    '$origem · ${lista.totalCanais} canais',
                    style: Theme.of(context).textTheme.bodySmall,
                  ),
                ],
              ),
            ),
            _MenuLista(lista: lista),
          ],
        ),
      ),
    );
  }
}

class _MenuLista extends StatelessWidget {
  final ListaM3U lista;
  const _MenuLista({required this.lista});

  @override
  Widget build(BuildContext context) {
    return PopupMenuButton<String>(
      icon: const Icon(
        Icons.more_vert_rounded,
        color: AppColors.textSecondary,
        size: 20,
      ),
      onSelected: (acao) => _executar(context, acao),
      itemBuilder: (_) => [
        if (lista.origem == OrigemLista.url)
          const PopupMenuItem(
            value: 'atualizar',
            child: Row(
              children: [
                Icon(Icons.refresh_rounded, size: 18),
                SizedBox(width: AppSpacing.md),
                Text('Atualizar'),
              ],
            ),
          ),
        const PopupMenuItem(
          value: 'remover',
          child: Row(
            children: [
              Icon(Icons.delete_outline_rounded,
                  size: 18, color: AppColors.error),
              SizedBox(width: AppSpacing.md),
              Text('Remover', style: TextStyle(color: AppColors.error)),
            ],
          ),
        ),
      ],
    );
  }

  Future<void> _executar(BuildContext context, String acao) async {
    final provider = context.read<IptvProvider>();
    final messenger = ScaffoldMessenger.of(context);

    if (acao == 'atualizar') {
      await provider.atualizarLista(lista);
      if (provider.erro != null) {
        messenger.showSnackBar(SnackBar(content: Text(provider.erro!)));
        provider.limparErro();
      } else {
        messenger
            .showSnackBar(const SnackBar(content: Text('Lista atualizada')));
      }
    } else if (acao == 'remover') {
      final confirmar = await showDialog<bool>(
        context: context,
        builder: (_) => AlertDialog(
          title: const Text('Remover lista?'),
          content: Text('A lista "${lista.nome}" sera apagada.'),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(context, false),
              child: const Text('Cancelar'),
            ),
            FilledButton(
              onPressed: () => Navigator.pop(context, true),
              style:
                  FilledButton.styleFrom(backgroundColor: AppColors.error),
              child: const Text('Remover'),
            ),
          ],
        ),
      );
      if (confirmar == true) await provider.removerLista(lista);
    }
  }
}

class _BodyVazio extends StatelessWidget {
  const _BodyVazio();

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: AppSpacing.xl),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          const Spacer(),
          Center(
            child: Container(
              width: 88,
              height: 88,
              decoration: BoxDecoration(
                color: AppColors.surface1,
                borderRadius: BorderRadius.circular(AppRadius.lg),
              ),
              child: const Icon(
                Icons.playlist_play_rounded,
                size: 44,
                color: AppColors.accent,
              ),
            ),
          ),
          const SizedBox(height: AppSpacing.xl),
          Text(
            'Bem-vindo',
            style: Theme.of(context).textTheme.headlineMedium,
            textAlign: TextAlign.center,
          ),
          const SizedBox(height: AppSpacing.sm),
          Text(
            'Importe sua primeira lista IPTV para comecar a assistir',
            style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                  color: AppColors.textSecondary,
                ),
            textAlign: TextAlign.center,
          ),
          const SizedBox(height: AppSpacing.xxl),
          FilledButton.icon(
            onPressed: () => Navigator.of(context).push(
              MaterialPageRoute(builder: (_) => const TelaImportar()),
            ),
            icon: const Icon(Icons.add_rounded),
            label: const Text('Importar lista M3U'),
            style: FilledButton.styleFrom(
              padding: const EdgeInsets.symmetric(vertical: AppSpacing.base),
            ),
          ),
          const Spacer(flex: 2),
        ],
      ),
    );
  }
}