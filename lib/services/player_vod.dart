import 'package:media_kit/media_kit.dart';
import 'package:media_kit_video/media_kit_video.dart';

/// Player único e reutilizável para conteúdo VOD (filmes e episódios).
///
/// Criar um [Player]/[VideoController] novo a cada vídeo vaza superfícies
/// EGL no Windows — depois de alguns filmes aparece "Failed to create EGL
/// surface" e a reprodução passa a falhar de forma intermitente. Reutilizando
/// uma única instância, existe no máximo UMA superfície de vídeo VOD durante
/// toda a sessão.
///
/// VOD nunca usa o mini player (só canais ao vivo minimizam), então um único
/// player serve: há no máximo um [TelaPlayer] de VOD vivo por vez.
class PlayerVod {
  PlayerVod._();
  static final PlayerVod instancia = PlayerVod._();

  Player? _player;
  VideoController? _controller;

  /// Player compartilhado — criado na primeira reprodução de VOD.
  Player get player => _player ??= Player();

  /// VideoController compartilhado — uma única superfície de vídeo.
  VideoController get controller => _controller ??= VideoController(player);
}
