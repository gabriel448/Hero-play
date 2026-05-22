import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:media_kit/media_kit.dart';
import 'package:media_kit_video/media_kit_video.dart';
import 'package:provider/provider.dart';
import '../models/canal.dart';
import '../services/player_ao_vivo.dart';
import '../services/player_vod.dart';
import '../state/iptv_provider.dart';
import '../state/mini_player_provider.dart';
import '../theme/app_theme.dart';

class TelaPlayer extends StatefulWidget {
  final Canal canal;
  final Duration? posicaoInicial;
  // Quando vem do mini player, o player já existe e não deve ser recriado.
  final Player? playerExterno;
  final VideoController? controllerExterno;

  const TelaPlayer({
    super.key,
    required this.canal,
    this.posicaoInicial,
    this.playerExterno,
    this.controllerExterno,
  });

  /// Construtor usado ao maximizar o mini player (reutiliza player existente).
  const TelaPlayer.comPlayer({
    super.key,
    required this.canal,
    required Player player,
    required VideoController controller,
  })  : posicaoInicial = null,
        playerExterno = player,
        controllerExterno = controller;

  @override
  State<TelaPlayer> createState() => _TelaPlayerState();
}

enum _Estrategia {
  vlcUa,
  chromeUa,
  semHeaders,
  raw,
}

extension on _Estrategia {
  String get descricao {
    switch (this) {
      case _Estrategia.vlcUa:
        return 'VLC User-Agent (padrao)';
      case _Estrategia.chromeUa:
        return 'Chrome Mobile User-Agent';
      case _Estrategia.semHeaders:
        return 'Sem User-Agent';
      case _Estrategia.raw:
        return 'Sem nenhuma config extra';
    }
  }
}

class _TelaPlayerState extends State<TelaPlayer> {
  late Player _player;
  late VideoController _controller;

  String? _erro;
  String _status = 'Iniciando...';
  _Estrategia _estrategia = _Estrategia.vlcUa;
  final List<String> _log = [];
  bool _iniciado = false;

  DateTime? _inicioTentativa;
  Timer? _timeoutTimer;
  Timer? _atualizadorStatus;
  late IptvProvider _provider;

  StreamSubscription? _subPlaying;
  StreamSubscription? _subBuffering;
  StreamSubscription? _subError;
  StreamSubscription? _subLog;
  StreamSubscription? _subTracks;
  StreamSubscription? _subTrack;
  StreamSubscription? _subDuration;

  Tracks _tracks = Tracks(video: [], audio: [], subtitle: []);
  Track _track = const Track();

  // Quando true, o player foi transferido para o mini player e não deve
  // ser disposto neste widget.
  bool _transferidoParaMini = false;
  // Quando true, usa o player VOD compartilhado: ao sair, só para (não
  // dispõe) — assim ele é reaproveitado no próximo filme.
  bool _compartilhado = false;
  // Permite exatamente um retry silencioso por tentativa iniciada pelo usuário.
  // Resetado apenas em chamadas diretas de _abrirStream() (não no auto-retry),
  // evitando loop infinito caso o stream falhe repetidamente.
  bool _tentouAutoRetry = false;
  // Garante que o seek de retomada aconteça uma única vez.
  bool _seekFeito = false;

  @override
  void initState() {
    super.initState();
    if (widget.playerExterno != null) {
      // Veio do mini player: reutiliza o player que já está tocando.
      _player = widget.playerExterno!;
      _controller = widget.controllerExterno!;
      _iniciado = true;
      _status = 'Tocando';
      // Restaura o volume caso estivesse mutado no mini player.
      _boostarVolume();
    } else if (widget.canal.tipo == TipoCanal.filme) {
      // VOD reutiliza um player único — criar um player novo a cada filme
      // vaza superfícies EGL no Windows ("Failed to create EGL surface").
      _compartilhado = true;
      _player = PlayerVod.instancia.player;
      _controller = PlayerVod.instancia.controller;
      _boostarVolume();
      _abrirStream();
    } else {
      // Canal ao vivo: player compartilhado e reutilizável (mesma razão do
      // VOD). Se for minimizado, é transferido ao mini player — ver
      // _minimizar, que avisa o holder para criar um novo no próximo canal.
      _compartilhado = true;
      _player = PlayerAoVivo.instancia.player;
      _controller = PlayerAoVivo.instancia.controller;
      _boostarVolume();
      _abrirStream();
    }
    _registrarStreams();
  }

