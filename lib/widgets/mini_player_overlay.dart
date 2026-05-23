import 'dart:io';
import 'package:flutter/material.dart';
import 'package:media_kit_video/media_kit_video.dart';
import 'package:provider/provider.dart';
import '../screens/tela_player.dart';
import '../state/mini_player_provider.dart';
import '../theme/app_theme.dart';
import '../utils/nav_keys.dart';

// ── Mobile / tablet (tamanho original, intocado) ──────────────────────────────
const double _kW = 180.0;
const double _kH = 108.0; // 16:9

// ── Desktop (PC) ──────────────────────────────────────────────────────────────
// O tamanho do mini player desktop e dinamico — vive no MiniPlayerProvider e
// pode ser redimensionado pelos cantos. Os defaults estao no provider.

/// Cantos onde ha alca de redimensionamento.
enum _Canto { topLeft, topRight, bottomLeft, bottomRight }

class MiniPlayerOverlay extends StatelessWidget {
  final Widget child;
  const MiniPlayerOverlay({super.key, required this.child});

  @override
  Widget build(BuildContext context) {
    return Stack(
      children: [
        child,
        const _MiniFloat(),
      ],
    );
  }
}

class _MiniFloat extends StatelessWidget {
  const _MiniFloat();

  static bool get _isDesktop =>
      Platform.isWindows || Platform.isMacOS || Platform.isLinux;

