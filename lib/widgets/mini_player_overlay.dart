import 'dart:async';
import 'dart:io';
import 'package:flutter/material.dart';
import 'package:media_kit_video/media_kit_video.dart';
import 'package:provider/provider.dart';
import '../models/canal.dart';
import '../screens/tela_player.dart';
import '../state/iptv_provider.dart';
import '../state/mini_player_provider.dart';
import '../theme/app_theme.dart';
import '../utils/layout.dart';
import '../utils/nav_keys.dart';

// ── Mobile / tablet (mini player flutuante) ──────────────────────────────────
// No desktop o mini player foi substituido pelo player embutido fixo
// dentro de TelaCanais — ver lib/widgets/player_embutido_desktop.dart.
// No tablet landscape o mini player também é substituído pelo layout 3 colunas.
const double _kWPhone = 180.0;
const double _kHPhone = 108.0; // 16:9
const double _kBarHPhone = 32.0;
const double _kWTablet = 360.0; // 2× phone
const double _kHTablet = 216.0; // 2× phone
const double _kBarHTablet = 48.0;

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

class _MiniFloat extends StatefulWidget {
  const _MiniFloat();

  @override
  State<_MiniFloat> createState() => _MiniFloatState();
}

class _MiniFloatState extends State<_MiniFloat> with WidgetsBindingObserver {
  // Um filme que segue tocando no mini player tambem precisa gravar onde parou
  // — senao o progresso congela no instante em que a TelaPlayer foi minimizada.
  Timer? _timerProgresso;
  static const _intervalo = Duration(seconds: 15);

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _timerProgresso = Timer.periodic(_intervalo, (_) => _salvarProgresso());
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    super.didChangeAppLifecycleState(state);
    if (state == AppLifecycleState.paused ||
        state == AppLifecycleState.inactive ||
        state == AppLifecycleState.hidden) {
      _salvarProgresso();
    }
  }

  @override
  void dispose() {
    _timerProgresso?.cancel();
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }

  void _salvarProgresso() {
    if (!mounted) return;
    final mini = context.read<MiniPlayerProvider>();
    salvarProgressoMini(context, mini);
  }

  static bool get _isDesktop =>
      Platform.isWindows || Platform.isMacOS || Platform.isLinux;

  @override
  Widget build(BuildContext context) {
    // Desktop: substituído pelo PlayerEmbutidoDesktop fixo na TelaCanais.
    if (_isDesktop) return const SizedBox.shrink();

    // Tablet landscape: substituído pelo layout 3 colunas — mini player oculto.
    final tablet = isTablet(context);
    if (tablet &&
        MediaQuery.orientationOf(context) == Orientation.landscape) {
      return const SizedBox.shrink();
    }

    final mini = context.watch<MiniPlayerProvider>();
    if (!mini.ativo) return const SizedBox.shrink();

    final kW = tablet ? _kWTablet : _kWPhone;
    final kH = tablet ? _kHTablet : _kHPhone;
    final kBarH = tablet ? _kBarHTablet : _kBarHPhone;
    final screenSize = MediaQuery.sizeOf(context);

    return Positioned(
      left: mini.posicao.dx.clamp(0, screenSize.width - kW),
      top: mini.posicao.dy.clamp(0, screenSize.height - kH - kBarH),
      child: GestureDetector(
        onPanUpdate: (d) => mini.mover(d.delta),
        onTap: mini.alternarAcoes,
        child: Material(
          elevation: 8,
          borderRadius: BorderRadius.circular(AppRadius.base),
          clipBehavior: Clip.antiAlias,
          color: Colors.black,
          child: SizedBox(
            width: kW,
            height: kH + (mini.mostrarAcoes ? kBarH : 0),
            child: Column(
              children: [
                SizedBox(
                  width: kW,
                  height: kH,
                  child: Stack(
                    children: [
                      Video(
                        controller: mini.controller!,
                        controls: NoVideoControls,
                        width: kW,
                        height: kH,
                      ),
                      Positioned(
                        top: 4,
                        left: 4,
                        child: _LiveBadge(),
                      ),
                    ],
                  ),
                ),
                if (mini.mostrarAcoes)
                  _BarraMobile(mini: mini, width: kW, height: kBarH),
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
  final double width;
  final double height;
  const _BarraMobile({required this.mini, required this.width, required this.height});

  @override
  Widget build(BuildContext context) {
    return Container(
      width: width,
      height: height,
      color: AppColors.surface1,
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceEvenly,
        children: [
          _BotaoMobile(
            icon: Icons.close,
            color: Colors.redAccent,
            onTap: () {
              // Grava antes de matar o player: depois do fechar() nao ha mais
              // posicao para ler.
              salvarProgressoMini(context, mini);
              mini.fechar();
            },
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


/// Grava o progresso do VOD que esta tocando no mini player. Nao faz nada para
/// canal ao vivo (nao ha onde retomar) nem antes de 2 min de reproducao — o
/// mesmo criterio da TelaPlayer.
void salvarProgressoMini(BuildContext context, MiniPlayerProvider mini) {
  final canal = mini.canal;
  final player = mini.player;
  if (canal == null || player == null) return;
  if (canal.tipo != TipoCanal.filme) return;
  final posicaoSeg = player.state.position.inSeconds;
  if (posicaoSeg <= 120) return;
  final duracaoSeg = player.state.duration.inSeconds;
  final fracao = duracaoSeg > 0 ? posicaoSeg / duracaoSeg : 0.0;
  final provider = context.read<IptvProvider>();
  if (fracao < 0.9) {
    provider
        .salvarProgresso(canal, posicaoSeg, duracaoSeg > 0 ? duracaoSeg : null,
            notificar: false)
        .ignore();
  } else {
    provider.removerProgresso(canal, notificar: false).ignore();
  }
}