  void _boostarVolume() {
    final native = _player.platform;
    if (native is NativePlayer) {
      native.setProperty('volume-max', '200').then((_) {
        if (!mounted) return;
        native.setProperty('volume', '50');
      });
    }
  }

  // Chamado pelo PopScope quando o canal é ao vivo: envia para mini player.
  void _minimizar() {
    final mini = context.read<MiniPlayerProvider>();
    _transferidoParaMini = true;
    // O player passa a pertencer ao mini player; o holder esquece a
    // instância para que o próximo canal ao vivo crie uma nova.
    PlayerAoVivo.instancia.liberarSeAtual(_player);
    mini.iniciar(widget.canal, _player, _controller);
    Navigator.of(context).pop();
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    _provider = context.read<IptvProvider>();
  }

  void _registrarLog(String msg) {
    if (!mounted) return;
    final hora = DateTime.now().toIso8601String().substring(11, 19);
    setState(() {
      _log.add('[$hora] $msg');
      if (_log.length > 30) _log.removeAt(0);
    });
  }

  void _registrarStreams() {
    _subPlaying = _player.stream.playing.listen((tocando) {
      if (!mounted) return;
      if (tocando && !_iniciado) {
        _iniciado = true;
        _timeoutTimer?.cancel();
        _atualizadorStatus?.cancel();
        _registrarLog('playing=true');
        setState(() => _status = 'Tocando');
        _tentarSeekInicial();
      } else if (!tocando && _iniciado) {
        setState(() => _status = 'Pausado');
      }
    });

    _subBuffering = _player.stream.buffering.listen((bufferando) {
      if (!mounted) return;
      if (bufferando) {
        setState(() => _status = 'Buffering...');
      } else if (_iniciado) {
        setState(() => _status = 'Tocando');
      }
    });

    _subError = _player.stream.error.listen((mensagem) {
      _registrarLog('ERROR: $mensagem');
      _timeoutTimer?.cancel();
      _atualizadorStatus?.cancel();
      if (!mounted) return;
      // Retry silencioso na primeira falha, independente de playing=true já
      // ter disparado. Com await _player.stop() em _abrirStream(), playing=true
      // dispara antes do erro (player entra em estado "playing" antes de
      // conectar de fato) — por isso a condição !_iniciado foi removida.
      // deAutoRetry: true impede que o retry reset _tentouAutoRetry, evitando
      // loop infinito caso o stream falhe em todas as tentativas.
      if (!_tentouAutoRetry) {
        _tentouAutoRetry = true;
        _registrarLog('Auto-retry em 300ms...');
        Future.delayed(const Duration(milliseconds: 300), () {
          if (mounted) _abrirStream(deAutoRetry: true);
        });
        return;
      }
      setState(() {
        _erro = mensagem;
        _status = 'Erro';
      });
    });

    _subLog = _player.stream.log.listen((log) {
      if (log.level != 'warn' && log.level != 'error' && log.level != 'fatal') return;
      // Ignora ruido interno do libmpv que nao tem valor de diagnostico.
      if (log.text.contains('_setProperty(osc')) return;
      _registrarLog('mpv[${log.level}] ${log.text}');
    });

    _subTracks = _player.stream.tracks.listen((t) {
      if (!mounted) return;
      setState(() => _tracks = t);
    });

    _subTrack = _player.stream.track.listen((t) {
      if (!mounted) return;
      setState(() => _track = t);
    });

    // A retomada (posicaoInicial) só é confiável depois que a duração é
    // conhecida — aí a mídia está carregada e aceita seek. Seekar cedo
    // demais (ex.: no playing=true) faz o libmpv ignorar e tocar do início.
    _subDuration = _player.stream.duration.listen((_) {
      if (!mounted) return;
      _tentarSeekInicial();
    });
  }

  /// Executa o seek de retomada uma única vez, quando a mídia já está
  /// pronta (duração conhecida). Chamado tanto pelo evento de duração
  /// quanto pelo de playing.
  void _tentarSeekInicial() {
    if (_seekFeito) return;
    final alvo = widget.posicaoInicial;
    if (alvo == null || alvo <= Duration.zero) return;
    final duracao = _player.state.duration;
    if (duracao <= Duration.zero) return; // duração ainda desconhecida
    _seekFeito = true;
    if (alvo >= duracao) return; // alvo inválido — toca do início
    _player.seek(alvo);
    _registrarLog('seek de retomada para ${alvo.inSeconds}s '
        '(duração ${duracao.inSeconds}s)');
  }

