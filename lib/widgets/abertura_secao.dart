import 'dart:async';
import 'dart:ui' show lerpDouble;

import 'package:flutter/material.dart';
import '../theme/app_theme.dart';

/// Abertura animada de uma secao (Filmes / Series / Canais ao vivo), no mesmo
/// espirito da entrada de perfil:
///
///   1) o icone sai do botao tocado e vai para o CENTRO da tela, crescendo,
///      enquanto o fundo escurece e o nome aparece embaixo;
///   2) icone + nome pulsam levemente no centro ENQUANTO o conteudo carrega
///      (ou por [duracaoMinima], o que durar mais);
///   3) o icone sobe para o TOPO e o nome se posiciona a direita dele,
///      centralizados na linha da AppBar (mesma linha do botao voltar); o preto
///      some e o conteudo, ja carregado, e revelado.
///
/// A posicao final casa com a [TituloSecao] usada no `title` da AppBar da tela
/// de destino — por isso, ao remover o overlay, a troca e imperceptivel.
///
/// [pronto] completa quando o conteudo terminou de carregar. Em telas sem load
/// (canais), passe um future ja completo e use [duracaoMinima] (~1s) para a
/// animacao ter a mesma cadencia das demais.
class AberturaSecao extends StatefulWidget {
  final Rect? origem;
  final IconData icone;
  final String titulo;
  final Color corIcone;
  final Future<void> pronto;
  final Duration duracaoMinima;
  final Widget child;

  const AberturaSecao({
    super.key,
    required this.origem,
    required this.icone,
    required this.titulo,
    required this.corIcone,
    required this.pronto,
    required this.child,
    this.duracaoMinima = const Duration(milliseconds: 600),
  });

  @override
  State<AberturaSecao> createState() => _AberturaSecaoState();

  /// True quando o conteudo da secao ja pode ENTRAR (estagio 3 iniciado). As
  /// telas usam isso para so construir/animar seus itens nesse momento, em
  /// sincronia com a revelacao. Sem uma [AberturaSecao] acima, retorna true
  /// (entrada imediata).
  static bool conteudoRevelado(BuildContext context) =>
      _EscopoAbertura.revelarDe(context);
}

