import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../models/idioma_app.dart';
import '../state/preferencias_provider.dart';
import '../theme/app_theme.dart';
import '../widgets/animado_entrada.dart';

/// Tela de boas-vindas do primeiro uso: o usuario escolhe o idioma.
///
/// Assim que ele toca em um idioma, [PreferenciasProvider] e atualizado e o
/// `IptvApp` troca a `home` automaticamente para o app de verdade. O idioma
/// pode ser alterado depois em Configuracoes.
class TelaOnboarding extends StatelessWidget {
  const TelaOnboarding({super.key});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: SafeArea(
        child: Center(
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 420),
            child: SingleChildScrollView(
              padding: const EdgeInsets.all(AppSpacing.xl),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  AnimadoEntrada(
                    child: Center(
                      child: Container(
                        width: 88,
                        height: 88,
                        decoration: BoxDecoration(
                          color: AppColors.surface1,
                          borderRadius: BorderRadius.circular(AppRadius.lg),
                        ),
                        child: const Icon(
                          Icons.live_tv_rounded,
                          size: 44,
                          color: AppColors.accent,
                        ),
                      ),
                    ),
                  ),
                  const SizedBox(height: AppSpacing.xl),
                  AnimadoEntrada(
                    delay: const Duration(milliseconds: 80),
                    child: Column(
                      children: [
                        Text(
                          'IPTV Player',
                          style: Theme.of(context).textTheme.headlineMedium,
                          textAlign: TextAlign.center,
                        ),
                        const SizedBox(height: AppSpacing.xs),
                        Text(
                          'Escolha o idioma  ·  Choose your language  ·  '
                          'Elige tu idioma',
                          style:
                              Theme.of(context).textTheme.bodySmall?.copyWith(
                                    color: AppColors.textSecondary,
                                  ),
                          textAlign: TextAlign.center,
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(height: AppSpacing.xl),
                  for (final (i, idioma) in IdiomaApp.values.indexed) ...[
                    AnimadoEntrada(
                      delay: Duration(milliseconds: 160 + i * 70),
                      child: _CardIdioma(
                        idioma: idioma,
                        onTap: () => context
                            .read<PreferenciasProvider>()
                            .definirIdioma(idioma),
                      ),
                    ),
                    if (idioma != IdiomaApp.values.last)
                      const SizedBox(height: AppSpacing.md),
                  ],
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class _CardIdioma extends StatelessWidget {
  final IdiomaApp idioma;
  final VoidCallback onTap;
  const _CardIdioma({required this.idioma, required this.onTap});

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
            horizontal: AppSpacing.lg,
            vertical: AppSpacing.base,
          ),
          child: Row(
            children: [
              Container(
                width: 40,
                height: 40,
                decoration: BoxDecoration(
                  color: AppColors.surface2,
                  borderRadius: BorderRadius.circular(AppRadius.sm),
                ),
                alignment: Alignment.center,
                child: Text(
                  idioma.codigo.substring(0, 2).toUpperCase(),
                  style: Theme.of(context).textTheme.labelMedium?.copyWith(
                        color: AppColors.accent,
                        fontWeight: FontWeight.w700,
                      ),
                ),
              ),
              const SizedBox(width: AppSpacing.base),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      idioma.nome,
                      style: Theme.of(context).textTheme.titleSmall,
                    ),
                    Text(
                      idioma.regiao,
                      style: Theme.of(context).textTheme.bodySmall,
                    ),
                  ],
                ),
              ),
              const Icon(
                Icons.chevron_right_rounded,
                size: 20,
                color: AppColors.textTertiary,
              ),
            ],
          ),
        ),
      ),
    );
  }
}
