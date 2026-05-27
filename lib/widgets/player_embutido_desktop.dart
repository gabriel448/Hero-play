import 'dart:async';

import 'package:flutter/material.dart';
import 'package:media_kit/media_kit.dart';
import 'package:media_kit_video/media_kit_video.dart';
import 'package:provider/provider.dart';

import '../models/canal.dart';
import '../models/programa.dart';
import '../screens/tela_player.dart';
import '../services/player_ao_vivo.dart';
import '../services/servico_epg.dart';
import '../state/iptv_provider.dart';
import '../theme/app_theme.dart';
import '../utils/nav_keys.dart';
import 'modal_programacao.dart';

/// Player embutido fixo no canto direito da TelaCanais no desktop.
///
/// - Observa [IptvProvider.canalSelecionadoDesktop]; quando o usuario clica
///   em outro canal, troca o stream automaticamente.
/// - Reusa o singleton [PlayerAoVivo] — o mesmo player que TelaPlayer usa,
///   permitindo "maximizar" (push em TelaPlayer) sem perder o stream.
/// - Mostra a programacao do canal (estilo modal — blocos separados) embaixo
///   do video.
class PlayerEmbutidoDesktop extends StatefulWidget {
  const PlayerEmbutidoDesktop({super.key});

  @override
  State<PlayerEmbutidoDesktop> createState() => _PlayerEmbutidoDesktopState();
}

class _PlayerEmbutidoDesktopState extends State<PlayerEmbutidoDesktop> {
  Player? _player;
  VideoController? _controller;
  Canal? _canalAberto;
  bool _iniciado = false;
  String _status = 'Iniciando...';
  String? _erro;

  /// True enquanto TelaPlayer esta empilhada por cima — o video deste widget
  /// e substituido por um placeholder pra evitar conflito de duas Video
  /// widgets na mesma VideoController.
  bool _maximizado = false;
  bool _tentouAutoRetry = false;
  bool _retryPendente = false;

  StreamSubscription<bool>? _subPlaying;
  StreamSubscription<bool>? _subBuffering;
  StreamSubscription<String>? _subError;

  void _garantirPlayer() {
    if (_player != null) return;
    _player = PlayerAoVivo.instancia.player;
    _controller = PlayerAoVivo.instancia.controller;
    final native = _player!.platform;
    if (native is NativePlayer) {
      native.setProperty('volume-max', '200').then((_) {
        if (!mounted) return;
        native.setProperty('volume', '60');
      });
    }
    _subPlaying = _player!.stream.playing.listen((tocando) {
      if (!mounted) return;
      if (tocando) {
        setState(() {
          _iniciado = true;
          _status = 'Tocando';
        });
      } else if (_iniciado) {
        setState(() => _status = 'Pausado');
      }
    });
    _subBuffering = _player!.stream.buffering.listen((b) {
      if (!mounted) return;
      if (b) {
        setState(() => _status = 'Buffering...');
      } else if (_iniciado) {
        setState(() => _status = 'Tocando');
      }
    });
    _subError = _player!.stream.error.listen((e) {
      if (!mounted) return;
      if (_retryPendente) return;
      if (!_tentouAutoRetry) {
        _tentouAutoRetry = true;
        _retryPendente = true;
        Future.delayed(const Duration(milliseconds: 300), () {
          if (mounted && _canalAberto != null) {
            _abrirCanal(_canalAberto!, deAutoRetry: true);
          }
        });
        return;
      }
      setState(() {
        _erro = e;
        _status = 'Erro';
      });
    });
  }

  static String _normalizarUrl(String url) {
    final schemeEnd = url.indexOf('://');
    if (schemeEnd < 0) return url;
    final authorityEnd = url.indexOf('/', schemeEnd + 3);
    if (authorityEnd < 0) return url;
    final path = url.substring(authorityEnd);
    if (!path.contains('@')) return url;
    return url.substring(0, authorityEnd) + path.replaceAll('@', '%40');
  }

