import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../state/iptv_provider.dart';
import '../theme/app_theme.dart';
import '../utils/layout.dart';
import '../widgets/item_canal.dart';
import 'tela_player.dart';

/// Canais favoritados pelo usuario. Persistem entre sessoes via Hive.
class TelaFavoritos extends StatelessWidget {
  const TelaFavoritos({super.key});

  @override
  Widget build(BuildContext context) {
    final provider = context.watch<IptvProvider>();
    final favoritos = provider.favoritos;

    return Scaffold(
      appBar: AppBar(
        title: const Text('Favoritos'),
      ),
      body: favoritos.isEmpty
          ? const _Vazio()
          : tabletBody(
              context,
              ListView.builder(
                itemExtent: 64,
                itemCount: favoritos.length,
                padding: const EdgeInsets.only(bottom: AppSpacing.lg),
                itemBuilder: (_, i) {
                  final c = favoritos[i];
                  return ItemCanal(
                    canal: c,
                    ehFavorito: true,
                    mostrarGrupo: true,
                    onTap: () {
                      provider.registrarVisualizacao(c);
                      Navigator.of(context).push(
                        MaterialPageRoute(
                            builder: (_) => TelaPlayer(canal: c)),
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
                Icons.star_rounded,
                size: 32,
                color: AppColors.accent,
              ),
            ),
            const SizedBox(height: AppSpacing.base),
            Text(
              'Sem favoritos ainda',
              style: Theme.of(context).textTheme.titleMedium,
            ),
            const SizedBox(height: AppSpacing.sm),
            Text(
              'Toque na estrela ao lado de um canal para favorita-lo. Ele ficara disponivel aqui mesmo sem a lista.',
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