class _AberturaSecaoState extends State<AberturaSecao>
    with TickerProviderStateMixin {
  // 3 estagios independentes (ver doc da classe).
  late final AnimationController _centro;
  late final AnimationController _pulso;
  late final AnimationController _canto;
  late final bool _animar;
  bool _concluido = false;
  // True quando o estagio 3 comeca — libera o conteudo da secao a entrar.
  bool _revelar = false;

  @override
  void initState() {
    super.initState();
    _animar = widget.origem != null;
    _centro = AnimationController(
        vsync: this, duration: const Duration(milliseconds: 440));
    _pulso = AnimationController(
        vsync: this, duration: const Duration(milliseconds: 700));
    _canto = AnimationController(
        vsync: this, duration: const Duration(milliseconds: 760));
    if (_animar) {
      _orquestrar();
    } else {
      _concluido = true; // sem origem: mostra o conteudo direto.
    }
  }

  Future<void> _orquestrar() async {
    final inicio = DateTime.now();
    _centro.addStatusListener((s) {
      if (s == AnimationStatus.completed && !_pulso.isAnimating) {
        _pulso.repeat(reverse: true); // estagio 2 ao chegar no centro
      }
    });
    // Deixa a transicao de rota assentar antes de comecar.
    await Future<void>.delayed(const Duration(milliseconds: 60));
    if (!mounted) return;
    await _centro.forward(); // estagio 1
    if (!mounted) return;
    try {
      await widget.pronto; // estagio 2: espera o conteudo carregar
    } catch (_) {/* best-effort */}
    if (!mounted) return;
    final decorrido = DateTime.now().difference(inicio);
    if (decorrido < widget.duracaoMinima) {
      await Future<void>.delayed(widget.duracaoMinima - decorrido);
    }
    if (!mounted) return;
    _pulso.stop();
    // Estagio 3: o icone sobe ao topo SOBRE o preto. Liberamos o conteudo a
    // entrar na aproximacao final do icone (quando o scrim ja esta saindo), em
    // vez de so no fim — assim os banners comecam a aparecer junto com a chegada
    // do icone, sem aquele intervalo de tela preta.
    void aoProgredir() {
      if (!_revelar && _canto.value >= 0.55) {
        if (mounted) setState(() => _revelar = true);
        _canto.removeListener(aoProgredir);
      }
    }

    _canto.addListener(aoProgredir);
    await _canto.forward();
    if (!mounted) return;
    setState(() {
      _concluido = true; // remove overlay; a AppBar real assume o titulo
      _revelar = true; // garante (caso o listener nao tenha disparado)
    });
  }

  @override
  void dispose() {
    _centro.dispose();
    _pulso.dispose();
    _canto.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    if (!_animar) return widget.child;
    return Stack(
      children: [
        // Destino: INVISIVEL ate o estagio 3. Nos estagios 1-2 a rota e
        // nao-opaca, entao a HOME (com os botoes de selecao) aparece por baixo e
        // escurece com o scrim. O flip de opacidade 0->1 acontece sob o preto
        // total (scrim==1 na virada do estagio 2 para o 3), entao a troca da
        // home pelo destino e imperceptivel; depois o scrim some revelando-o.
        Positioned.fill(
          child: AnimatedBuilder(
            animation: _canto,
            builder: (context, child) =>
                Opacity(opacity: _canto.value > 0 ? 1 : 0, child: child),
            // Enquanto o overlay existe, esconde o TITULO real da AppBar para
            // nao duplicar com o icone+nome que voam. Ao concluir, o overlay sai
            // e o titulo real aparece no mesmo lugar (troca imperceptivel).
            child: _EscopoAbertura(
              ocultarTitulo: !_concluido,
              revelar: _revelar,
              child: widget.child,
            ),
          ),
        ),
        if (!_concluido)
          Positioned.fill(
            // Bloqueia toques enquanto a animacao roda.
            child: AbsorbPointer(child: _overlay(context)),
          ),
      ],
    );
  }

  Widget _overlay(BuildContext context) {
    final mq = MediaQuery.of(context);
    final w = mq.size.width;
    final h = mq.size.height;
    final appbarMidY = mq.padding.top + kToolbarHeight / 2;

    // Mede o nome no MESMO estilo do title da AppBar (titleLarge) E com o mesmo
    // textScaler do dispositivo — sem isso, com fonte ampliada a largura medida
    // diverge da real e o icone+nome "pulam" de lado ao trocar pelo titulo real.
    final estilo = Theme.of(context).textTheme.titleLarge!;
    final escala = MediaQuery.textScalerOf(context);
    final tp = TextPainter(
      text: TextSpan(text: widget.titulo, style: estilo),
      textDirection: TextDirection.ltr,
      textScaler: escala,
      maxLines: 1,
    )..layout();
    final textoW = tp.width;
    final textoH = tp.height;

    const iconFinal = 24.0; // == tamanho do icone na TituloSecao
    const gap = AppSpacing.sm; // == espaco na TituloSecao
    final grupoLeft = (w - (iconFinal + gap + textoW)) / 2;
    final iconFinalCenter = Offset(grupoLeft + iconFinal / 2, appbarMidY);
    final textoFinalCenter =
        Offset(grupoLeft + iconFinal + gap + textoW / 2, appbarMidY);

    const iconCentro = 76.0;
    final centro = Offset(w / 2, h * 0.40);
    final textoCentro =
        Offset(w / 2, centro.dy + iconCentro / 2 + 20 + textoH / 2);

    final origemCenter = widget.origem!.center;
    final origemSize = widget.origem!.shortestSide;

    return AnimatedBuilder(
      animation: Listenable.merge([_centro, _pulso, _canto]),
      builder: (context, _) {
        double scrim;
        Offset iconCenter;
        double iconSize;
        Offset textoPos;
        double textoOp;

        if (_canto.value == 0) {
          // estagios 1 e 2: origem -> centro (+ pulso ao chegar).
          final t = Curves.easeOutCubic.transform(_centro.value);
          iconCenter = Offset.lerp(origemCenter, centro, t)!;
          iconSize = lerpDouble(origemSize, iconCentro, t)!;
          textoPos = textoCentro;
          textoOp = ((_centro.value - 0.45) / 0.55).clamp(0.0, 1.0);
          scrim = t;
          if (_centro.isCompleted) {
            iconSize *= 1 + 0.05 * _pulso.value; // pulso leve
          }
        } else {
          // estagio 3: centro -> topo; o preto some.
          final t = Curves.easeInOutCubic.transform(_canto.value);
          iconCenter = Offset.lerp(centro, iconFinalCenter, t)!;
          iconSize = lerpDouble(iconCentro, iconFinal, t)!;
          textoPos = Offset.lerp(textoCentro, textoFinalCenter, t)!;
          textoOp = 1;
          scrim = 1 -
              Curves.easeInOut.transform((_canto.value / 0.6).clamp(0.0, 1.0));
        }

        return Stack(
          children: [
            Positioned.fill(
              child: ColoredBox(color: Colors.black.withValues(alpha: scrim)),
            ),
            Positioned(
              left: iconCenter.dx - iconSize / 2,
              top: iconCenter.dy - iconSize / 2,
              width: iconSize,
              height: iconSize,
              child: FittedBox(
                fit: BoxFit.contain,
                // Tamanho-base = tamanho final (== TituloSecao); o FittedBox
                // escala para o box. Assim, ao chegar no topo (box 24), o icone
                // fica 1:1 com o da AppBar, sem salto.
                child: Icon(widget.icone, size: iconFinal, color: widget.corIcone),
              ),
            ),
            Positioned(
              left: textoPos.dx - textoW / 2,
              top: textoPos.dy - textoH / 2,
              child: Opacity(
                opacity: textoOp,
                child: Text(widget.titulo, style: estilo),
              ),
            ),
          ],
        );
      },
    );
  }
}