  Future<void> _abrirCanal(Canal canal, {bool deAutoRetry = false}) async {
    _garantirPlayer();
    _retryPendente = false;
    if (!deAutoRetry) _tentouAutoRetry = false;
    setState(() {
      _erro = null;
      _iniciado = false;
      _status = 'Conectando...';
      _canalAberto = canal;
    });
    // Para canais agrupados, abre a primeira variante (melhor qualidade).
    // O usuario pode trocar qualidade depois ao maximizar para TelaPlayer.
    final variante = canal.agrupado ? canal.variantes.first : canal;
    final url = _normalizarUrl(variante.url);
    final headers = {'User-Agent': 'VLC/3.0.20 LibVLC/3.0.20'};
    try {
      await _player!.stop();
      await _player!.open(Media(url, httpHeaders: headers), play: true);
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _erro = e.toString();
        _status = 'Erro';
      });
    }
  }

  void _fechar() {
    context.read<IptvProvider>().selecionarCanalDesktop(null);
  }

  Future<void> _maximizar() async {
    final canal = _canalAberto;
    final player = _player;
    final controller = _controller;
    if (canal == null || player == null || controller == null) return;
    setState(() => _maximizado = true);
    // Desktop: usa o navigator de conteudo para manter a sidebar visivel.
    // Phone/tablet landscape: cai no navigator raiz.
    final nav = desktopContentNavigatorKey.currentState ??
        rootNavigatorKey.currentState;
    if (nav == null) {
      setState(() => _maximizado = false);
      return;
    }
    await nav.push(
      MaterialPageRoute(
        builder: (_) => TelaPlayer.comPlayer(
          canal: canal,
          player: player,
          controller: controller,
          mantemPlayerAoSair: true,
        ),
      ),
    );
    // Voltou de TelaPlayer — embutido reassume o controle do Video.
    if (!mounted) return;
    setState(() => _maximizado = false);
  }

  @override
  void dispose() {
    _subPlaying?.cancel();
    _subBuffering?.cancel();
    _subError?.cancel();
    // O player vive no singleton — paramos o stream, mas o player em si
    // pode ser reaproveitado pela proxima sessao (ex.: usuario abre canal
    // em outra tela). Nao chamamos dispose() para nao matar o singleton.
    _player?.stop();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final provider = context.watch<IptvProvider>();
    final canal = provider.canalSelecionadoDesktop;
    final idLista = provider.listaAtiva?.id;

    // Sincroniza o player com o canal selecionado. Usamos um post-frame
    // callback para nao chamar setState durante o build.
    if (canal?.id != _canalAberto?.id) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (!mounted) return;
        if (canal == null) {
          _player?.stop();
          setState(() {
            _canalAberto = null;
            _iniciado = false;
            _erro = null;
            _status = 'Iniciando...';
          });
        } else {
          _abrirCanal(canal);
        }
      });
    }

    if (canal == null) {
      return const _EstadoVazio();
    }

    return Container(
      color: AppColors.surface0,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          _Cabecalho(
            canal: canal,
            status: _status,
            onProgramacao: idLista != null &&
                    canal.tvgId != null &&
                    canal.tvgId!.isNotEmpty
                ? () => mostrarModalProgramacao(
                      context,
                      canal: canal,
                      idLista: idLista,
                    )
                : null,
            onMaximizar: _maximizar,
            onFechar: _fechar,
          ),
          // ── Video ────────────────────────────────────────────────────────
          AspectRatio(
            aspectRatio: 16 / 9,
            child: ColoredBox(
              color: Colors.black,
              child: _AreaVideo(
                controller: _controller,
                maximizado: _maximizado,
                conectando: !_iniciado && _erro == null && !_maximizado,
                status: _status,
                erro: _erro,
              ),
            ),
          ),
          // ── EPG embutida ────────────────────────────────────────────────
          Expanded(
            child: idLista != null
                ? _EpgEmbutida(canal: canal, idLista: idLista)
                : const _SemListaParaEpg(),
          ),
        ],
      ),
    );
  }
}

// ─── Cabecalho ────────────────────────────────────────────────────────────────

class _Cabecalho extends StatelessWidget {
  final Canal canal;
  final String status;
  final VoidCallback? onProgramacao;
  final VoidCallback onMaximizar;
  final VoidCallback onFechar;

