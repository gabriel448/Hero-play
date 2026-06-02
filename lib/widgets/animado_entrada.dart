import 'dart:async';

import 'package:flutter/material.dart';

/// Anima a entrada de um widget com fade + deslize para cima.
/// Equivalente ao padrao .anim-in do site (anime.js, 18px translateY, easeOutExpo).
///
/// Use [delay] para criar efeito de stagger entre elementos da mesma tela:
///   AnimadoEntrada(delay: Duration(milliseconds: 80), child: ...)
class AnimadoEntrada extends StatefulWidget {
  final Widget child;
  final Duration delay;
  final Duration duration;

  const AnimadoEntrada({
    super.key,
    required this.child,
    this.delay = Duration.zero,
    this.duration = const Duration(milliseconds: 480),
  });

  @override
  State<AnimadoEntrada> createState() => _AnimadoEntradaState();
}

class _AnimadoEntradaState extends State<AnimadoEntrada>
    with SingleTickerProviderStateMixin {
  late final AnimationController _ctrl;
  late final Animation<double> _fade;
  late final Animation<Offset> _slide;
  Timer? _timer;

  @override
  void initState() {
    super.initState();
    _ctrl = AnimationController(vsync: this, duration: widget.duration);
    _fade = CurvedAnimation(parent: _ctrl, curve: Curves.easeOutQuart);
    _slide = Tween<Offset>(
      begin: const Offset(0, 0.045),
      end: Offset.zero,
    ).animate(CurvedAnimation(parent: _ctrl, curve: Curves.easeOutQuart));

    if (widget.delay == Duration.zero) {
      _ctrl.forward();
    } else {
      _timer = Timer(widget.delay, () {
        if (mounted) _ctrl.forward();
      });
    }
  }

  @override
  void dispose() {
    _timer?.cancel();
    _ctrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return FadeTransition(
      opacity: _fade,
      child: SlideTransition(position: _slide, child: widget.child),
    );
  }
}
