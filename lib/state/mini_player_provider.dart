import 'package:flutter/material.dart';
import 'package:media_kit/media_kit.dart';
import 'package:media_kit_video/media_kit_video.dart';
import '../models/canal.dart';

class MiniPlayerProvider extends ChangeNotifier {
  // ── Tamanho do mini player no desktop ────────────────────────────────────
  // Largura do video. Altura deriva por 16:9 + barra proporcional.
  // Mobile usa tamanho fixo proprio — estes valores so afetam o desktop.
  static const double _kLarguraDesktopMin = 220.0;
  static const double _kLarguraDesktopMax = 800.0;
  static const double _kLarguraDesktopInicial = 360.0;

  Canal? _canal;
  Player? _player;
  VideoController? _controller;
  Offset _posicao = const Offset(16, 16);
  bool _mutado = false;
  bool _mostrarAcoes = false;
  double _volumeAnterior = 100;
  double _larguraDesktop = _kLarguraDesktopInicial;

  Canal? get canal => _canal;
  Player? get player => _player;
  VideoController? get controller => _controller;
  Offset get posicao => _posicao;
  bool get mutado => _mutado;
  bool get mostrarAcoes => _mostrarAcoes;
  bool get ativo => _canal != null;

  /// Largura atual do video no mini player desktop.
  double get larguraDesktop => _larguraDesktop;

  /// Altura do video — sempre 16:9 sobre [larguraDesktop].
  double get alturaVideoDesktop => _larguraDesktop * 9 / 16;

  /// Altura da barra de botoes — proporcional a largura, com limites.
  double get alturaBarraDesktop =>
      (_larguraDesktop * 56 / 360).clamp(40.0, 60.0);

  /// Altura total (video + barra).
  double get alturaTotalDesktop => alturaVideoDesktop + alturaBarraDesktop;

  /// Limites de largura — uteis para a UI clampar antes de chamar [redimensionarDesktop].
  double get larguraDesktopMin => _kLarguraDesktopMin;
  double get larguraDesktopMax => _kLarguraDesktopMax;

  /// Define a largura do mini player desktop. Valor fora do intervalo
  /// permitido e ajustado automaticamente. Sem efeito se a largura nao mudar.
  void redimensionarDesktop(double novaLargura) {
    final clamped =
        novaLargura.clamp(_kLarguraDesktopMin, _kLarguraDesktopMax);
    if (clamped == _larguraDesktop) return;
    _larguraDesktop = clamped;
    notifyListeners();
  }

  /// Inicia o mini player com um [Player] já aberto (transferido de TelaPlayer).
  void iniciar(Canal canal, Player player, VideoController controller) {
    _fecharPlayer();
    _canal = canal;
    _player = player;
    _controller = controller;
    _mutado = false;
    _mostrarAcoes = false;
    notifyListeners();
  }

  void mover(Offset delta) {
    _posicao += delta;
    notifyListeners();
  }

  void alternarAcoes() {
    _mostrarAcoes = !_mostrarAcoes;
    notifyListeners();
  }

  void ocultarAcoes() {
    if (_mostrarAcoes) {
      _mostrarAcoes = false;
      notifyListeners();
    }
  }

  void toggleMudo() {
    if (_player == null) return;
    if (_mutado) {
      _mutado = false;
      _player!.setVolume(_volumeAnterior);
    } else {
      _volumeAnterior = _player!.state.volume;
      _mutado = true;
      _player!.setVolume(0);
    }
    notifyListeners();
  }

  void fechar() {
    _fecharPlayer();
    notifyListeners();
  }

  /// Retorna o canal e transfere o player para TelaPlayer (sem dispor).
  /// Após chamar, o caller é responsável pelo player.
  (Canal, Player, VideoController)? reivindicar() {
    if (_canal == null) return null;
    final c = _canal!;
    final p = _player!;
    final vc = _controller!;
    _canal = null;
    _player = null;
    _controller = null;
    _mostrarAcoes = false;
    notifyListeners();
    return (c, p, vc);
  }

  void _fecharPlayer() {
    final p = _player;
    _canal = null;
    _player = null;
    _controller = null;
    _mostrarAcoes = false;
    if (p != null) {
      // stop() encerra áudio + vídeo na hora; dispose() libera o handle
      // nativo só depois. Sem o stop(), o áudio do libmpv pode continuar
      // tocando de fundo no Windows.
      p.stop().whenComplete(p.dispose);
    }
  }

  @override
  void dispose() {
    _fecharPlayer();
    super.dispose();
  }
}
