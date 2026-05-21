import 'package:flutter/material.dart';
import 'package:media_kit/media_kit.dart';
import 'package:media_kit_video/media_kit_video.dart';
import '../models/canal.dart';

class MiniPlayerProvider extends ChangeNotifier {
  Canal? _canal;
  Player? _player;
  VideoController? _controller;
  Offset _posicao = const Offset(16, 16);
  bool _mutado = false;
  bool _mostrarAcoes = false;
  double _volumeAnterior = 100;

  Canal? get canal => _canal;
  Player? get player => _player;
  VideoController? get controller => _controller;
  Offset get posicao => _posicao;
  bool get mutado => _mutado;
  bool get mostrarAcoes => _mostrarAcoes;
  bool get ativo => _canal != null;

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
    _player?.dispose();
    _canal = null;
    _player = null;
    _controller = null;
    _mostrarAcoes = false;
  }

  @override
  void dispose() {
    _fecharPlayer();
    super.dispose();
  }
}