  // Codifica @ em segmentos de caminho para evitar que parsers de URL
  // (FFmpeg/libmpv) interpretem user:pass@host em URLs IPTV como
  // http://server/movie/user/pass@Pato/id.mp4 → host=Pato (errado).
  static String _normalizarUrl(String url) {
    final schemeEnd = url.indexOf('://');
    if (schemeEnd < 0) return url;
    final authorityEnd = url.indexOf('/', schemeEnd + 3);
    if (authorityEnd < 0) return url;
    final path = url.substring(authorityEnd);
    if (!path.contains('@')) return url;
    return url.substring(0, authorityEnd) + path.replaceAll('@', '%40');
  }

  // deAutoRetry: true quando chamado pelo retry interno — NÃO reseta
  // _tentouAutoRetry, evitando que o retry também receba um retry (loop).
  // false (padrão) quando iniciado pelo usuário — reseta o flag para que
  // a nova tentativa manual também possa ter seu único retry silencioso.
  Future<void> _abrirStream({bool deAutoRetry = false}) async {
    _timeoutTimer?.cancel();
    _atualizadorStatus?.cancel();
    _iniciado = false;
    _seekFeito = false;
    if (!deAutoRetry) _tentouAutoRetry = false;
    _inicioTentativa = DateTime.now();

    setState(() {
      _erro = null;
      _status = 'Conectando...';
    });

    _registrarLog('=== Estrategia: ${_estrategia.descricao} ===');

    // Define headers conforme estrategia.
    Map<String, String> headers;
    switch (_estrategia) {
      case _Estrategia.vlcUa:
        headers = {'User-Agent': 'VLC/3.0.20 LibVLC/3.0.20'};
        break;
      case _Estrategia.chromeUa:
        headers = {
          'User-Agent':
              'Mozilla/5.0 (Linux; Android 12) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/120.0.0.0 Mobile Safari/537.36',
        };
        break;
      case _Estrategia.semHeaders:
      case _Estrategia.raw:
        headers = {};
        break;
    }

    _registrarLog('headers: ${headers.isEmpty ? "nenhum" : headers.keys.join(",")}');

    try {
      final url = _normalizarUrl(widget.canal.url);
      if (url != widget.canal.url) _registrarLog('url normalizada: $url');

      // Garante estado limpo antes de abrir nova mídia no player compartilhado.
      // O dispose() da sessão anterior chama _player.stop() sem await (Flutter
      // não permite async no dispose). Se esse stop ainda estiver em andamento
      // quando open() for chamado, a transição stop→open emite erros transitórios
      // que seriam mostrados ao usuário. Aguardar stop() aqui absorve o stop
      // pendente e evita esses erros por completo.
      if (_compartilhado) await _player.stop();

      await _player.open(
        Media(url, httpHeaders: headers.isEmpty ? null : headers),
        play: true,
      );

      _atualizadorStatus = Timer.periodic(const Duration(seconds: 1), (_) {
        if (!mounted || _iniciado || _erro != null) return;
        final segs = DateTime.now().difference(_inicioTentativa!).inSeconds;
        setState(() => _status = 'Conectando ha ${segs}s...');
      });

      // Timeout maior para libmpv porque ele aceita streams mais lentos.
      _timeoutTimer = Timer(const Duration(seconds: 20), () {
        if (!mounted || _iniciado || _erro != null) return;
        _registrarLog('TIMEOUT (20s sem inicio de reproducao)');
        _atualizadorStatus?.cancel();
        setState(() {
          _erro = 'Timeout: o player nao conseguiu iniciar em 20 segundos.';
          _status = 'Timeout';
        });
      });
    } catch (e) {
      _registrarLog('Excecao ao abrir: $e');
      setState(() {
        _erro = 'Falha ao abrir stream: $e';
        _status = 'Erro';
      });
    }
  }

  Future<void> _tentarProximaEstrategia() async {
    final proxima = _Estrategia.values.firstWhere(
      (e) => e.index > _estrategia.index,
      orElse: () => _estrategia,
    );
    if (proxima == _estrategia) {
      _mostrarSnack('Ja tentamos todas as estrategias.');
      return;
    }
    setState(() => _estrategia = proxima);
    await _abrirStream();
  }

