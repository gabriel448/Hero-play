import 'dart:async';

import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../state/iptv_provider.dart';
import '../theme/app_theme.dart';

/// Tela exibida enquanto a lista do APARELHO (ativacao MAC+Key) e baixada e
/// parseada pela primeira vez — quando ainda nao ha nada em cache.
///
/// O `app.dart` mostra esta tela enquanto [IptvProvider.primeiroDownload] for
/// verdadeiro. Nas aberturas seguintes ela nao aparece: a lista vem do cache
/// local e o download so acontece de novo em "Atualizar".
class TelaImportandoListas extends StatefulWidget {
  const TelaImportandoListas({super.key});

  @override
  State<TelaImportandoListas> createState() => _TelaImportandoListasState();
}

class _TelaImportandoListasState extends State<TelaImportandoListas> {
  // Dicas que passam no rodape, no estilo das telas de carregamento de jogos.
  static const _dicas = [
    'Bem-vindo ao Hero Play',
    'Esse processo só é realizado uma vez',
  ];

  int _dicaAtual = 0;
  Timer? _timer;

  @override
  void initState() {
    super.initState();
    _timer = Timer.periodic(const Duration(seconds: 4), (_) {
      if (!mounted) return;
      setState(() => _dicaAtual = (_dicaAtual + 1) % _dicas.length);
    });
  }

  @override
  void dispose() {
    _timer?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final provider = context.watch<IptvProvider>();
    final fracao = provider.fracaoDownload;
    final mb = provider.bytesBaixados / 1048576;

    // Texto que descreve a fase atual. O servidor Xtream costuma NAO informar o
    // tamanho total — nesse caso mostramos os MB recebidos, que e o que prova
    // que o download esta andando.
    final String subtitulo;
    if (provider.bytesBaixados == 0) {
      subtitulo = 'Conectando ao servidor…';
    } else if (fracao != null && fracao >= 1) {
      subtitulo = 'Organizando seus canais…';
    } else if (fracao != null) {
      subtitulo = 'Baixando sua lista… ${(fracao * 100).round()}%';
    } else {
      subtitulo = 'Baixando sua lista… ${mb.toStringAsFixed(1)} MB';
    }

    return Scaffold(
      body: SafeArea(
        child: Stack(
          children: [
            Center(
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
                        'Preparando sua lista',
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
                          style: Theme.of(context)
                              .textTheme
                              .bodyMedium
                              ?.copyWith(color: AppColors.textSecondary),
                          textAlign: TextAlign.center,
                        ),
                      ),
                      const SizedBox(height: AppSpacing.xxl),
                      // Barra de progresso: indeterminada ate sabermos o total,
                      // depois sobe em tempo real conforme as listas sao baixadas.
                      ClipRRect(
                        borderRadius: BorderRadius.circular(AppRadius.pill),
                        child: TweenAnimationBuilder<double>(
                          tween: Tween(begin: 0, end: fracao ?? 0),
                          duration: const Duration(milliseconds: 400),
                          curve: Curves.easeOut,
                          builder: (context, value, _) =>
                              LinearProgressIndicator(
                            value: fracao != null ? value : null,
                            minHeight: 5,
                            backgroundColor: AppColors.surface2,
                            valueColor: const AlwaysStoppedAnimation(
                                AppColors.accent),
                          ),
                        ),
                      ),
                      if (provider.bytesBaixados > 0) ...[
                        const SizedBox(height: AppSpacing.md),
                        Text(
                          '${mb.toStringAsFixed(1)} MB',
                          style: Theme.of(context)
                              .textTheme
                              .labelSmall
                              ?.copyWith(color: AppColors.textTertiary),
                        ),
                      ],
                    ],
                  ),
                ),
              ),
            ),
            // Dica no rodape, trocando suavemente a cada poucos segundos.
            Positioned(
              left: AppSpacing.xl,
              right: AppSpacing.xl,
              bottom: AppSpacing.xl,
              child: AnimatedSwitcher(
                duration: const Duration(milliseconds: 500),
                transitionBuilder: (child, animation) => FadeTransition(
                  opacity: animation,
                  child: child,
                ),
                child: Text(
                  _dicas[_dicaAtual],
                  key: ValueKey(_dicaAtual),
                  textAlign: TextAlign.center,
                  style: Theme.of(context).textTheme.bodySmall?.copyWith(
                        color: AppColors.textTertiary,
                        fontStyle: FontStyle.italic,
                      ),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
