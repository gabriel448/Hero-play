import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../models/idioma_app.dart';
import '../state/preferencias_provider.dart';
import '../theme/app_theme.dart';
import '../utils/layout.dart';
import 'tela_historico.dart';

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
            const _TituloSecao('Atividade'),
            _OpcaoNavegacao(
              icone: Icons.history_rounded,
              titulo: 'Histórico',
              subtitulo: 'Canais e episódios assistidos recentemente',
              onTap: () => Navigator.of(context).push(
                MaterialPageRoute(builder: (_) => const TelaHistorico()),
              ),
            ),
            const _TituloSecao('Reprodução'),
            _OpcaoToggle(
              titulo: 'Ajuste automático de qualidade',
              subtitulo:
                  'Reduz a qualidade automaticamente quando a conexão está instável.',
              valor: preferencias.autoQualidade,
              onChanged: preferencias.definirAutoQualidade,
              beta: true,
            ),
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

class _OpcaoNavegacao extends StatelessWidget {
  final IconData icone;
  final String titulo;
  final String subtitulo;
  final VoidCallback onTap;

  const _OpcaoNavegacao({
    required this.icone,
    required this.titulo,
    required this.subtitulo,
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
                color: AppColors.surface2,
                borderRadius: BorderRadius.circular(AppRadius.sm),
              ),
              child: Icon(icone, size: 20, color: AppColors.textSecondary),
            ),
            const SizedBox(width: AppSpacing.base),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(titulo, style: Theme.of(context).textTheme.titleSmall),
                  const SizedBox(height: 2),
                  Text(
                    subtitulo,
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

class _OpcaoToggle extends StatelessWidget {
  final String titulo;
  final String subtitulo;
  final bool valor;
  final ValueChanged<bool> onChanged;
  final bool beta;

  const _OpcaoToggle({
    required this.titulo,
    required this.subtitulo,
    required this.valor,
    required this.onChanged,
    this.beta = false,
  });

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(
        horizontal: AppSpacing.lg,
        vertical: AppSpacing.sm,
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Text(titulo, style: Theme.of(context).textTheme.titleSmall),
                    if (beta) ...[
                      const SizedBox(width: 8),
                      Container(
                        padding: const EdgeInsets.symmetric(
                            horizontal: 6, vertical: 2),
                        decoration: BoxDecoration(
                          color: AppColors.accentDim,
                          borderRadius: BorderRadius.circular(4),
                        ),
                        child: Text(
                          'BETA',
                          style:
                              Theme.of(context).textTheme.labelSmall?.copyWith(
                                    color: AppColors.accentBright,
                                    fontWeight: FontWeight.w700,
                                    fontSize: 10,
                                  ),
                        ),
                      ),
                    ],
                  ],
                ),
                const SizedBox(height: 2),
                Text(subtitulo,
                    style: Theme.of(context).textTheme.bodySmall),
              ],
            ),
          ),
          Switch(value: valor, onChanged: onChanged),
        ],
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
