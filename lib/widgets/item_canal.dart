import 'package:flutter/material.dart';
import '../models/canal.dart';
import '../theme/app_theme.dart';
import 'seletor_categoria.dart';

/// Linha de canal. Material denso, hierarquia clara, sem cards desnecessarios.
///
/// Cada linha tem 64px de altura quando exibe grupo (mostrarGrupo=true),
/// 56px caso contrario. Logo a esquerda, nome dominante, accent na estrela.
class ItemCanal extends StatelessWidget {
  final Canal canal;
  final bool ehFavorito;
  final VoidCallback onTap;
  final VoidCallback onToggleFavorito;
  final bool mostrarGrupo;

  const ItemCanal({
    super.key,
    required this.canal,
    required this.ehFavorito,
    required this.onTap,
    required this.onToggleFavorito,
    this.mostrarGrupo = false,
  });

  @override
  Widget build(BuildContext context) {
    final ehLive = canal.tipo == TipoCanal.aoVivo;
    return InkWell(
      onTap: onTap,
      child: Padding(
        padding: const EdgeInsets.fromLTRB(
          AppSpacing.base,
          AppSpacing.sm,
          AppSpacing.sm,
          AppSpacing.sm,
        ),
        child: Row(
          children: [
            _Logo(url: canal.logoUrl, ehLive: ehLive),
            const SizedBox(width: AppSpacing.md),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Text(
                    canal.nome,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: Theme.of(context).textTheme.titleSmall,
                  ),
                  if (mostrarGrupo) ...[
                    const SizedBox(height: 2),
                    Text(
                      canal.grupo,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: Theme.of(context).textTheme.bodySmall,
                    ),
                  ],
                ],
              ),
            ),
            if (canal.agrupado) ...[
              _BadgeQualidades(quantidade: canal.variantes.length),
              const SizedBox(width: AppSpacing.xs),
            ],
            IconButton(
              icon: const Icon(
                Icons.playlist_add_rounded,
                color: AppColors.textTertiary,
                size: 22,
              ),
              tooltip: 'Adicionar a categoria',
              onPressed: () => mostrarSeletorCategoria(context, canal),
              splashRadius: 22,
            ),
            IconButton(
              icon: Icon(
                ehFavorito ? Icons.star_rounded : Icons.star_outline_rounded,
                color: ehFavorito ? AppColors.accent : AppColors.textTertiary,
                size: 22,
              ),
              tooltip: ehFavorito
                  ? 'Remover dos favoritos'
                  : 'Adicionar aos favoritos',
              onPressed: onToggleFavorito,
              splashRadius: 22,
            ),
          ],
        ),
      ),
    );
  }
}

/// Selo discreto indicando que o canal reune varias qualidades.
class _BadgeQualidades extends StatelessWidget {
  final int quantidade;
  const _BadgeQualidades({required this.quantidade});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 3),
      decoration: BoxDecoration(
        color: AppColors.surface2,
        borderRadius: BorderRadius.circular(AppRadius.sm),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          const Icon(
            Icons.high_quality_rounded,
            size: 13,
            color: AppColors.textTertiary,
          ),
          const SizedBox(width: 3),
          Text(
            '$quantidade',
            style: Theme.of(context).textTheme.labelSmall?.copyWith(
                  color: AppColors.textTertiary,
                ),
          ),
        ],
      ),
    );
  }
}

/// Logo do canal. Fallback bonito para canais sem logo ou com URL quebrada.
class _Logo extends StatelessWidget {
  final String? url;
  final bool ehLive;
  const _Logo({this.url, required this.ehLive});

  @override
  Widget build(BuildContext context) {
    const tamanho = 44.0;
    final placeholder = Container(
      width: tamanho,
      height: tamanho,
      decoration: BoxDecoration(
        color: AppColors.surface2,
        borderRadius: BorderRadius.circular(AppRadius.sm),
      ),
      child: Icon(
        ehLive ? Icons.live_tv_rounded : Icons.movie_creation_rounded,
        color: AppColors.textTertiary,
        size: 20,
      ),
    );

    if (url == null || url!.isEmpty) return placeholder;

    return ClipRRect(
      borderRadius: BorderRadius.circular(AppRadius.sm),
      child: Image.network(
        url!,
        width: tamanho,
        height: tamanho,
        fit: BoxFit.cover,
        errorBuilder: (_, _, _) => placeholder,
        loadingBuilder: (context, child, progress) {
          if (progress == null) return child;
          return placeholder;
        },
      ),
    );
  }
}