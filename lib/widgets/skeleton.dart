import 'package:flutter/material.dart';
import '../theme/app_theme.dart';

/// Efeito "shimmer": uma faixa de brilho desliza sobre os filhos.
///
/// Padrao moderno para indicar carregamento de texto/conteudo — comunica
/// "isto vai aparecer aqui" com movimento, sem recorrer a um spinner
/// generico. Use envolvendo um ou mais [SkeletonBox].
class Shimmer extends StatefulWidget {
  final Widget child;
  const Shimmer({super.key, required this.child});

  @override
  State<Shimmer> createState() => _ShimmerState();
}

class _ShimmerState extends State<Shimmer>
    with SingleTickerProviderStateMixin {
  late final AnimationController _ctrl;

  @override
  void initState() {
    super.initState();
    _ctrl = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 1350),
    )..repeat();
  }

  @override
  void dispose() {
    _ctrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: _ctrl,
      child: widget.child,
      builder: (context, child) {
        return ShaderMask(
          blendMode: BlendMode.srcATop,
          shaderCallback: (bounds) {
            return LinearGradient(
              begin: Alignment.centerLeft,
              end: Alignment.centerRight,
              colors: const [
                AppColors.surface2,
                AppColors.surface2,
                AppColors.surface3,
                AppColors.surface2,
                AppColors.surface2,
              ],
              stops: const [0.0, 0.35, 0.5, 0.65, 1.0],
              // _ctrl.value 0..1  ->  percent -1..2 (entra e sai da area)
              transform: _SlidingGradient(percent: _ctrl.value * 3.0 - 1.0),
            ).createShader(bounds);
          },
          child: child,
        );
      },
    );
  }
}

/// Desloca o gradiente horizontalmente — faz o brilho varrer a area.
class _SlidingGradient extends GradientTransform {
  final double percent;
  const _SlidingGradient({required this.percent});

  @override
  Matrix4? transform(Rect bounds, {TextDirection? textDirection}) {
    return Matrix4.translationValues(bounds.width * percent, 0.0, 0.0);
  }
}

/// Retangulo arredondado opaco — placeholder de uma linha de texto ou bloco.
/// Pensado para ficar dentro de um [Shimmer].
class SkeletonBox extends StatelessWidget {
  final double? width;
  final double height;

  const SkeletonBox({super.key, this.width, this.height = 12.0});

  @override
  Widget build(BuildContext context) {
    return Container(
      width: width,
      height: height,
      decoration: BoxDecoration(
        color: AppColors.surface2,
        borderRadius: BorderRadius.circular(AppRadius.sm),
      ),
    );
  }
}

/// Bloco pronto de varias linhas em skeleton — util para sinopses.
/// A ultima linha sai mais curta, imitando um paragrafo real.
class SkeletonLinhas extends StatelessWidget {
  final int linhas;
  final double alturaLinha;
  final double espaco;
  final double larguraUltima;

  const SkeletonLinhas({
    super.key,
    this.linhas = 3,
    this.alturaLinha = 12.0,
    this.espaco = 9.0,
    this.larguraUltima = 150.0,
  });

  @override
  Widget build(BuildContext context) {
    return Shimmer(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          for (var i = 0; i < linhas; i++) ...[
            SkeletonBox(
              height: alturaLinha,
              width: i == linhas - 1 ? larguraUltima : double.infinity,
            ),
            if (i != linhas - 1) SizedBox(height: espaco),
          ],
        ],
      ),
    );
  }
}