  Future<void> _cancelarTentativa() async {
    _registrarLog('Cancelado pelo usuario');
    _timeoutTimer?.cancel();
    _atualizadorStatus?.cancel();
    await _player.stop();
    setState(() {
      _erro = 'Tentativa cancelada.';
      _status = 'Cancelado';
    });
  }

  Future<void> _resetarParaPadrao() async {
    setState(() => _estrategia = _Estrategia.vlcUa);
    await _abrirStream();
  }

  Future<void> _copiarUrl() async {
    await Clipboard.setData(ClipboardData(text: widget.canal.url));
    _mostrarSnack('URL copiada');
  }

  void _mostrarSnack(String msg) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(msg)));
  }

  void _mostrarFaixas([BuildContext? ctx]) {
    showModalBottomSheet(
      context: ctx ?? context,
      backgroundColor: AppColors.surface2,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(AppRadius.lg)),
      ),
      isScrollControlled: true,
      builder: (_) => _PainelFaixas(
        player: _player,
        tracks: _tracks,
        track: _track,
      ),
    );
  }

  Widget _buildControlesAoVivo(VideoState state) {
    return _ControlesAoVivo(
      state: state,
      iniciado: _iniciado,
      tracks: _tracks,
      onFaixas: () => _mostrarFaixas(state.context),
      player: _player,
    );
  }

  Widget _buildControls(VideoState state) {
    return Stack(
      children: [
        AdaptiveVideoControls(state),
        if (_iniciado && _tracks.audio.isNotEmpty)
          Positioned(
            top: 0,
            right: 0,
            child: SafeArea(
              child: IconButton(
                icon: const Icon(
                  Icons.closed_caption_rounded,
                  color: Colors.white,
                  shadows: [Shadow(color: Colors.black54, blurRadius: 6)],
                ),
                tooltip: 'Faixas e legendas',
                onPressed: () => _mostrarFaixas(state.context),
              ),
            ),
          ),
      ],
    );
  }

  @override
  void dispose() {
    if (_iniciado && widget.canal.tipo == TipoCanal.filme) {
      final posicaoSeg = _player.state.position.inSeconds;
      if (posicaoSeg > 120) {
        final duracaoSeg = _player.state.duration.inSeconds;
        final fracao = duracaoSeg > 0 ? posicaoSeg / duracaoSeg : 0.0;
        if (fracao < 0.9) {
          _provider
              .salvarProgresso(
                  widget.canal, posicaoSeg, duracaoSeg > 0 ? duracaoSeg : null)
              .ignore();
        } else {
          _provider.removerProgresso(widget.canal).ignore();
        }
      }
    }
    _timeoutTimer?.cancel();
    _atualizadorStatus?.cancel();
    _subPlaying?.cancel();
    _subBuffering?.cancel();
    _subError?.cancel();
    _subLog?.cancel();
    _subTracks?.cancel();
    _subTrack?.cancel();
    _subDuration?.cancel();
    if (_transferidoParaMini) {
      // Player foi para o mini player — segue vivo lá, não mexe.
    } else if (_compartilhado) {
      // Player VOD compartilhado: só para, mantém vivo para o próximo filme.
      _player.stop();
    } else {
      _player.dispose();
    }
    SystemChrome.setPreferredOrientations(DeviceOrientation.values);
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final provider = context.watch<IptvProvider>();
    final favorito = provider.ehFavorito(widget.canal);
    final conectando = _erro == null && !_iniciado;

    final aoVivo = widget.canal.tipo == TipoCanal.aoVivo;

    return PopScope(
      // Intercepta o back em canais ao vivo para minimizar em vez de fechar.
      canPop: !aoVivo,
      onPopInvokedWithResult: (didPop, _) {
        if (!didPop && aoVivo) _minimizar();
      },
      child: Scaffold(
      backgroundColor: AppColors.surface0,
      appBar: AppBar(
        title: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(widget.canal.nome, overflow: TextOverflow.ellipsis),
            Text(
              _status,
              style: const TextStyle(fontSize: 11, color: Colors.white70),
            ),
          ],
        ),
        backgroundColor: AppColors.surface0,
        foregroundColor: Colors.white,
        actions: [
          IconButton(
            icon: const Icon(Icons.copy, color: Colors.white),
            tooltip: 'Copiar URL',
            onPressed: _copiarUrl,
          ),
          IconButton(
            icon: Icon(
              favorito ? Icons.star_rounded : Icons.star_outline_rounded,
              color: favorito ? AppColors.accent : Colors.white,
            ),
            onPressed: () => provider.alternarFavorito(widget.canal),
          ),
        ],
      ),
      body: _erro != null
          ? _ViewErro(
              canal: widget.canal,
              erro: _erro!,
              estrategiaAtual: _estrategia,
              log: _log,
              onTentarMesmo: _abrirStream,
              onTentarOutraEstrategia: _tentarProximaEstrategia,
              onResetar: _resetarParaPadrao,
              onCopiarUrl: _copiarUrl,
            )
          : SafeArea(
              top: false,
              child: Stack(
              alignment: Alignment.center,
              children: [
                Center(
                  child: AspectRatio(
                    aspectRatio: 16 / 9,
                    child: Video(
                      controller: _controller,
                      controls: aoVivo
                          ? _buildControlesAoVivo
                          : _buildControls,
                    ),
                  ),
                ),
                if (conectando)
                  _OverlayConectando(
                    status: _status,
                    estrategia: _estrategia,
                    onCancelar: _cancelarTentativa,
                    onProximaEstrategia: _tentarProximaEstrategia,
                  ),
              ],
            ),
            ),
      ), // Scaffold
    ); // PopScope
  }
}

