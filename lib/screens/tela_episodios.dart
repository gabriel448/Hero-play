import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../models/canal.dart';
import '../models/serie.dart';
import '../state/iptv_provider.dart';
import '../theme/app_theme.dart';
import 'tela_player.dart';

/// Tela de episodios de uma serie agrupada.
/// Exibe episodios agrupados por temporada com header visual por temporada.
class TelaEpisodios extends StatelessWidget {
  final Serie serie;
  const TelaEpisodios({super.key, required this.serie});

  @override
  Widget build(BuildContext context) {
    final provider = context.watch<IptvProvider>();

    final Map<int, List<Canal>> porTemporada = {};
    for (final ep in serie.episodios) {
      (porTemporada[Serie.seasonOf(ep)] ??= []).add(ep);
    }
    final temporadas = porTemporada.keys.toList()..sort();

    // Lista plana: int = marcador de temporada, Canal = episodio
    final items = <Object>[];
    for (final t in temporadas) {
      items.add(t);
      items.addAll(porTemporada[t]!);
    }

    return Scaffold(
      appBar: AppBar(
        title: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(serie.nome, overflow: TextOverflow.ellipsis),
            Text(
              _descricao(temporadas.length, serie.totalEpisodios),
              style: const TextStyle(fontSize: 11, color: Colors.white70),
            ),
          ],
        ),
      ),
      body: ListView.builder(
        padding: const EdgeInsets.only(bottom: AppSpacing.lg),
        itemCount: items.length,
        itemBuilder: (_, i) {
          final item = items[i];
          if (item is int) {
            return _HeaderTemporada(
              numero: item,
              total: porTemporada[item]!.length,
            );
          }
          final ep = item as Canal;
          return _ItemEpisodio(
            episodio: ep,
            ehFavorito: provider.ehFavorito(ep),
            onTap: () {
              provider.registrarVisualizacao(ep);
              Navigator.of(context).push(
                MaterialPageRoute(builder: (_) => TelaPlayer(canal: ep)),
              );
            },
            onToggleFavorito: () => provider.alternarFavorito(ep),
          );
        },
      ),
    );
  }

  static String _descricao(int t, int e) {
    final ts = t == 1 ? '1 temporada' : '$t temporadas';
    final es = e == 1 ? '1 episódio' : '$e episódios';
    return '$ts · $es';
  }
}

class _HeaderTemporada extends StatelessWidget {
  final int numero;
  final int total;
  const _HeaderTemporada({required this.numero, required this.total});

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(
        AppSpacing.lg,
        AppSpacing.lg,
        AppSpacing.lg,
        AppSpacing.xs,
      ),
      child: Row(
        children: [
          Container(
            padding: const EdgeInsets.symmetric(
              horizontal: AppSpacing.sm,
              vertical: 2,
            ),
            decoration: BoxDecoration(
              color: AppColors.accentDim,
              borderRadius: BorderRadius.circular(AppRadius.sm),
            ),
            child: Text(
              numero == 0 ? 'ESPECIAIS' : 'TEMPORADA $numero',
              style: Theme.of(context).textTheme.labelSmall?.copyWith(
                    color: AppColors.accentBright,
                    letterSpacing: 0.5,
                  ),
            ),
          ),
          const SizedBox(width: AppSpacing.sm),
          Text(
            '$total ep.',
            style: tabular(
              Theme.of(context).textTheme.bodySmall?.copyWith(
                    color: AppColors.textTertiary,
                  ),
            ),
          ),
        ],
      ),
    );
  }
}

class _ItemEpisodio extends StatelessWidget {
  final Canal episodio;
  final bool ehFavorito;
  final VoidCallback onTap;
  final VoidCallback onToggleFavorito;

  const _ItemEpisodio({
    required this.episodio,
    required this.ehFavorito,
    required this.onTap,
    required this.onToggleFavorito,
  });

  @override
  Widget build(BuildContext context) {
    return InkWell(
      onTap: onTap,
      child: Padding(
        padding: const EdgeInsets.symmetric(
          horizontal: AppSpacing.lg,
          vertical: AppSpacing.sm,
        ),
        child: Row(
          children: [
            Container(
              width: 80,
              height: 46,
              decoration: BoxDecoration(
                color: AppColors.surface2,
                borderRadius: BorderRadius.circular(AppRadius.sm),
              ),
              child: const Icon(
                Icons.play_circle_outline_rounded,
                color: AppColors.textTertiary,
                size: 22,
              ),
            ),
            const SizedBox(width: AppSpacing.base),
            Expanded(
              child: Text(
                Serie.episodeLabel(episodio),
                style: Theme.of(context).textTheme.bodyMedium,
                maxLines: 2,
                overflow: TextOverflow.ellipsis,
              ),
            ),
            const SizedBox(width: AppSpacing.xs),
            GestureDetector(
              onTap: onToggleFavorito,
              child: Padding(
                padding: const EdgeInsets.all(AppSpacing.xs),
                child: Icon(
                  ehFavorito ? Icons.star_rounded : Icons.star_outline_rounded,
                  size: 20,
                  color: ehFavorito ? AppColors.accent : AppColors.textTertiary,
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
