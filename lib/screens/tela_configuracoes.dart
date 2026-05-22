import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../models/idioma_app.dart';
import '../state/preferencias_provider.dart';
import '../theme/app_theme.dart';
import '../utils/layout.dart';

/// Tela de configuracoes. Hoje apenas o idioma — ponto de extensao natural
/// para futuras opcoes.
class TelaConfiguracoes extends StatelessWidget {
  const TelaConfiguracoes({super.key});

  @override
  Widget build(BuildContext context) {
    final preferencias = context.watch<PreferenciasProvider>();
    final idiomaAtual = preferencias.idiomaEfetivo;

    return Scaffold(
      appBar: AppBar(title: const Text('Configurações')),
      body: tabletBody(
        context,
        ListView(
          padding: const EdgeInsets.only(bottom: AppSpacing.xl),
          children: [
            const _TituloSecao('Idioma'),
            Padding(
              padding: const EdgeInsets.fromLTRB(
                AppSpacing.lg,
                0,
                AppSpacing.lg,
                AppSpacing.sm,
              ),
              child: Text(
                'Usado nas buscas de sinopse e elenco dos filmes e séries.',
                style: Theme.of(context).textTheme.bodySmall,
              ),
            ),
            for (final idioma in IdiomaApp.values)
              _OpcaoIdioma(
                idioma: idioma,
                selecionado: idioma == idiomaAtual,
                onTap: () => preferencias.definirIdioma(idioma),
              ),
          ],
        ),
      ),
    );
  }
}

class _TituloSecao extends StatelessWidget {
  final String texto;
  const _TituloSecao(this.texto);

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(
        AppSpacing.lg,
        AppSpacing.lg,
        AppSpacing.lg,
        AppSpacing.xs,
      ),
      child: Text(
        texto.toUpperCase(),
        style: Theme.of(context).textTheme.labelSmall?.copyWith(
              color: AppColors.textTertiary,
              letterSpacing: 0.6,
            ),
      ),
    );
  }
}

class _OpcaoIdioma extends StatelessWidget {
  final IdiomaApp idioma;
  final bool selecionado;
  final VoidCallback onTap;

  const _OpcaoIdioma({
    required this.idioma,
    required this.selecionado,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return InkWell(
      onTap: onTap,
      child: Padding(
        padding: const EdgeInsets.symmetric(
          horizontal: AppSpacing.lg,
          vertical: AppSpacing.md,
        ),
        child: Row(
          children: [
            Container(
              width: 40,
              height: 40,
              decoration: BoxDecoration(
                color: selecionado
                    ? AppColors.accentDim
                    : AppColors.surface2,
                borderRadius: BorderRadius.circular(AppRadius.sm),
              ),
              alignment: Alignment.center,
              child: Text(
                idioma.codigo.substring(0, 2).toUpperCase(),
                style: Theme.of(context).textTheme.labelMedium?.copyWith(
                      color: selecionado
                          ? AppColors.accentBright
                          : AppColors.textSecondary,
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
            Icon(
              selecionado
                  ? Icons.check_circle_rounded
                  : Icons.circle_outlined,
              size: 22,
              color: selecionado
                  ? AppColors.accent
                  : AppColors.textTertiary,
            ),
          ],
        ),
      ),
    );
  }
}
