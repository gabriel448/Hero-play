import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:media_kit/media_kit.dart';
import 'package:media_kit_video/media_kit_video.dart';
import 'package:provider/provider.dart';
import '../models/canal.dart';
import '../state/iptv_provider.dart';
import '../theme/app_theme.dart';

/// Tela do player usando media_kit (engine libmpv - mesmo motor do mpv/VLC).
///
/// Diferente do better_player (que usa ExoPlayer), o libmpv suporta praticamente
/// todos os formatos exoticos comuns em IPTV: MPEG-TS, RTSP, HLS sem .m3u8, etc.
///
/// Mantemos as estrategias de retry com diferentes User-Agents porque alguns
/// servidores IPTV exigem UA especifico.
class TelaPlayer extends StatefulWidget {
  final Canal canal;
  const TelaPlayer({super.key, required this.canal});

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

  StreamSubscription? _subPlaying;
  StreamSubscription? _subBuffering;
  StreamSubscription? _subError;
  StreamSubscription? _subLog;

  @override
  void initState() {
    super.initState();
    _player = Player();
    _controller = VideoController(_player);
    _registrarStreams();
    _abrirStream();
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
      if (tocando) {
        _iniciado = true;
        _timeoutTimer?.cancel();
        _atualizadorStatus?.cancel();
        _registrarLog('playing=true');
        setState(() => _status = 'Tocando');
      } else if (_iniciado) {
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
      setState(() {
        _erro = mensagem;
        _status = 'Erro';
      });
    });

    _subLog = _player.stream.log.listen((log) {
      // Filtra so warnings/errors para nao poluir.
      if (log.level == 'warn' || log.level == 'error' || log.level == 'fatal') {
        _registrarLog('mpv[${log.level}] ${log.text}');
      }
    });
  }

  Future<void> _abrirStream() async {
    _timeoutTimer?.cancel();
    _atualizadorStatus?.cancel();
    _iniciado = false;
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
      await _player.open(
        Media(widget.canal.url, httpHeaders: headers.isEmpty ? null : headers),
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

  @override
  void dispose() {
    _timeoutTimer?.cancel();
    _atualizadorStatus?.cancel();
    _subPlaying?.cancel();
    _subBuffering?.cancel();
    _subError?.cancel();
    _subLog?.cancel();
    _player.dispose();
    SystemChrome.setPreferredOrientations(DeviceOrientation.values);
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final provider = context.watch<IptvProvider>();
    final favorito = provider.ehFavorito(widget.canal);
    final conectando = _erro == null && !_iniciado;

    return Scaffold(
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
          : Stack(
              alignment: Alignment.center,
              children: [
                Center(
                  child: AspectRatio(
                    aspectRatio: 16 / 9,
                    child: Video(
                      controller: _controller,
                      controls: AdaptiveVideoControls,
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
    );
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