  @override
  Widget build(BuildContext context) {
    final mini = context.watch<MiniPlayerProvider>();
    if (!mini.ativo) return const SizedBox.shrink();

    // Versão desktop: widget próprio, sem compartilhar nenhum código com mobile.
    if (_isDesktop) return _MiniFloatDesktop(mini: mini);

    // ── Mobile / Tablet (código original intacto) ─────────────────────────────
    final screenSize = MediaQuery.sizeOf(context);

    return Positioned(
      left: mini.posicao.dx.clamp(0, screenSize.width - _kW),
      top: mini.posicao.dy.clamp(0, screenSize.height - _kH - 32),
      child: GestureDetector(
        onPanUpdate: (d) => mini.mover(d.delta),
        onTap: mini.alternarAcoes,
        child: Material(
          elevation: 8,
          borderRadius: BorderRadius.circular(AppRadius.base),
          clipBehavior: Clip.antiAlias,
          color: Colors.black,
          child: SizedBox(
            width: _kW,
            height: _kH + (mini.mostrarAcoes ? 32 : 0),
            child: Column(
              children: [
                SizedBox(
                  width: _kW,
                  height: _kH,
                  child: Stack(
                    children: [
                      Video(
                        controller: mini.controller!,
                        controls: NoVideoControls,
                        width: _kW,
                        height: _kH,
                      ),
                      Positioned(
                        top: 4,
                        left: 4,
                        child: _LiveBadge(),
                      ),
                    ],
                  ),
                ),
                if (mini.mostrarAcoes) _BarraMobile(mini: mini),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

// ─── Mini player DESKTOP ──────────────────────────────────────────────────────
// Widget 100% independente do mobile. Construído do zero para PC:
//
//  • Vídeo grande (360x216) — arrastar nele move a janelinha.
//  • Barra de 3 botões SEMPRE visível abaixo do vídeo.
//  • Cada botão ocupa 1/3 inteiro da barra (≈120x56) — alvo de clique enorme.
//  • Sem Material/InkWell/IconButton: nada de "tinta" branca no hover.
//    O hover é só uma troca de cor de fundo (cinza), controlada manualmente.
//  • A barra de botões fica FORA de qualquer GestureDetector de arraste,
//    então não há disputa de gestos — o clique sempre chega no botão.

class _MiniFloatDesktop extends StatelessWidget {
  final MiniPlayerProvider mini;
  const _MiniFloatDesktop({required this.mini});

  void _maximizar() {
    final dados = mini.reivindicar();
    if (dados == null) return;
    final (canal, player, controller) = dados;
    // Empilha na área de conteúdo do ShellDesktop — a sidebar continua
    // visível ao redor (abre o canal "sem tela cheia", como ao clicá-lo).
    desktopContentNavigatorKey.currentState?.push(
      MaterialPageRoute(
        builder: (_) => TelaPlayer.comPlayer(
          canal: canal,
          player: player,
          controller: controller,
        ),
      ),
    );
  }

  /// Aplica um resize a partir do [canto] arrastado.
  ///
  /// Como o aspect ratio do vídeo é fixo (16:9), o resize é fundamentalmente
  /// 1D — escolhemos a dimensão (largura) e a altura segue. Aceitamos drag
  /// nos dois eixos: o eixo com maior movimento (em escala equivalente de
  /// largura) ganha. O canto oposto fica parado — a posição se ajusta para
  /// compensar a mudança de tamanho.
  void _aplicarResize(_Canto canto, Offset delta) {
    final (sinalX, sinalY) = switch (canto) {
      _Canto.topLeft => (-1.0, -1.0),
      _Canto.topRight => (1.0, -1.0),
      _Canto.bottomLeft => (-1.0, 1.0),
      _Canto.bottomRight => (1.0, 1.0),
    };
    final dx = delta.dx * sinalX;
    final dyEquivalenteX = delta.dy * sinalY * (16 / 9);
    final deltaLargura =
        dx.abs() > dyEquivalenteX.abs() ? dx : dyEquivalenteX;

    final larguraAntiga = mini.larguraDesktop;
    final alturaAntiga = mini.alturaTotalDesktop;
    mini.redimensionarDesktop(larguraAntiga + deltaLargura);
    final larguraNova = mini.larguraDesktop;
    final alturaNova = mini.alturaTotalDesktop;
    final aplicadoW = larguraNova - larguraAntiga;
    final aplicadoH = alturaNova - alturaAntiga;
    if (aplicadoW == 0 && aplicadoH == 0) return;

    final ajustePos = switch (canto) {
      _Canto.bottomRight => Offset.zero,
      _Canto.bottomLeft => Offset(-aplicadoW, 0),
      _Canto.topRight => Offset(0, -aplicadoH),
      _Canto.topLeft => Offset(-aplicadoW, -aplicadoH),
    };
    if (ajustePos != Offset.zero) mini.mover(ajustePos);
  }

  @override
  Widget build(BuildContext context) {
    final screen = MediaQuery.sizeOf(context);
    final largura = mini.larguraDesktop;
    final alturaVideo = mini.alturaVideoDesktop;
    final alturaBarra = mini.alturaBarraDesktop;
    final alturaTotal = alturaVideo + alturaBarra;
    final tamIcone = (alturaBarra * 0.46).clamp(18.0, 30.0);
    final escalaBadge = (largura / 200).clamp(1.0, 3.0);
    final maxX = (screen.width - largura).clamp(0.0, double.infinity);
    final maxY = (screen.height - alturaTotal).clamp(0.0, double.infinity);

    return Positioned(
      left: mini.posicao.dx.clamp(0.0, maxX),
      top: mini.posicao.dy.clamp(0.0, maxY),
      child: SizedBox(
        width: largura,
        height: alturaTotal,
        child: Stack(
          clipBehavior: Clip.none,
          children: [
            Material(
              elevation: 12,
              borderRadius: BorderRadius.circular(AppRadius.base),
              clipBehavior: Clip.antiAlias,
              color: Colors.black,
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  // ── Vídeo — área de arraste ─────────────────────────────────
                  MouseRegion(
                    cursor: SystemMouseCursors.move,
                    child: GestureDetector(
                      behavior: HitTestBehavior.opaque,
                      onPanUpdate: (d) => mini.mover(d.delta),
                      child: SizedBox(
                        width: largura,
                        height: alturaVideo,
                        child: Stack(
                          children: [
                            Video(
                              controller: mini.controller!,
                              controls: NoVideoControls,
                              width: largura,
                              height: alturaVideo,
                            ),
                            Positioned(
                              top: 8,
                              left: 8,
                              child: _LiveBadge(scale: escalaBadge),
                            ),
                          ],
                        ),
                      ),
                    ),
                  ),
                  // ── Barra de botões ─────────────────────────────────────────
                  SizedBox(
                    width: largura,
                    height: alturaBarra,
                    child: Row(
                      children: [
                        Expanded(
                          child: _BotaoDesktop(
                            icon: Icons.open_in_full_rounded,
                            cor: AppColors.textPrimary,
                            iconSize: tamIcone,
                            onTap: _maximizar,
                          ),
                        ),
                        const _DivisorVertical(),
                        Expanded(
                          child: _BotaoDesktop(
                            icon: mini.mutado
                                ? Icons.volume_off_rounded
                                : Icons.volume_up_rounded,
                            cor: mini.mutado
                                ? AppColors.accentBright
                                : AppColors.textPrimary,
                            iconSize: tamIcone,
                            onTap: mini.toggleMudo,
                          ),
                        ),
                        const _DivisorVertical(),
                        Expanded(
                          child: _BotaoDesktop(
                            icon: Icons.close_rounded,
                            cor: Colors.redAccent,
                            iconSize: tamIcone,
                            onTap: mini.fechar,
                          ),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
            ),
            // ── Alças de redimensionamento ───────────────────────────────────
            // 4 cantos. O canto inferior-direito tem um grip visível como
            // dica visual; os outros respondem só pela mudança de cursor.
            for (final canto in _Canto.values)
              _ResizeHandle(
                canto: canto,
                grip: canto == _Canto.bottomRight,
                onPan: (d) => _aplicarResize(canto, d),
              ),
          ],
        ),
      ),
    );
  }
}

/// Alça invisível de redimensionamento em um canto do mini player.
class _ResizeHandle extends StatefulWidget {
  final _Canto canto;
  final bool grip;
  final ValueChanged<Offset> onPan;

  const _ResizeHandle({
    required this.canto,
    required this.grip,
    required this.onPan,
  });

  @override
  State<_ResizeHandle> createState() => _ResizeHandleState();
}

class _ResizeHandleState extends State<_ResizeHandle> {
  bool _hover = false;

  MouseCursor get _cursor {
    switch (widget.canto) {
      case _Canto.topLeft:
      case _Canto.bottomRight:
        return SystemMouseCursors.resizeUpLeftDownRight;
      case _Canto.topRight:
      case _Canto.bottomLeft:
        return SystemMouseCursors.resizeUpRightDownLeft;
    }
  }

  @override
  Widget build(BuildContext context) {
    const tamanho = 18.0;
    const offset = -3.0; // metade fora da Material para sobrar fora dos botões
    final esquerda = widget.canto == _Canto.topLeft ||
        widget.canto == _Canto.bottomLeft;
    final cima =
        widget.canto == _Canto.topLeft || widget.canto == _Canto.topRight;

    return Positioned(
      left: esquerda ? offset : null,
      right: esquerda ? null : offset,
      top: cima ? offset : null,
      bottom: cima ? null : offset,
      width: tamanho,
      height: tamanho,
      child: MouseRegion(
        cursor: _cursor,
        onEnter: (_) {
          if (widget.grip) setState(() => _hover = true);
        },
        onExit: (_) {
          if (widget.grip) setState(() => _hover = false);
        },
        child: GestureDetector(
          behavior: HitTestBehavior.opaque,
          onPanUpdate: (d) => widget.onPan(d.delta),
          child: widget.grip
              ? CustomPaint(painter: _GripPainter(destaque: _hover))
              : const SizedBox.expand(),
        ),
      ),
    );
  }
}

/// Pinta três traços diagonais no canto inferior-direito, indicando que
/// dali se pode redimensionar.
class _GripPainter extends CustomPainter {
  final bool destaque;
  _GripPainter({required this.destaque});

  @override
  void paint(Canvas canvas, Size size) {
    final paint = Paint()
      ..color = Colors.white.withValues(alpha: destaque ? 0.75 : 0.4)
      ..strokeWidth = 1.4
      ..strokeCap = StrokeCap.round;
    final w = size.width;
    final h = size.height;
    canvas.drawLine(Offset(w * 0.45, h * 0.95),
        Offset(w * 0.95, h * 0.45), paint);
    canvas.drawLine(Offset(w * 0.65, h * 0.95),
        Offset(w * 0.95, h * 0.65), paint);
    canvas.drawLine(Offset(w * 0.82, h * 0.95),
        Offset(w * 0.95, h * 0.82), paint);
  }

  @override
  bool shouldRepaint(covariant _GripPainter old) => destaque != old.destaque;
}

/// Botão da barra desktop. Ocupa o espaço inteiro do [Expanded] que o contém,
/// então o alvo de clique é gigante. Hover = troca de fundo cinza (nunca branco).
class _BotaoDesktop extends StatefulWidget {
  final IconData icon;
  final Color cor;
  final double iconSize;
  final VoidCallback onTap;

  const _BotaoDesktop({
    required this.icon,
    required this.cor,
    required this.iconSize,
    required this.onTap,
  });

  @override
  State<_BotaoDesktop> createState() => _BotaoDesktopState();
}

class _BotaoDesktopState extends State<_BotaoDesktop> {
  bool _hover = false;
  bool _pressed = false;

  Color get _fundo {
    if (_pressed) return AppColors.surface1;
    if (_hover) return AppColors.surface3;
    return AppColors.surface2;
  }

  @override
  Widget build(BuildContext context) {
    return MouseRegion(
      cursor: SystemMouseCursors.click,
      onEnter: (_) => setState(() => _hover = true),
      onExit: (_) => setState(() {
        _hover = false;
        _pressed = false;
      }),
      child: GestureDetector(
        behavior: HitTestBehavior.opaque,
        onTap: widget.onTap,
        onTapDown: (_) => setState(() => _pressed = true),
        onTapUp: (_) => setState(() => _pressed = false),
        onTapCancel: () => setState(() => _pressed = false),
        child: ColoredBox(
          color: _fundo,
          child: SizedBox.expand(
            child: Center(
              child: Icon(widget.icon, size: widget.iconSize, color: widget.cor),
            ),
          ),
        ),
      ),
    );
  }
}

class _DivisorVertical extends StatelessWidget {
  const _DivisorVertical();

  @override
  Widget build(BuildContext context) {
    return const VerticalDivider(
      width: 1,
      thickness: 1,
      color: AppColors.divider,
    );
  }
}

// ─── Barra de ações mobile/tablet (original) ──────────────────────────────────

class _BarraMobile extends StatelessWidget {
  final MiniPlayerProvider mini;
  const _BarraMobile({required this.mini});

  @override
  Widget build(BuildContext context) {
    return Container(
      width: _kW,
      height: 32,
      color: AppColors.surface1,
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceEvenly,
        children: [
          _BotaoMobile(
            icon: Icons.close,
            color: Colors.redAccent,
            onTap: mini.fechar,
          ),
          _BotaoMobile(
            icon: mini.mutado
                ? Icons.volume_off_rounded
                : Icons.volume_up_rounded,
            color: mini.mutado ? AppColors.accent : Colors.white70,
            onTap: mini.toggleMudo,
          ),
          _BotaoMobile(
            icon: Icons.open_in_full_rounded,
            color: Colors.white70,
            onTap: () => _maximizar(mini),
          ),
        ],
      ),
    );
  }

  static void _maximizar(MiniPlayerProvider mini) {
    final dados = mini.reivindicar();
    if (dados == null) return;
    final (canal, player, controller) = dados;
    rootNavigatorKey.currentState?.push(
      MaterialPageRoute(
        builder: (_) => TelaPlayer.comPlayer(
          canal: canal,
          player: player,
          controller: controller,
        ),
      ),
    );
  }
}

class _BotaoMobile extends StatelessWidget {
  final IconData icon;
  final Color color;
  final VoidCallback onTap;

  const _BotaoMobile({
    required this.icon,
    required this.color,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      behavior: HitTestBehavior.opaque,
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
        child: Icon(icon, size: 18, color: color),
      ),
    );
  }
}

// ─── Badge AO VIVO (compartilhado) ───────────────────────────────────────────

class _LiveBadge extends StatelessWidget {
  final double scale;
  const _LiveBadge({this.scale = 1.0});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: EdgeInsets.symmetric(
        horizontal: 4 * scale,
        vertical: 2 * scale,
      ),
      decoration: BoxDecoration(
        color: Colors.black54,
        borderRadius: BorderRadius.circular(3 * scale),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          DecoratedBox(
            decoration: const BoxDecoration(
              color: Colors.red,
              shape: BoxShape.circle,
            ),
            child: SizedBox(width: 5 * scale, height: 5 * scale),
          ),
          SizedBox(width: 3 * scale),
          Text(
            'AO VIVO',
            style: TextStyle(
              color: Colors.white,
              fontSize: 7 * scale,
              fontWeight: FontWeight.w700,
              letterSpacing: 0.4,
            ),
          ),
        ],
      ),
    );
  }
}
