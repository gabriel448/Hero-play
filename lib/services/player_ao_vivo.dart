import 'dart:io';

import 'package:media_kit/media_kit.dart';
import 'package:media_kit_video/media_kit_video.dart';

/// Player reutilizável para canais ao vivo em tela cheia.
///
/// Como em [PlayerVod], evita o vazamento de superfícies EGL no Windows
/// causado por criar um [Player]/[VideoController] novo a cada canal aberto
/// ("Failed to create EGL surface" depois de várias aberturas).
///
/// Diferença para o VOD: um canal ao vivo pode ser transferido para o mini
/// player ao minimizar. Nesse caso [liberarSeAtual] é chamado — o player
/// passa a pertencer ao mini player e o próximo canal cria uma instância
/// nova. No uso comum (abrir e fechar canais em tela cheia, sem minimizar)
/// a mesma instância é sempre reaproveitada — sem churn, sem vazamento.
class PlayerAoVivo {
  PlayerAoVivo._();
  static final PlayerAoVivo instancia = PlayerAoVivo._();

  Player? _player;
  VideoController? _controller;

  /// Player compartilhado — criado sob demanda e configurado uma unica vez.
  Player get player {
    if (_player == null) {
      _player = Player();
      _configurar(_player!);
    }
    return _player!;
  }

  /// VideoController compartilhado — uma única superfície de vídeo.
  VideoController get controller => _controller ??= VideoController(player);

  /// Aplica propriedades mpv que evitam falhas conhecidas em Android.
  ///
  /// cache=no  — desativa cache em disco (desnecessario para live e causa
  ///             "Failed to create file cache" quando o diretorio temp nao
  ///             e acessivel no Android).
  ///
  /// hwdec=mediacodec-copy (Android) — decodifica em hardware mas copia o
  ///             frame para memoria do sistema em vez de usar uma Surface
  ///             direta, evitando "h264_mediacodec: Both surface and
  ///             native_window are NULL" quando o EPG roda em background
  ///             (isolate + Hive) e causa pressao de memoria.
  void _configurar(Player p) {
    final native = p.platform;
    if (native is! NativePlayer) return;
    native.setProperty('cache', 'no');
    if (Platform.isAndroid) native.setProperty('hwdec', 'mediacodec-copy');
  }

  /// Esquece a instância atual se ela for [p] — usado quando esse player
  /// foi transferido ao mini player. O próximo acesso cria uma nova.
  void liberarSeAtual(Player p) {
    if (identical(_player, p)) {
      _player = null;
      _controller = null;
    }
  }
}
