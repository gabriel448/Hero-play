import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../models/canal.dart';
import '../state/iptv_provider.dart';
import '../theme/app_theme.dart';

/// Abre o seletor de categorias personalizadas para [canal].
///
/// Bottom sheet onde o usuario marca/desmarca a quais categorias o canal
/// pertence. Funciona igual em celular, tablet e desktop.
Future<void> mostrarSeletorCategoria(BuildContext context, Canal canal) {
  return showModalBottomSheet(
    context: context,
    backgroundColor: AppColors.surface2,
    shape: const RoundedRectangleBorder(
      borderRadius: BorderRadius.vertical(top: Radius.circular(AppRadius.lg)),
    ),
    isScrollControlled: true,
    builder: (_) => _SeletorCategoria(canal: canal),
  );
}

/// Dialogo para digitar o nome de uma nova categoria.
/// Devolve o nome (nao vazio) ou null se cancelado.
Future<String?> dialogoCriarCategoria(BuildContext context) async {
  final controller = TextEditingController();
  final nome = await showDialog<String>(
    context: context,
    builder: (ctx) => AlertDialog(
      title: const Text('Nova categoria'),
      content: TextField(
        controller: controller,
        autofocus: true,
        textCapitalization: TextCapitalization.sentences,
        decoration: const InputDecoration(hintText: 'Nome da categoria'),
        onSubmitted: (v) => Navigator.pop(ctx, v.trim()),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(ctx),
          child: const Text('Cancelar'),
        ),
        FilledButton(
          onPressed: () => Navigator.pop(ctx, controller.text.trim()),
          child: const Text('Criar'),
        ),
      ],
    ),
  );
  controller.dispose();
  return (nome != null && nome.isNotEmpty) ? nome : null;
}

class _SeletorCategoria extends StatelessWidget {
  final Canal canal;
  const _SeletorCategoria({required this.canal});

  @override
  Widget build(BuildContext context) {
    final provider = context.watch<IptvProvider>();
    final categorias = provider.categoriasPersonalizadas;

    return SafeArea(
      child: Padding(
        padding: const EdgeInsets.fromLTRB(
          AppSpacing.base,
          AppSpacing.base,
          AppSpacing.base,
          AppSpacing.lg,
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Center(
              child: Container(
                width: 36,
                height: 4,
                margin: const EdgeInsets.only(bottom: AppSpacing.base),
                decoration: BoxDecoration(
                  color: AppColors.outlineSubtle,
                  borderRadius: BorderRadius.circular(AppRadius.pill),
                ),
              ),
            ),
            Text(
              'Adicionar a categoria',
              style: Theme.of(context).textTheme.titleMedium,
            ),
            const SizedBox(height: AppSpacing.base),

            // ── Criar nova categoria ──────────────────────────────────────
            InkWell(
              onTap: () async {
                final nome = await dialogoCriarCategoria(context);
                if (nome == null) return;
                final id = await provider.criarCategoriaPersonalizada(nome);
                await provider.adicionarCanalACategoria(id, canal);
              },
              borderRadius: BorderRadius.circular(AppRadius.sm),
              child: Padding(
                padding: const EdgeInsets.symmetric(
                  horizontal: AppSpacing.sm,
                  vertical: AppSpacing.md,
                ),
                child: Row(
                  children: [
                    const Icon(
                      Icons.add_rounded,
                      size: 20,
                      color: AppColors.accent,
                    ),
                    const SizedBox(width: AppSpacing.md),
                    Text(
                      'Nova categoria',
                      style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                            color: AppColors.accent,
                            fontWeight: FontWeight.w600,
                          ),
                    ),
                  ],
                ),
              ),
            ),

            if (categorias.isEmpty)
              Padding(
                padding: const EdgeInsets.symmetric(vertical: AppSpacing.lg),
                child: Center(
                  child: Text(
                    'Voce ainda nao criou categorias.',
                    style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                          color: AppColors.textSecondary,
                        ),
                  ),
                ),
              )
            else
              Flexible(
                child: ListView.builder(
                  shrinkWrap: true,
                  itemCount: categorias.length,
                  itemBuilder: (_, i) {
                    final cat = categorias[i];
                    final dentro = cat.contem(canal);
                    return _ItemSeletor(
                      nome: cat.nome,
                      quantidade: cat.canais.length,
                      marcado: dentro,
                      onTap: () => dentro
                          ? provider.removerCanalDeCategoria(cat.id, canal)
                          : provider.adicionarCanalACategoria(cat.id, canal),
                    );
                  },
                ),
              ),
          ],
        ),
      ),
    );
  }
}

class _ItemSeletor extends StatelessWidget {
  final String nome;
  final int quantidade;
  final bool marcado;
  final VoidCallback onTap;

  const _ItemSeletor({
    required this.nome,
    required this.quantidade,
    required this.marcado,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(AppRadius.sm),
      child: Padding(
        padding: const EdgeInsets.symmetric(
          horizontal: AppSpacing.sm,
          vertical: AppSpacing.md,
        ),
        child: Row(
          children: [
            Icon(
              marcado
                  ? Icons.check_circle_rounded
                  : Icons.circle_outlined,
              size: 22,
              color: marcado ? AppColors.accent : AppColors.textTertiary,
            ),
            const SizedBox(width: AppSpacing.md),
            Expanded(
              child: Text(
                nome,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                      color: marcado
                          ? AppColors.textPrimary
                          : AppColors.textSecondary,
                      fontWeight: marcado ? FontWeight.w600 : null,
                    ),
              ),
            ),
            Text(
              '$quantidade',
              style: Theme.of(context).textTheme.bodySmall?.copyWith(
                    color: AppColors.textTertiary,
                  ),
            ),
          ],
        ),
      ),
    );
  }
}
