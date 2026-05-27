import 'package:flutter/material.dart';

/// [ScrollController] que produz animacao suave para eventos de roda do mouse
/// em vez do salto instantaneo (jumpTo) padrao.
///
/// Funciona porque [_SmoothScrollPosition.pointerScroll] e chamado diretamente
/// pelo [Scrollable] quando ocorre um evento de scroll do ponteiro, ANTES de
/// qualquer Listener externo registrar handler no PointerSignalResolver.
/// Substituindo essa chamada por [animateTo] obtemos rolagem suave sem precisar
/// disputar a primeira registrar via Listener (que naturalmente perdemos, ja
/// que o Listener interno do proprio Scrollable e mais "inner" e dispara antes).
///
/// Use-o em ListViews/CustomScrollViews/SingleChildScrollViews do desktop:
///
/// ```dart
/// final _ctrl = SmoothScrollController();
/// // ...
/// ListView(controller: _ctrl, ...);
/// ```
class SmoothScrollController extends ScrollController {
  SmoothScrollController({
    super.initialScrollOffset,
    super.keepScrollOffset,
    super.debugLabel,
  });

  /// Duracao da animacao por evento de scroll. 180ms da resposta rapida
  /// mas com curva suave perceptivel.
  static const Duration duration = Duration(milliseconds: 180);

  /// Curva de saida — easeOutCubic da impressao de "deslizar" e acomodar.
  static const Curve curve = Curves.easeOutCubic;

  @override
  ScrollPosition createScrollPosition(
    ScrollPhysics physics,
    ScrollContext context,
    ScrollPosition? oldPosition,
  ) {
    return _SmoothScrollPosition(
      physics: physics,
      context: context,
      initialPixels: initialScrollOffset,
      keepScrollOffset: keepScrollOffset,
      oldPosition: oldPosition,
      debugLabel: debugLabel,
    );
  }
}

class _SmoothScrollPosition extends ScrollPositionWithSingleContext {
  _SmoothScrollPosition({
    required super.physics,
    required super.context,
    super.initialPixels = 0.0,
    super.keepScrollOffset = true,
    super.oldPosition,
    super.debugLabel,
  });

  @override
  void pointerScroll(double delta) {
    // Compatibilidade com inertia cancel — delta zero significa "pare a
    // simulacao balistica atual"; deixar a implementacao padrao cuidar.
    if (delta == 0.0) {
      goBallistic(0.0);
      return;
    }

    final target =
        (pixels + delta).clamp(minScrollExtent, maxScrollExtent).toDouble();
    if (target == pixels) return;

    // Se ha uma animacao em andamento, partir de pixels atuais (que ja
    // refletem a posicao animada) acumula suavemente — sem reiniciar o tween.
    animateTo(
      target,
      duration: SmoothScrollController.duration,
      curve: SmoothScrollController.curve,
    );
  }
}
