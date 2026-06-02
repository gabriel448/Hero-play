import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../state/iptv_provider.dart';
import '../theme/app_theme.dart';

/// Tela exibida logo apos o login, enquanto as listas da conta sao baixadas
/// e parseadas pela primeira vez (quando ainda nao ha nenhuma no aparelho).
///
/// O `app.dart` mostra esta tela enquanto [IptvProvider.sincronizando] for
/// verdadeiro e ainda nao houver listas; assim que a primeira lista fica
/// pronta, ele troca para a tela inicial automaticamente.
class TelaImportandoListas extends StatelessWidget {
  const TelaImportandoListas({super.key});

  @override
  Widget build(BuildContext context) {
    final provider = context.watch<IptvProvider>();
    final progresso = provider.progressoSync;
    final total = provider.totalSync;

    // Texto que descreve a fase atual do download.
    final String subtitulo;
    if (total == 0) {
      subtitulo = 'Conectando à sua conta…';
    } else if (progresso >= total) {
      subtitulo = 'Preparando…';
    } else {
      final falta = total - progresso;
      subtitulo = 'Baixando $falta ${falta == 1 ? 'lista' : 'listas'}…';
    }

    return Scaffold(
      body: SafeArea(
        child: Center(
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 360),
            child: Padding(
              padding: const EdgeInsets.all(AppSpacing.xl),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Container(
                    width: 88,
                    height: 88,
                    decoration: BoxDecoration(
                      color: AppColors.surface1,
                      borderRadius: BorderRadius.circular(AppRadius.lg),
                    ),
                    child: const Icon(
                      Icons.cloud_download_rounded,
                      size: 44,
                      color: AppColors.accent,
                    ),
                  ),
                  const SizedBox(height: AppSpacing.xl),
                  Text(
                    'Importando suas listas',
                    style: Theme.of(context).textTheme.headlineMedium,
                    textAlign: TextAlign.center,
                  ),
                  const SizedBox(height: AppSpacing.sm),
                  // Texto animado — troca suavemente a cada mudanca de fase.
                  AnimatedSwitcher(
                    duration: const Duration(milliseconds: 300),
                    child: Text(
                      subtitulo,
                      key: ValueKey(subtitulo),
                      style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                            color: AppColors.textSecondary,
                          ),
                      textAlign: TextAlign.center,
                    ),
                  ),
                  const SizedBox(height: AppSpacing.xxl),
                  // Barra de progresso: indeterminada ate sabermos o total,
                  // depois sobe em tempo real conforme as listas sao baixadas.
                  ClipRRect(
                    borderRadius: BorderRadius.circular(AppRadius.pill),
                    child: TweenAnimationBuilder<double>(
                      tween: Tween(
                        begin: 0,
                        end: total > 0 ? progresso / total : 0,
                      ),
                      duration: const Duration(milliseconds: 400),
                      curve: Curves.easeOut,
                      builder: (context, value, _) => LinearProgressIndicator(
                        value: total > 0 ? value : null,
                        minHeight: 5,
                        backgroundColor: AppColors.surface2,
                        valueColor:
                            const AlwaysStoppedAnimation(AppColors.accent),
                      ),
                    ),
                  ),
                  if (total > 0) ...[
                    const SizedBox(height: AppSpacing.md),
                    AnimatedSwitcher(
                      duration: const Duration(milliseconds: 250),
                      child: Text(
                        '$progresso de $total',
                        key: ValueKey(progresso),
                        style: Theme.of(context).textTheme.labelSmall?.copyWith(
                              color: AppColors.textTertiary,
                            ),
                      ),
                    ),
                  ],
                  const SizedBox(height: AppSpacing.xl),
                  const SizedBox(
                    width: 24,
                    height: 24,
                    child: CircularProgressIndicator(strokeWidth: 2),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}
