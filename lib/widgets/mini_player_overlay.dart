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

// ── Desktop (PC) — 100% maior que o mobile ────────────────────────────────────
const double _kWDesktop = 360.0;
const double _kHDesktop = 216.0; // 16:9
const double _kBarraDesktop = 56.0;

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

  @override
  Widget build(BuildContext context) {
    final screen = MediaQuery.sizeOf(context);

    return Positioned(
      left: mini.posicao.dx.clamp(0, screen.width - _kWDesktop),
      top: mini.posicao.dy
          .clamp(0, screen.height - _kHDesktop - _kBarraDesktop),
      child: Material(
        elevation: 12,
        borderRadius: BorderRadius.circular(AppRadius.base),
        clipBehavior: Clip.antiAlias,
        color: Colors.black,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            // ── Vídeo — área de arraste (cursor vira "mover") ─────────────────
            MouseRegion(
              cursor: SystemMouseCursors.move,
              child: GestureDetector(
                behavior: HitTestBehavior.opaque,
                onPanUpdate: (d) => mini.mover(d.delta),
                child: SizedBox(
                  width: _kWDesktop,
                  height: _kHDesktop,
                  child: Stack(
                    children: [
                      Video(
                        controller: mini.controller!,
                        controls: NoVideoControls,
                        width: _kWDesktop,
                        height: _kHDesktop,
                      ),
                      const Positioned(
                        top: 8,
                        left: 8,
                        child: _LiveBadge(scale: 1.8),
                      ),
                    ],
                  ),
                ),
              ),
            ),
            // ── Barra de botões — sempre visível, sem disputa de gestos ───────
            SizedBox(
              width: _kWDesktop,
              height: _kBarraDesktop,
              child: Row(
                children: [
                  Expanded(
                    child: _BotaoDesktop(
                      icon: Icons.open_in_full_rounded,
                      cor: AppColors.textPrimary,
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
                      onTap: mini.toggleMudo,
                    ),
                  ),
                  const _DivisorVertical(),
                  Expanded(
                    child: _BotaoDesktop(
                      icon: Icons.close_rounded,
                      cor: Colors.redAccent,
                      onTap: mini.fechar,
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// Botão da barra desktop. Ocupa o espaço inteiro do [Expanded] que o contém,
/// então o alvo de clique é gigante. Hover = troca de fundo cinza (nunca branco).
class _BotaoDesktop extends StatefulWidget {
  final IconData icon;
  final Color cor;
  final VoidCallback onTap;

  const _BotaoDesktop({
    required this.icon,
    required this.cor,
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
              child: Icon(widget.icon, size: 26, color: widget.cor),
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
    return const SizedBox(
      width: 1,
      height: _kBarraDesktop,
      child: ColoredBox(color: AppColors.divider),
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