  const _Cabecalho({
    required this.canal,
    required this.status,
    required this.onProgramacao,
    required this.onMaximizar,
    required this.onFechar,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(
        horizontal: AppSpacing.base,
        vertical: AppSpacing.sm,
      ),
      decoration: const BoxDecoration(
        color: AppColors.surface0,
        border: Border(bottom: BorderSide(color: AppColors.divider, width: 1)),
      ),
      child: Row(
        children: [
          _Logo(canal: canal),
          const SizedBox(width: AppSpacing.md),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(
                  canal.nome,
                  style: Theme.of(context).textTheme.titleSmall,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
                Text(
                  status,
                  style: Theme.of(context).textTheme.labelSmall?.copyWith(
                        color: AppColors.textTertiary,
                      ),
                ),
              ],
            ),
          ),
          // ── Acoes ──────────────────────────────────────────────────────
          if (onProgramacao != null)
            _BotaoIcone(
              icone: Icons.event_note_rounded,
              tooltip: 'Programacao',
              destaque: true,
              onTap: onProgramacao!,
            ),
          const SizedBox(width: AppSpacing.xs),
          _BotaoIcone(
            icone: Icons.open_in_full_rounded,
            tooltip: 'Abrir em tela ampliada',
            onTap: onMaximizar,
          ),
          const SizedBox(width: AppSpacing.xs),
          _BotaoIcone(
            icone: Icons.close_rounded,
            tooltip: 'Fechar player',
            corIcone: AppColors.error,
            onTap: onFechar,
          ),
        ],
      ),
    );
  }
}

class _Logo extends StatelessWidget {
  final Canal canal;
  const _Logo({required this.canal});

  @override
  Widget build(BuildContext context) {
    final tem = canal.logoUrl != null && canal.logoUrl!.isNotEmpty;
    return Container(
      width: 40,
      height: 40,
      decoration: BoxDecoration(
        color: AppColors.surface3,
        borderRadius: BorderRadius.circular(AppRadius.sm),
      ),
      clipBehavior: Clip.antiAlias,
      child: tem
          ? Image.network(
              canal.logoUrl!,
              fit: BoxFit.contain,
              errorBuilder: (_, _, _) => const _LogoFallback(),
            )
          : const _LogoFallback(),
    );
  }
}

class _LogoFallback extends StatelessWidget {
  const _LogoFallback();
  @override
  Widget build(BuildContext context) => const Center(
        child: Icon(
          Icons.live_tv_rounded,
          size: 20,
          color: AppColors.textTertiary,
        ),
      );
}

class _BotaoIcone extends StatefulWidget {
  final IconData icone;
  final String tooltip;
  final VoidCallback onTap;
  final Color? corIcone;
  final bool destaque;

  const _BotaoIcone({
    required this.icone,
    required this.tooltip,
    required this.onTap,
    this.corIcone,
    this.destaque = false,
  });

  @override
  State<_BotaoIcone> createState() => _BotaoIconeState();
}

class _BotaoIconeState extends State<_BotaoIcone> {
  bool _hover = false;

  @override
  Widget build(BuildContext context) {
    final corBase = widget.corIcone ??
        (widget.destaque ? AppColors.accent : AppColors.textPrimary);
    return Tooltip(
      message: widget.tooltip,
      child: MouseRegion(
        cursor: SystemMouseCursors.click,
        onEnter: (_) => setState(() => _hover = true),
        onExit: (_) => setState(() => _hover = false),
        child: GestureDetector(
          onTap: widget.onTap,
          behavior: HitTestBehavior.opaque,
          child: AnimatedContainer(
            duration: AppMotion.fast,
            width: 36,
            height: 36,
            decoration: BoxDecoration(
              color: _hover ? AppColors.surface2 : Colors.transparent,
              borderRadius: BorderRadius.circular(AppRadius.sm),
              border: widget.destaque
                  ? Border.all(
                      color: AppColors.accent.withValues(alpha: 0.45),
                    )
                  : null,
            ),
            child: Icon(widget.icone, size: 18, color: corBase),
          ),
        ),
      ),
    );
  }
}

// ─── Area do video ────────────────────────────────────────────────────────────

class _AreaVideo extends StatelessWidget {
  final VideoController? controller;
  final bool maximizado;
  final bool conectando;
  final String status;
  final String? erro;

  const _AreaVideo({
    required this.controller,
    required this.maximizado,
    required this.conectando,
    required this.status,
    required this.erro,
  });

  @override
  Widget build(BuildContext context) {
    if (maximizado) {
      return const _PlaceholderMaximizado();
    }
    if (erro != null) {
      return _ErroSimples(mensagem: erro!);
    }
    if (controller == null) {
      return const Center(
        child: Text(
          'Iniciando...',
          style: TextStyle(color: Colors.white70),
        ),
      );
    }
    return Stack(
      children: [
        Video(controller: controller!, controls: NoVideoControls),
        if (conectando)
          Container(
            color: Colors.black54,
            alignment: Alignment.center,
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                const CircularProgressIndicator(color: Colors.white),
                const SizedBox(height: AppSpacing.sm),
                Text(
                  status,
                  style: const TextStyle(color: Colors.white, fontSize: 13),
                ),
              ],
            ),
          ),
      ],
    );
  }
}