class _OverlayConectando extends StatelessWidget {
  final String status;
  final _Estrategia estrategia;
  final VoidCallback onCancelar;
  final VoidCallback onProximaEstrategia;

  const _OverlayConectando({
    required this.status,
    required this.estrategia,
    required this.onCancelar,
    required this.onProximaEstrategia,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      color: Colors.black.withValues(alpha: 0.7),
      child: Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const CircularProgressIndicator(color: Colors.white),
            const SizedBox(height: 16),
            Text(status, style: const TextStyle(color: Colors.white, fontSize: 16)),
            const SizedBox(height: 4),
            Text(
              estrategia.descricao,
              style: const TextStyle(color: Colors.white60, fontSize: 12),
            ),
            const SizedBox(height: 24),
            Wrap(
              spacing: 8,
              children: [
                OutlinedButton.icon(
                  onPressed: onCancelar,
                  icon: const Icon(Icons.close, color: Colors.white),
                  label: const Text('Cancelar', style: TextStyle(color: Colors.white)),
                  style: OutlinedButton.styleFrom(
                    side: const BorderSide(color: Colors.white70),
                  ),
                ),
                FilledButton.icon(
                  onPressed: onProximaEstrategia,
                  icon: const Icon(Icons.swap_horiz),
                  label: const Text('Outra estrategia'),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}

class _ViewErro extends StatelessWidget {
  final Canal canal;
  final String erro;
  final _Estrategia estrategiaAtual;
  final List<String> log;
  final VoidCallback onTentarMesmo;
  final VoidCallback onTentarOutraEstrategia;
  final VoidCallback onResetar;
  final VoidCallback onCopiarUrl;

  const _ViewErro({
    required this.canal,
    required this.erro,
    required this.estrategiaAtual,
    required this.log,
    required this.onTentarMesmo,
    required this.onTentarOutraEstrategia,
    required this.onResetar,
    required this.onCopiarUrl,
  });

  String get _proximaEstrategiaNome {
    final proxima = _Estrategia.values.firstWhere(
      (e) => e.index > estrategiaAtual.index,
      orElse: () => estrategiaAtual,
    );
    if (proxima == estrategiaAtual) return 'Ja tentamos todas';
    return proxima.descricao;
  }

  @override
  Widget build(BuildContext context) {
    return SingleChildScrollView(
      padding: const EdgeInsets.all(16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          const Icon(Icons.error_outline, color: Colors.white70, size: 56),
          const SizedBox(height: 12),
          const Center(
            child: Text(
              'Falha ao reproduzir',
              style: TextStyle(
                color: Colors.white,
                fontSize: 18,
                fontWeight: FontWeight.w600,
              ),
            ),
          ),
          const SizedBox(height: 16),
          Container(
            padding: const EdgeInsets.all(12),
            decoration: BoxDecoration(
              color: Colors.red.shade900.withValues(alpha: 0.3),
              borderRadius: BorderRadius.circular(8),
              border: Border.all(color: Colors.red.shade700),
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Text(
                  'Erro / Motivo:',
                  style: TextStyle(color: Colors.white70, fontSize: 12),
                ),
                const SizedBox(height: 4),
                SelectableText(
                  erro,
                  style: const TextStyle(
                    color: Colors.white,
                    fontFamily: 'monospace',
                    fontSize: 13,
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(height: 16),
          Container(
            padding: const EdgeInsets.all(12),
            decoration: BoxDecoration(
              color: Colors.grey.shade900,
              borderRadius: BorderRadius.circular(8),
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'Estrategia: ${estrategiaAtual.descricao}',
                  style: const TextStyle(color: Colors.white70, fontSize: 12),
                ),
                const SizedBox(height: 4),
                SelectableText(
                  'URL: ${canal.url}',
                  style: const TextStyle(
                    color: Colors.white60,
                    fontFamily: 'monospace',
                    fontSize: 11,
                  ),
                  maxLines: 3,
                ),
                const SizedBox(height: 4),
                Text(
                  'Tipo: ${canal.tipo.name}',
                  style: const TextStyle(color: Colors.white60, fontSize: 11),
                ),
              ],
            ),
          ),
          const SizedBox(height: 16),
          FilledButton.icon(
            onPressed: onTentarMesmo,
            icon: const Icon(Icons.refresh),
            label: const Text('Tentar novamente'),
          ),
          const SizedBox(height: 8),
          OutlinedButton.icon(
            onPressed: onTentarOutraEstrategia,
            icon: const Icon(Icons.swap_horiz),
            label: Text(_proximaEstrategiaNome),
          ),
          const SizedBox(height: 8),
          OutlinedButton.icon(
            onPressed: onCopiarUrl,
            icon: const Icon(Icons.copy),
            label: const Text('Copiar URL'),
          ),
          if (estrategiaAtual != _Estrategia.vlcUa) ...[
            const SizedBox(height: 8),
            TextButton.icon(
              onPressed: onResetar,
              icon: const Icon(Icons.restart_alt),
              label: const Text('Resetar para estrategia padrao'),
            ),
          ],
          const SizedBox(height: 24),
          ExpansionTile(
            iconColor: Colors.white70,
            collapsedIconColor: Colors.white70,
            title: const Text(
              'Log de diagnostico',
              style: TextStyle(color: Colors.white70, fontSize: 13),
            ),
            children: [
              Container(
                padding: const EdgeInsets.all(8),
                decoration: BoxDecoration(
                  color: Colors.black,
                  borderRadius: BorderRadius.circular(4),
                ),
                child: SelectableText(
                  log.isEmpty ? '(vazio)' : log.join('\n'),
                  style: const TextStyle(
                    color: Colors.greenAccent,
                    fontFamily: 'monospace',
                    fontSize: 11,
                  ),
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }
}

// ─── Controles canal ao vivo (toque → fullscreen/CC, sem barra de progresso) ─

class _ControlesAoVivo extends StatefulWidget {
  final VideoState state;
  final bool iniciado;
  final Tracks tracks;
  final VoidCallback onFaixas;
  final Player player;

  const _ControlesAoVivo({
    required this.state,
    required this.iniciado,
    required this.tracks,
    required this.onFaixas,
    required this.player,
  });

  @override
  State<_ControlesAoVivo> createState() => _ControlesAoVivoState();
}

class _ControlesAoVivoState extends State<_ControlesAoVivo> {
  bool _visivel = false;
  Timer? _timer;
  double _volume = 50.0;
  StreamSubscription<double>? _subVolume;

  @override
  void initState() {
    super.initState();
    _volume = widget.player.state.volume;
    _subVolume = widget.player.stream.volume.listen((v) {
      if (mounted) setState(() => _volume = v);
    });
  }

  @override
  void dispose() {
    _timer?.cancel();
    _subVolume?.cancel();
    super.dispose();
  }

  void _onTap() {
    setState(() => _visivel = !_visivel);
    if (_visivel) _resetTimer();
  }

  void _resetTimer() {
    _timer?.cancel();
    _timer = Timer(const Duration(seconds: 3), () {
      if (mounted) setState(() => _visivel = false);
    });
  }

  @override
  Widget build(BuildContext context) {
    final emTela = isFullscreen(context);
    return GestureDetector(
      behavior: HitTestBehavior.opaque,
      onTap: _onTap,
      child: AnimatedOpacity(
        opacity: _visivel ? 1.0 : 0.0,
        duration: const Duration(milliseconds: 200),
        child: IgnorePointer(
          ignoring: !_visivel,
          child: Stack(
            children: [
              Container(color: Colors.black38),
              const Positioned(
                top: 12,
                left: 12,
                child: _BadgeAoVivo(),
              ),
              // Barra inferior: volume (esquerda) + CC/fullscreen (direita).
              Positioned(
                bottom: 4,
                left: 4,
                right: 4,
                child: SafeArea(
                  child: Row(
                    children: [
                      // ── Volume ───────────────────────────────────────────
                      Icon(
                        _volume == 0
                            ? Icons.volume_off_rounded
                            : Icons.volume_up_rounded,
                        color: Colors.white,
                        size: 20,
                      ),
                      Expanded(
                        child: SliderTheme(
                          data: SliderTheme.of(context).copyWith(
                            activeTrackColor: Colors.white,
                            inactiveTrackColor: Colors.white30,
                            thumbColor: Colors.white,
                            overlayColor: Colors.white24,
                            trackHeight: 2.0,
                            thumbShape: const RoundSliderThumbShape(
                              enabledThumbRadius: 6,
                            ),
                          ),
                          child: Slider(
                            // max = 150 para manter o boost configurado.
                            value: _volume.clamp(0.0, 150.0),
                            min: 0,
                            max: 150,
                            onChanged: (v) => widget.player.setVolume(v),
                            // Pausa o auto-hide enquanto arrasta o slider.
                            onChangeStart: (_) => _timer?.cancel(),
                            onChangeEnd: (_) => _resetTimer(),
                          ),
                        ),
                      ),
                      // ── CC e Fullscreen ──────────────────────────────────
                      if (widget.iniciado && widget.tracks.audio.isNotEmpty)
                        IconButton(
                          icon: const Icon(
                            Icons.closed_caption_rounded,
                            color: Colors.white,
                          ),
                          tooltip: 'Faixas e legendas',
                          onPressed: widget.onFaixas,
                        ),
                      IconButton(
                        icon: Icon(
                          emTela
                              ? Icons.fullscreen_exit_rounded
                              : Icons.fullscreen_rounded,
                          color: Colors.white,
                        ),
                        tooltip: emTela ? 'Sair da tela cheia' : 'Tela cheia',
                        onPressed: () => toggleFullscreen(context),
                      ),
                    ],
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

// ─── Badge AO VIVO ───────────────────────────────────────────────────────────

class _BadgeAoVivo extends StatelessWidget {
  const _BadgeAoVivo();

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
      decoration: BoxDecoration(
        color: Colors.black54,
        borderRadius: BorderRadius.circular(4),
      ),
      child: const Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          DecoratedBox(
            decoration: BoxDecoration(
              color: Colors.red,
              shape: BoxShape.circle,
            ),
            child: SizedBox(width: 8, height: 8),
          ),
          SizedBox(width: 5),
          Text(
            'AO VIVO',
            style: TextStyle(
              color: Colors.white,
              fontSize: 11,
              fontWeight: FontWeight.w700,
              letterSpacing: 0.6,
            ),
          ),
        ],
      ),
    );
  }
}

// ─── Painel de faixas e legendas ─────────────────────────────────────────────

class _PainelFaixas extends StatefulWidget {
  final Player player;
  final Tracks tracks;
  final Track track;

  const _PainelFaixas({
    required this.player,
    required this.tracks,
    required this.track,
  });

  @override
  State<_PainelFaixas> createState() => _PainelFaixasState();
}

class _PainelFaixasState extends State<_PainelFaixas> {
  late AudioTrack _audio;
  late SubtitleTrack _subtitle;

  @override
  void initState() {
    super.initState();
    _audio = widget.track.audio;
    _subtitle = widget.track.subtitle;
  }

  String _labelAudio(AudioTrack t) {
    if (t.id == 'auto') return 'Automático';
    final parts = <String>[];
    if (t.title != null && t.title!.isNotEmpty) parts.add(t.title!);
    if (t.language != null && t.language!.isNotEmpty) {
      parts.add(t.language!.toUpperCase());
    }
    return parts.isEmpty ? 'Faixa ${t.id}' : parts.join(' · ');
  }

  String _labelLegenda(SubtitleTrack t) {
    if (t.id == 'no') return 'Desativar';
    if (t.id == 'auto') return 'Automático';
    final parts = <String>[];
    if (t.title != null && t.title!.isNotEmpty) parts.add(t.title!);
    if (t.language != null && t.language!.isNotEmpty) {
      parts.add(t.language!.toUpperCase());
    }
    return parts.isEmpty ? 'Legenda ${t.id}' : parts.join(' · ');
  }

  @override
  Widget build(BuildContext context) {
    final audioTracks = widget.tracks.audio.where((t) => t.id != 'auto' && t.id != 'no').toList();
    final subTracks = widget.tracks.subtitle.where((t) => t.id != 'no' && t.id != 'auto').toList();
    final temAudio = audioTracks.isNotEmpty;
    final temLegenda = subTracks.isNotEmpty;

    return SafeArea(
      child: Padding(
        padding: const EdgeInsets.fromLTRB(
          AppSpacing.base,
          AppSpacing.base,
          AppSpacing.base,
          AppSpacing.lg,
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // Handle
            Center(
              child: Container(
                width: 36,
                height: 4,
                margin: const EdgeInsets.only(bottom: AppSpacing.base),
                decoration: BoxDecoration(
                  color: AppColors.outlineSubtle,
                  borderRadius: BorderRadius.circular(AppRadius.pill),
                ),
              ),
            ),
            Text(
              'Faixas e Legendas',
              style: Theme.of(context).textTheme.titleMedium,
            ),
            const SizedBox(height: AppSpacing.lg),

            // ── Áudio ─────────────────────────────────────────────────────
            if (temAudio) ...[
              _SecaoLabel('ÁUDIO'),
              const SizedBox(height: AppSpacing.xs),
              // "Auto" sempre disponível
              _ItemFaixa(
                rotulo: 'Automático',
                selecionado: _audio.id == 'auto',
                onTap: () async {
                  final t = AudioTrack.auto();
                  await widget.player.setAudioTrack(t);
                  setState(() => _audio = t);
                },
              ),
              ...audioTracks.map(
                (t) => _ItemFaixa(
                  rotulo: _labelAudio(t),
                  selecionado: _audio.id == t.id,
                  onTap: () async {
                    await widget.player.setAudioTrack(t);
                    setState(() => _audio = t);
                  },
                ),
              ),
              const SizedBox(height: AppSpacing.base),
            ],

            // ── Legendas ──────────────────────────────────────────────────
            if (temLegenda) ...[
              _SecaoLabel('LEGENDAS'),
              const SizedBox(height: AppSpacing.xs),
              _ItemFaixa(
                rotulo: 'Desativar',
                selecionado: _subtitle.id == 'no',
                onTap: () async {
                  final t = SubtitleTrack.no();
                  await widget.player.setSubtitleTrack(t);
                  setState(() => _subtitle = t);
                },
              ),
              ...subTracks.map(
                (t) => _ItemFaixa(
                  rotulo: _labelLegenda(t),
                  selecionado: _subtitle.id == t.id,
                  onTap: () async {
                    await widget.player.setSubtitleTrack(t);
                    setState(() => _subtitle = t);
                  },
                ),
              ),
            ],

            if (!temAudio && !temLegenda)
              Padding(
                padding: const EdgeInsets.symmetric(vertical: AppSpacing.lg),
                child: Center(
                  child: Text(
                    'Nenhuma faixa alternativa disponível',
                    style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                          color: AppColors.textSecondary,
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

class _SecaoLabel extends StatelessWidget {
  final String texto;
  const _SecaoLabel(this.texto);

  @override
  Widget build(BuildContext context) {
    return Text(
      texto,
      style: Theme.of(context).textTheme.labelSmall?.copyWith(
            color: AppColors.textTertiary,
            letterSpacing: 0.6,
          ),
    );
  }
}

class _ItemFaixa extends StatelessWidget {
  final String rotulo;
  final bool selecionado;
  final VoidCallback onTap;

  const _ItemFaixa({
    required this.rotulo,
    required this.selecionado,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(AppRadius.sm),
      child: Padding(
        padding: const EdgeInsets.symmetric(
          horizontal: AppSpacing.sm,
          vertical: AppSpacing.md,
        ),
        child: Row(
          children: [
            Icon(
              selecionado
                  ? Icons.radio_button_checked_rounded
                  : Icons.radio_button_unchecked_rounded,
              size: 20,
              color: selecionado ? AppColors.accent : AppColors.textTertiary,
            ),
            const SizedBox(width: AppSpacing.md),
            Expanded(
              child: Text(
                rotulo,
                style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                      color: selecionado
                          ? AppColors.textPrimary
                          : AppColors.textSecondary,
                      fontWeight: selecionado ? FontWeight.w600 : null,
                    ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}