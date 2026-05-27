import 'dart:io';
import 'package:flutter/material.dart';
import 'package:media_kit_video/media_kit_video.dart';
import 'package:provider/provider.dart';
import '../screens/tela_player.dart';
import '../state/mini_player_provider.dart';
import '../theme/app_theme.dart';
import '../utils/nav_keys.dart';

// ── Mobile / tablet (mini player flutuante) ──────────────────────────────────
// No desktop o mini player foi substituido pelo player embutido fixo
// dentro de TelaCanais — ver lib/widgets/player_embutido_desktop.dart.
const double _kW = 180.0;
const double _kH = 108.0; // 16:9

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
    // No desktop o mini player flutuante foi substituido pelo player embutido
    // fixo dentro da TelaCanais (PlayerEmbutidoDesktop). Nada e renderizado
    // aqui — o overlay vira no-op pra essa plataforma.
    if (_isDesktop) return const SizedBox.shrink();

    final mini = context.watch<MiniPlayerProvider>();
    if (!mini.ativo) return const SizedBox.shrink();

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
  const _LiveBadge();

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 2),
      decoration: BoxDecoration(
        color: Colors.black54,
        borderRadius: BorderRadius.circular(3),
      ),
      child: const Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          DecoratedBox(
            decoration: BoxDecoration(
              color: Colors.red,
              shape: BoxShape.circle,
            ),
            child: SizedBox(width: 5, height: 5),
          ),
          SizedBox(width: 3),
          Text(
            'AO VIVO',
            style: TextStyle(
              color: Colors.white,
              fontSize: 7,
              fontWeight: FontWeight.w700,
              letterSpacing: 0.4,
            ),
          ),
        ],
      ),
    );
  }
}
