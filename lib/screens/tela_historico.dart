import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../state/iptv_provider.dart';
import '../theme/app_theme.dart';
import '../utils/layout.dart';
import '../widgets/item_canal.dart';
import 'tela_player.dart';

/// Historico de canais assistidos (limite 50 itens, dos mais recentes).
class TelaHistorico extends StatelessWidget {
  const TelaHistorico({super.key});

  @override
  Widget build(BuildContext context) {
    final provider = context.watch<IptvProvider>();
    final historico = provider.historico;

    return Scaffold(
      appBar: AppBar(
        title: const Text('Historico'),
        actions: [
          if (historico.isNotEmpty)
            IconButton(
              icon: const Icon(Icons.delete_sweep_outlined, size: 22),
              tooltip: 'Limpar historico',
              onPressed: () => _confirmarLimpeza(context),
            ),
        ],
      ),
      body: historico.isEmpty
          ? const _Vazio()
          : tabletBody(
              context,
              ListView.builder(
                itemExtent: 64,
                itemCount: historico.length,
                padding: const EdgeInsets.only(bottom: AppSpacing.lg),
                itemBuilder: (_, i) {
                  final item = historico[i];
                  return ItemCanal(
                    canal: item.canal,
                    ehFavorito: provider.ehFavorito(item.canal),
                    mostrarGrupo: true,
                    onTap: () {
                      provider.registrarVisualizacao(item.canal);
                      Navigator.of(context).push(
                        MaterialPageRoute(
                          builder: (_) => TelaPlayer(canal: item.canal),
                        ),
                      );
                    },
                    onToggleFavorito: () =>
                        provider.alternarFavorito(item.canal),
                  );
                },
              ),
            ),
    );
  }

  Future<void> _confirmarLimpeza(BuildContext context) async {
    final provider = context.read<IptvProvider>();
    final confirmar = await showDialog<bool>(
      context: context,
      builder: (_) => AlertDialog(
        title: const Text('Limpar historico?'),
        content: const Text('Todos os itens serao removidos.'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('Cancelar'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(context, true),
            child: const Text('Limpar'),
          ),
        ],
      ),
    );
    if (confirmar == true) await provider.limparHistorico();
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
                color: AppColors.surface1,
                borderRadius: BorderRadius.circular(AppRadius.base),
              ),
              child: const Icon(
                Icons.history_rounded,
                size: 32,
                color: AppColors.textSecondary,
              ),
            ),
            const SizedBox(height: AppSpacing.base),
            Text(
              'Sem historico ainda',
              style: Theme.of(context).textTheme.titleMedium,
            ),
            const SizedBox(height: AppSpacing.sm),
            Text(
              'Os ultimos canais que voce abrir aparecerao aqui.',
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