/// Escopo fornecido por [AberturaSecao] ao seu filho. Enquanto [ocultarTitulo]
/// for true (overlay ativo), a [TituloSecao] da AppBar se esconde para nao
/// duplicar com o icone+nome que estao voando no overlay.
class _EscopoAbertura extends InheritedWidget {
  final bool ocultarTitulo;
  final bool revelar;
  const _EscopoAbertura({
    required this.ocultarTitulo,
    required this.revelar,
    required super.child,
  });

  static bool ocultarDe(BuildContext context) =>
      context
          .dependOnInheritedWidgetOfExactType<_EscopoAbertura>()
          ?.ocultarTitulo ??
      false;

  // Sem escopo (ex.: navegacao sem animacao) => true (entrada imediata).
  static bool revelarDe(BuildContext context) =>
      context.dependOnInheritedWidgetOfExactType<_EscopoAbertura>()?.revelar ??
      true;

  @override
  bool updateShouldNotify(_EscopoAbertura old) =>
      old.ocultarTitulo != ocultarTitulo || old.revelar != revelar;
}

/// Title padrao das secoes na AppBar: icone + nome. Mantido em sincronia com a
/// posicao final de [AberturaSecao] (icone 24px + espaco AppSpacing.sm + nome
/// em titleLarge, centralizados).
class TituloSecao extends StatelessWidget {
  final IconData icone;
  final String texto;
  final Color corIcone;

  const TituloSecao({
    super.key,
    required this.icone,
    required this.texto,
    required this.corIcone,
  });

  @override
  Widget build(BuildContext context) {
    return Opacity(
      // Oculto enquanto a animacao de abertura roda (o overlay mostra o titulo).
      opacity: _EscopoAbertura.ocultarDe(context) ? 0 : 1,
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icone, size: 24, color: corIcone),
          const SizedBox(width: AppSpacing.sm),
          Flexible(
            child: Text(
              texto,
              style: Theme.of(context).textTheme.titleLarge,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
            ),
          ),
        ],
      ),
    );
  }
}