class _PlaceholderMaximizado extends StatelessWidget {
  const _PlaceholderMaximizado();
  @override
  Widget build(BuildContext context) {
    return Container(
      color: AppColors.surface1,
      alignment: Alignment.center,
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(
            Icons.open_in_full_rounded,
            size: 36,
            color: AppColors.textTertiary,
          ),
          const SizedBox(height: AppSpacing.sm),
          Text(
            'Tocando em tela ampliada',
            style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                  color: AppColors.textSecondary,
                ),
          ),
        ],
      ),
    );
  }
}

class _ErroSimples extends StatelessWidget {
  final String mensagem;
  const _ErroSimples({required this.mensagem});

  @override
  Widget build(BuildContext context) {
    return Container(
      color: Colors.black,
      padding: const EdgeInsets.all(AppSpacing.base),
      alignment: Alignment.center,
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          const Icon(
            Icons.error_outline_rounded,
            color: AppColors.error,
            size: 32,
          ),
          const SizedBox(height: AppSpacing.sm),
          Text(
            'Falha ao reproduzir',
            style: Theme.of(context)
                .textTheme
                .titleSmall
                ?.copyWith(color: Colors.white),
          ),
          const SizedBox(height: 2),
          Text(
            mensagem,
            maxLines: 3,
            overflow: TextOverflow.ellipsis,
            textAlign: TextAlign.center,
            style: const TextStyle(color: Colors.white70, fontSize: 11),
          ),
          const SizedBox(height: AppSpacing.sm),
          Text(
            'Use "Abrir em tela ampliada" para diagnostico.',
            style: const TextStyle(color: Colors.white38, fontSize: 11),
          ),
        ],
      ),
    );
  }
}

// ─── EPG embutida (estilo blocos do modal) ────────────────────────────────────

class _EpgEmbutida extends StatefulWidget {
  final Canal canal;
  final String idLista;

  const _EpgEmbutida({required this.canal, required this.idLista});

  @override
  State<_EpgEmbutida> createState() => _EpgEmbutidaState();
}

class _EpgEmbutidaState extends State<_EpgEmbutida> {
  Timer? _ticker;

  @override
  void initState() {
    super.initState();
    _ticker = Timer.periodic(const Duration(seconds: 30), (_) {
      if (mounted) setState(() {});
    });
  }

  @override
  void dispose() {
    _ticker?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final epg = context.watch<ServicoEpg>();
    final carregando = epg.estaCarregando(widget.idLista);
    final programas = epg.agenda(
      idLista: widget.idLista,
      canal: widget.canal,
    );

    return Container(
      color: AppColors.surface0,
      padding: const EdgeInsets.fromLTRB(
        AppSpacing.base,
        AppSpacing.md,
        AppSpacing.base,
        AppSpacing.md,
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            children: [
              Text(
                'PROGRAMACAO',
                style: Theme.of(context).textTheme.labelSmall?.copyWith(
                      color: AppColors.textTertiary,
                      letterSpacing: 0.6,
                    ),
              ),
              const Spacer(),
              if (programas.isNotEmpty)
                Text(
                  '${programas.length} ${programas.length == 1 ? "item" : "itens"}',
                  style: tabular(
                    Theme.of(context).textTheme.labelSmall?.copyWith(
                          color: AppColors.textTertiary,
                        ),
                  ),
                ),
            ],
          ),
          const SizedBox(height: AppSpacing.sm),
          Expanded(
            child: programas.isEmpty
                ? _EpgVazio(
                    carregando: carregando,
                    temEpg: epg.temEpg(widget.idLista),
                    temTvgId: widget.canal.tvgId != null &&
                        widget.canal.tvgId!.isNotEmpty,
                  )
                : _ListaProgramasComDias(programas: programas),
          ),
        ],
      ),
    );
  }
}

class _ListaProgramasComDias extends StatelessWidget {
  final List<Programa> programas;
  const _ListaProgramasComDias({required this.programas});

