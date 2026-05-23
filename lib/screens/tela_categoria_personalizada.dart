import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../state/iptv_provider.dart';
import '../theme/app_theme.dart';
import '../utils/layout.dart';
import '../widgets/item_canal.dart';
import 'tela_player.dart';

/// Mostra os canais de uma categoria criada pelo usuario.
///
/// Diferente da [TelaCategoria] (categoria da lista M3U), esta observa o
/// provider — adicionar/remover canais pelo seletor reflete na hora.
class TelaCategoriaPersonalizada extends StatelessWidget {
  final String idCategoria;
  const TelaCategoriaPersonalizada({super.key, required this.idCategoria});

  @override
  Widget build(BuildContext context) {
    final provider = context.watch<IptvProvider>();
    final categoria = provider.categoriaPersonalizadaPorId(idCategoria);

    // Categoria foi removida em outro lugar — sai dessa tela.
    if (categoria == null) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (Navigator.canPop(context)) Navigator.of(context).pop();
      });
      return const Scaffold(body: SizedBox.shrink());
    }

    final canais = categoria.canais;

    return Scaffold(
      appBar: AppBar(
        title: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(categoria.nome, maxLines: 1, overflow: TextOverflow.ellipsis),
            Text(
              '${canais.length} ${canais.length == 1 ? "canal" : "canais"}',
              style: tabular(Theme.of(context).textTheme.bodySmall),
            ),
          ],
        ),
        actions: [
          PopupMenuButton<String>(
            icon: const Icon(Icons.more_vert_rounded),
            onSelected: (acao) async {
              if (acao != 'excluir') return;
              final confirmar = await showDialog<bool>(
                context: context,
                builder: (_) => AlertDialog(
                  title: const Text('Excluir categoria?'),
                  content: Text(
                    'A categoria "${categoria.nome}" sera apagada. '
                    'Os canais continuam disponiveis na lista de origem.',
                  ),
                  actions: [
                    TextButton(
                      onPressed: () => Navigator.pop(context, false),
                      child: const Text('Cancelar'),
                    ),
                    FilledButton(
                      onPressed: () => Navigator.pop(context, true),
                      style: FilledButton.styleFrom(
                        backgroundColor: AppColors.error,
                      ),
                      child: const Text('Excluir'),
                    ),
                  ],
                ),
              );
              if (confirmar == true) {
                await provider.removerCategoriaPersonalizada(categoria.id);
              }
            },
            itemBuilder: (_) => const [
              PopupMenuItem(
                value: 'excluir',
                child: Row(
                  children: [
                    Icon(
                      Icons.delete_outline_rounded,
                      size: 18,
                      color: AppColors.error,
                    ),
                    SizedBox(width: AppSpacing.md),
                    Text(
                      'Excluir categoria',
                      style: TextStyle(color: AppColors.error),
                    ),
                  ],
                ),
              ),
            ],
          ),
        ],
      ),
      body: canais.isEmpty
          ? const _Vazio()
          : tabletBody(
              context,
              ListView.builder(
                itemExtent: 64,
                itemCount: canais.length,
                padding: const EdgeInsets.only(bottom: AppSpacing.lg),
                itemBuilder: (_, i) {
                  final c = canais[i];
                  return ItemCanal(
                    canal: c,
                    ehFavorito: provider.ehFavorito(c),
                    onTap: () {
                      provider.registrarVisualizacao(c);
                      Navigator.of(context).push(
                        MaterialPageRoute(
                          builder: (_) => TelaPlayer(canal: c),
                        ),
                      );
                    },
                    onToggleFavorito: () => provider.alternarFavorito(c),
                  );
                },
              ),
            ),
    );
  }
}

class _Vazio extends StatelessWidget {
  const _Vazio();

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: AppSpacing.xl),
      child: Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Container(
              width: 64,
              height: 64,
              decoration: BoxDecoration(
                color: AppColors.accentDim,
                borderRadius: BorderRadius.circular(AppRadius.base),
              ),
              child: const Icon(
                Icons.bookmark_add_rounded,
                size: 32,
                color: AppColors.accent,
              ),
            ),
            const SizedBox(height: AppSpacing.base),
            Text(
              'Categoria vazia',
              style: Theme.of(context).textTheme.titleMedium,
            ),
            const SizedBox(height: AppSpacing.sm),
            Text(
              'Adicione canais por aqui tocando no botao + ao lado da estrela em qualquer canal.',
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