  @override
  Widget build(BuildContext context) {
    final agora = DateTime.now();
    String? ultimaData;
    final filhos = <Widget>[];
    for (final p in programas) {
      final rotulo = _rotuloData(p.inicio.toLocal(), agora);
      if (rotulo != ultimaData) {
        filhos.add(_SeparadorDia(rotulo: rotulo));
        ultimaData = rotulo;
      }
      filhos.add(LinhaProgramaBlocos(
        programa: p,
        atual: p.ehAtual(agora),
        versaoLarga: true,
      ));
    }
    return ListView(
      padding: const EdgeInsets.only(bottom: AppSpacing.lg),
      children: filhos,
    );
  }
}

class _SeparadorDia extends StatelessWidget {
  final String rotulo;
  const _SeparadorDia({required this.rotulo});
  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(0, AppSpacing.sm, 0, AppSpacing.xs),
      child: Text(
        rotulo,
        style: Theme.of(context).textTheme.labelSmall?.copyWith(
              color: AppColors.textTertiary,
              letterSpacing: 0.6,
            ),
      ),
    );
  }
}

class _EpgVazio extends StatelessWidget {
  final bool carregando;
  final bool temEpg;
  final bool temTvgId;

  const _EpgVazio({
    required this.carregando,
    required this.temEpg,
    required this.temTvgId,
  });

  @override
  Widget build(BuildContext context) {
    String mensagem;
    if (carregando && !temEpg) {
      mensagem = 'Carregando programacao...';
    } else if (!temEpg) {
      mensagem = 'Sem grade de programacao nesta lista.';
    } else if (!temTvgId) {
      mensagem = 'Este canal nao tem identificador EPG.';
    } else {
      mensagem = 'Nenhum programa proximo encontrado para este canal.';
    }
    return Center(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          if (carregando && !temEpg)
            const CircularProgressIndicator(
              strokeWidth: 2,
              color: AppColors.textTertiary,
            )
          else
            const Icon(
              Icons.event_busy_rounded,
              size: 28,
              color: AppColors.textTertiary,
            ),
          const SizedBox(height: AppSpacing.sm),
          Text(
            mensagem,
            textAlign: TextAlign.center,
            style: Theme.of(context).textTheme.bodySmall?.copyWith(
                  color: AppColors.textTertiary,
                ),
          ),
        ],
      ),
    );
  }
}

class _SemListaParaEpg extends StatelessWidget {
  const _SemListaParaEpg();
  @override
  Widget build(BuildContext context) {
    return Center(
      child: Text(
        'Sem lista ativa.',
        style: Theme.of(context).textTheme.bodySmall?.copyWith(
              color: AppColors.textTertiary,
            ),
      ),
    );
  }
}

// ─── Estado vazio (nenhum canal selecionado) ──────────────────────────────────

class _EstadoVazio extends StatelessWidget {
  const _EstadoVazio();

  @override
  Widget build(BuildContext context) {
    return Container(
      color: AppColors.surface0,
      alignment: Alignment.center,
      padding: const EdgeInsets.all(AppSpacing.xl),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Container(
            width: 80,
            height: 80,
            decoration: BoxDecoration(
              color: AppColors.surface1,
              borderRadius: BorderRadius.circular(AppRadius.lg),
              border: Border.all(color: AppColors.divider),
            ),
            alignment: Alignment.center,
            child: const Icon(
              Icons.live_tv_rounded,
              size: 32,
              color: AppColors.textTertiary,
            ),
          ),
          const SizedBox(height: AppSpacing.base),
          Text(
            'Selecione um canal',
            style: Theme.of(context).textTheme.titleMedium,
          ),
          const SizedBox(height: AppSpacing.xs),
          Text(
            'Clique em um canal da lista ao lado\npara comecar a assistir aqui.',
            textAlign: TextAlign.center,
            style: Theme.of(context).textTheme.bodySmall?.copyWith(
                  color: AppColors.textSecondary,
                  height: 1.5,
                ),
          ),
        ],
      ),
    );
  }
}

String _rotuloData(DateTime data, DateTime agora) {
  final hoje = DateTime(agora.year, agora.month, agora.day);
  final amanha = hoje.add(const Duration(days: 1));
  final dia = DateTime(data.year, data.month, data.day);
  if (dia == hoje) return 'HOJE';
  if (dia == amanha) return 'AMANHA';
  final d = data.day.toString().padLeft(2, '0');
  final m = data.month.toString().padLeft(2, '0');
  return '$d/$m';
}
