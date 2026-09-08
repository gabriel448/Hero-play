import 'dart:async';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:media_kit/media_kit.dart';
import 'package:media_kit_video/media_kit_video.dart';
import 'package:provider/provider.dart';
import 'package:screen_brightness/screen_brightness.dart';
import 'package:volume_controller/volume_controller.dart';
import '../models/canal.dart';
import '../services/player_ao_vivo.dart';
import '../services/player_vod.dart';
import '../services/controle_parental.dart';
import '../state/iptv_provider.dart';
import '../state/mini_player_provider.dart';
import '../state/preferencias_provider.dart';
import '../theme/app_theme.dart';
import '../utils/layout.dart';
import '../utils/qualidade.dart';
import '../widgets/modal_programacao.dart';
import '../widgets/painel_epg.dart';
import '../widgets/seletor_categoria.dart';

class TelaPlayer extends StatefulWidget {
  final Canal canal;
  final Duration? posicaoInicial;
  // Quando vem do mini player ou do player embutido, o player já existe.
  final Player? playerExterno;
  final VideoController? controllerExterno;
  /// Quando true, o ciclo de vida do player nao pertence a este widget — ao
  /// sair, o player NAO e parado nem disposto. Usado pelo player embutido
  /// do desktop, que continua tocando depois que a TelaPlayer e fechada.
  final bool mantemPlayerAoSair;
  /// Lista ordenada de episodios da serie (quando este canal e um episodio).
  /// Habilita o botao "proximo episodio" no fim do episodio atual.
  final List<Canal>? episodiosSerie;

  const TelaPlayer({
    super.key,
    required this.canal,
    this.posicaoInicial,
    this.playerExterno,
    this.controllerExterno,
    this.mantemPlayerAoSair = false,
    this.episodiosSerie,
  });

  /// Construtor usado ao maximizar o mini player ou o player embutido do
  /// desktop (reutiliza player existente).
  const TelaPlayer.comPlayer({
    super.key,
    required this.canal,
    required Player player,
    required VideoController controller,
    this.mantemPlayerAoSair = false,
  })  : posicaoInicial = null,
        playerExterno = player,
        controllerExterno = controller,
        episodiosSerie = null;

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

class _TelaPlayerState extends State<TelaPlayer>
    with WidgetsBindingObserver {
  late Player _player;
  late VideoController _controller;

  // Fonte em uso. Para canais sem fontes alternativas e o proprio widget.canal;
  // para canais com fontes e uma das entradas de Canal.fontes.
  late Canal _fonteAtual;

  // Variante de qualidade em reproducao. Para canais comuns e o proprio
  // widget.canal; para canais agrupados e uma das variantes.
  late Canal _varianteAtual;

  String? _erro;
  String _status = 'Iniciando...';
  _Estrategia _estrategia = _Estrategia.vlcUa;
  final List<String> _log = [];
  bool _iniciado = false;

  DateTime? _inicioTentativa;
  Timer? _timeoutTimer;
  Timer? _atualizadorStatus;
  Timer? _timerBufferingLongo;
  Timer? _timerBufferingCurto;
  Timer? _timerResetContador;
  Timer? _timerNotificacao;
  int _contadorBuffering = 0;
  String? _msgAutoQualidade;
  late IptvProvider _provider;
  late PreferenciasProvider _preferencias;

  StreamSubscription? _subPlaying;
  StreamSubscription? _subBuffering;
  StreamSubscription? _subError;
  StreamSubscription? _subLog;
  StreamSubscription? _subTracks;
  StreamSubscription? _subTrack;
  StreamSubscription? _subDuration;

  Tracks _tracks = Tracks(video: [], audio: [], subtitle: []);
  Track _track = const Track();
  // Visibilidade do botao CC (faixas/legendas). ValueNotifier porque o slot do
  // CC precisa estar SEMPRE presente nos controles do media_kit (que sao
  // construidos uma vez) e so reagir internamente — senao, se os controles
  // forem montados antes das faixas carregarem, o botao so apareceria ao
  // recriar o Video (minimizar+maximizar).
  final ValueNotifier<bool> _temFaixas = ValueNotifier(false);
  // Garante que a auto-selecao de audio (pelo idioma do perfil) rode uma vez
  // por stream, sem sobrescrever uma troca manual posterior do usuario.
  bool _audioAuto = false;

  // ── Proximo episodio (series) ────────────────────────────────────────────
  // Episodio atualmente em reproducao. Muda IN-PLACE ao avancar para o proximo
  // (reabre o stream sem trocar de rota — assim o fullscreen nativo continua).
  late Canal _episodio;
  // Posicao de retomada atual (atualizada ao trocar de episodio).
  Duration? _posicaoInicial;
  // Proximo episodio na ordem da serie (null se nao houver ou nao for serie).
  Canal? _proximoEp;
  // Botao "proximo episodio" visivel (a partir de ~90% do episodio). ValueNotifier
  // porque o fullscreen NATIVO do media_kit roda numa rota separada que nao
  // rebuilda no setState desta tela — o botao reage via ValueListenableBuilder.
  final ValueNotifier<bool> _mostrarProximoEp = ValueNotifier(false);
  // Espelho da visibilidade dos controles do media_kit (para o botao subir/
  // descer junto com a barra). Observado via Listener nao-consumidor.
  final ValueNotifier<bool> _barraVodVisivel = ValueNotifier(false);
  // Visibilidade REAL dos controles do media_kit, reportada pela sentinela que
  // vive dentro deles (o estado do pacote e privado — ver _SentinelaControles).
  bool _mkVisivel = false;
  // Segura as barras enquanto o dedo esta ARRASTANDO volume/brilho, mesmo que
  // os controles do media_kit ja tenham sumido nesse meio tempo.
  bool _arrastandoBarras = false;
  Timer? _timerBarraVod;
  StreamSubscription? _subPosition;
  // Tela cheia do VOD numa rota SO (sem o segundo Video do media_kit): imersivo
  // + paisagem + video preenchendo, AppBar escondida. Botao de minimizar
  // alterna para o modo janela (vertical, copiar URL, etc.). Init true p/ VOD.
  bool _telaCheia = false;
  // Ajuste do video: contain (mostra inteiro, pode sobrar faixa nas laterais em
  // conteudo 16:9) ou cover (preenche cortando). Botao de zoom alterna.
  BoxFit _ajuste = BoxFit.contain;

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
  // True entre "retry agendado" e "retry iniciado": suprime eventos de erro
  // adicionais que o libmpv dispara enquanto a conexão anterior ainda morre,
  // evitando o flash da tela de erro antes do retry limpar o estado.
  bool _retryPendente = false;
  // Fontes (chave nome|url) que ja falharam nesta sessao — usadas para o
  // failover automatico nao repetir a mesma fonte. Limpo ao reproduzir com
  // sucesso e em qualquer abertura iniciada pelo usuario.
  final Set<String> _fontesFalhas = {};
  // Garante que o seek de retomada aconteça uma única vez.
  bool _streamAberto = false;
  bool _seekFeito = false;
  // Grava o progresso de tempos em tempos. Sem isto, o unico ponto de gravacao
  // era o dispose() — e quem fecha o app pelo gesto de "recentes" (ou tem o app
  // morto pelo sistema) NUNCA passa por ele: a sessao inteira era perdida e a
  // serie reabria do comeco.
  Timer? _timerProgresso;
  static const _intervaloSalvarProgresso = Duration(seconds: 15);

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _episodio = widget.canal;
    _posicaoInicial = widget.posicaoInicial;
    _fonteAtual = widget.canal.temFontes ? widget.canal.fontes.first : widget.canal;
    _varianteAtual = _varianteInicial();

    // VOD (filme/episodio): abre direto em TELA CHEIA (imersivo + paisagem +
    // video preenchendo). Botao de minimizar volta ao modo janela.
    if (widget.canal.tipo == TipoCanal.filme) {
      _telaCheia = true;
      _aplicarModoTela();
    }

    _recalcularProximoEp();

    // Controle dos pais: categoria bloqueada => NAO abre o stream. Pede o PIN
    // no primeiro frame (dialogo precisa da arvore montada) e so entao inicia.
    // Este e o ponto unico por onde passam favoritos, historico, busca,
    // categoria e detalhe — gatear aqui cobre todos.
    if (ControleParental.exigePin(context, widget.canal.grupo)) {
      _bloqueadoPorPin = true;
      WidgetsBinding.instance
          .addPostFrameCallback((_) => _pedirLiberacaoParental());
      return;
    }

    _prepararPlayer();
  }

  /// `true` enquanto o conteudo esta travado pelo controle dos pais (nada e
  /// carregado nem exibido).
  bool _bloqueadoPorPin = false;

  Future<void> _pedirLiberacaoParental() async {
    final liberou = await ControleParental.liberar(context, widget.canal.grupo);
    if (!mounted) return;
    if (!liberou) {
      Navigator.of(context).maybePop();
      return;
    }
    setState(() => _bloqueadoPorPin = false);
    _prepararPlayer();
  }

  void _prepararPlayer() {
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
    _iniciarTimerProgresso();
    _registrarStreams();
    _atualizarTemFaixas();
  }

  void _boostarVolume() {
    // O volume agora segue o volume do DISPOSITIVO (barra lateral via
    // volume_controller) tanto ao vivo quanto em VOD. Por isso o player fica em
    // 100% (sem atenuacao propria) — quem regula e o volume do aparelho.
    final native = _player.platform;
    if (native is NativePlayer) {
      native.setProperty('volume-max', '200').then((_) {
        if (!mounted) return;
        native.setProperty('volume', '100');
      });
    } else {
      _player.setVolume(100);
    }
  }

  /// Decide qual variante de qualidade abrir para a [_fonteAtual].
  /// Canal comum: ele mesmo. Canal agrupado: qualidade lembrada ou a melhor.
  Canal _varianteInicial() {
    final fonte = _fonteAtual;
    if (!fonte.agrupado) return fonte;
    final idGrupo = widget.canal.idGrupo;
    if (idGrupo != null) {
      final urlSalva = context.read<IptvProvider>().qualidadePreferida(idGrupo);
      if (urlSalva != null) {
        for (final v in fonte.variantes) {
          if (v.url == urlSalva) return v;
        }
      }
    }
    return fonte.variantes.first;
  }

  /// Troca a qualidade do canal agrupado, reabrindo o stream na variante
  /// escolhida e lembrando a preferencia para as proximas vezes.
  Future<void> _trocarQualidade(Canal variante) async {
    if (variante.url == _varianteAtual.url) return;
    _cancelarTimersBuffering();
    setState(() => _varianteAtual = variante);
    final idGrupo = widget.canal.idGrupo;
    if (idGrupo != null) {
      _provider.salvarQualidadePreferida(idGrupo, variante.url);
    }
    await _abrirStream();
  }

  /// Troca para uma fonte alternativa, reabrindo o stream.
  /// Ao trocar de fonte, escolhe a melhor qualidade disponivel naquela fonte.
  Future<void> _trocarFonte(Canal novaFonte) async {
    if (novaFonte.url == _fonteAtual.url && novaFonte.nome == _fonteAtual.nome) return;
    _cancelarTimersBuffering();
    setState(() {
      _fonteAtual = novaFonte;
      _varianteAtual = novaFonte.agrupado ? novaFonte.variantes.first : novaFonte;
    });
    await _abrirStream();
  }

  void _cancelarTimersBuffering() {
    _timerBufferingLongo?.cancel();
    _timerBufferingLongo = null;
    _timerBufferingCurto?.cancel();
    _timerBufferingCurto = null;
    _timerResetContador?.cancel();
    _timerResetContador = null;
    _contadorBuffering = 0;
  }

  // ── Failover automatico de fonte ─────────────────────────────────────────
  List<Canal> get _fontesDisponiveis =>
      widget.canal.temFontes ? widget.canal.fontes : [widget.canal];

  String _chaveFonte(Canal c) => '${c.nome}|${c.url}';

  Canal? _proximaFonte() {
    for (final f in _fontesDisponiveis) {
      if (!_fontesFalhas.contains(_chaveFonte(f))) return f;
    }
    return null;
  }

  /// Tratamento UNIFICADO de falha do stream (erro do libmpv, excecao ao abrir
  /// ou timeout). Recupera sem incomodar o usuario:
  ///   1) retry silencioso da MESMA fonte (uma vez);
  ///   2) failover automatico para a proxima fonte do canal;
  ///   3) so quando TODAS as fontes falham, mostra o erro padrao.
  /// Ao vivo: status amigavel ("Reconectando…"/"Alterando fonte…") durante a
  /// recuperacao. VOD: recupera em silencio e so mostra o erro no fim.
  /// [pularRetry] pula direto ao failover (usado no timeout, que ja esperou).
  void _tratarFalha(String mensagem, {bool pularRetry = false}) {
    _registrarLog('FALHA: $mensagem');
    _timeoutTimer?.cancel();
    _atualizadorStatus?.cancel();
    if (!mounted) return;
    // Eventos transitorios (entre stop()->open() ou com recuperacao ja
    // agendada) nao contam — evita o flash de erro antes do retry.
    if (!_streamAberto) {
      _registrarLog('falha ignorada (anterior ao open)');
      return;
    }
    if (_retryPendente) {
      _registrarLog('falha suprimida (recuperacao pendente)');
      return;
    }
    final aoVivo = widget.canal.tipo == TipoCanal.aoVivo;

    // 1) Retry silencioso da MESMA fonte (uma unica vez). O primeiro erro
    //    nunca chega ao usuario — fica so no log.
    if (!pularRetry && !_tentouAutoRetry) {
      _tentouAutoRetry = true;
      _retryPendente = true;
      _registrarLog('recuperacao: retry da mesma fonte em 800ms');
      if (aoVivo) setState(() => _status = 'Reconectando…');
      Future.delayed(const Duration(milliseconds: 800), () {
        if (mounted) _abrirStream(deAutoRetry: true);
      });
      return;
    }

    // 2) Failover: a fonte atual falhou de vez — tenta a proxima fonte.
    _fontesFalhas.add(_chaveFonte(_fonteAtual));
    final prox = _proximaFonte();
    if (prox != null) {
      _retryPendente = true;
      _registrarLog('recuperacao: failover -> ${prox.nome}');
      if (aoVivo) {
        _mostrarNotificacaoAutoQualidade('Alterando fonte…');
        setState(() => _status = 'Alterando fonte…');
      }
      Future.delayed(const Duration(milliseconds: 600), () {
        if (!mounted) return;
        setState(() {
          _fonteAtual = prox;
          _varianteAtual = prox.agrupado ? prox.variantes.first : prox;
          _tentouAutoRetry = false; // a nova fonte tem direito ao seu retry
        });
        _abrirStream(deAutoRetry: true); // deAutoRetry: preserva _fontesFalhas
      });
      return;
    }

    // 3) Acabaram as fontes -> erro padrao (vale para ao vivo e VOD).
    _registrarLog('recuperacao: sem mais fontes — exibindo erro');
    setState(() {
      _erro = mensagem;
      _status = 'Erro';
    });
  }

  void _tentarReduzirQualidade(String motivo) {
    if (!mounted || !_fonteAtual.agrupado) return;
    final variantes = _fonteAtual.variantes;
    final indexAtual = variantes.indexWhere((v) => v.url == _varianteAtual.url);
    if (indexAtual < 0 || indexAtual >= variantes.length - 1) return;

    _cancelarTimersBuffering();
    final proxima = variantes[indexAtual + 1];
    final rotulo = _rotuloQualidade(proxima);
    _registrarLog('Auto-qualidade: $motivo → reduzindo para $rotulo');
    _mostrarNotificacaoAutoQualidade('Conexão instável — reduzindo para $rotulo');
    setState(() => _varianteAtual = proxima);
    _abrirStream();
  }

  void _incrementarContadorBuffering() {
    _timerBufferingCurto = null;
    _contadorBuffering++;
    _registrarLog(
        'Auto-qualidade: evento $_contadorBuffering/10 no último minuto');
    _timerResetContador ??= Timer(const Duration(minutes: 1), () {
      _contadorBuffering = 0;
      _timerResetContador = null;
      _registrarLog('Auto-qualidade: contador resetado');
    });
    if (_contadorBuffering >= 10) {
      _tentarReduzirQualidade('$_contadorBuffering travamentos em 1 minuto');
    }
  }

  void _mostrarNotificacaoAutoQualidade(String msg) {
    _timerNotificacao?.cancel();
    setState(() => _msgAutoQualidade = msg);
    _timerNotificacao = Timer(const Duration(seconds: 5), () {
      if (!mounted) return;
      setState(() => _msgAutoQualidade = null);
      _timerNotificacao = null;
    });
  }

  String _rotuloQualidade(Canal v) => detectarQualidade(v.nome).rotulo;

  String get _subtituloPlayer {
    final partes = [_status];
    if (widget.canal.temFontes) {
      final idx = widget.canal.fontes.indexWhere((f) => f.nome == _fonteAtual.nome);
      if (idx > 0) partes.add('Fonte ${idx + 1}');
    }
    if (_fonteAtual.agrupado) partes.add(_rotuloQualidade(_varianteAtual));
    return partes.join(' · ');
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
    _preferencias = context.read<PreferenciasProvider>();
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
        _atualizarTemFaixas();
        _timeoutTimer?.cancel();
        _atualizadorStatus?.cancel();
        // Reproduziu: zera o estado de recuperacao. Uma queda futura recomeca
        // o failover do zero (todas as fontes disponiveis de novo).
        _tentouAutoRetry = false;
        _fontesFalhas.clear();
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
        if (_iniciado &&
            _fonteAtual.agrupado &&
            widget.canal.tipo == TipoCanal.aoVivo &&
            _preferencias.autoQualidade) {
          // 8s contínuos de buffering → troca imediata
          _timerBufferingLongo ??= Timer(
            const Duration(seconds: 8),
            () => _tentarReduzirQualidade('buffering contínuo >8s'),
          );
          // 2s de buffering → incrementa contador (reset a cada minuto)
          _timerBufferingCurto ??= Timer(
            const Duration(seconds: 2),
            _incrementarContadorBuffering,
          );
        }
      } else {
        _timerBufferingLongo?.cancel();
        _timerBufferingLongo = null;
        _timerBufferingCurto?.cancel();
        _timerBufferingCurto = null;
        if (_iniciado) setState(() => _status = 'Tocando');
      }
    });

    _subError = _player.stream.error.listen(_tratarFalha);

    _subLog = _player.stream.log.listen((log) {
      if (log.level != 'warn' && log.level != 'error' && log.level != 'fatal') return;
      // Ignora ruido interno do libmpv que nao tem valor de diagnostico.
      if (log.text.contains('_setProperty(osc')) return;
      _registrarLog('mpv[${log.level}] ${log.text}');
    });

    _subTracks = _player.stream.tracks.listen((t) {
      if (!mounted) return;
      setState(() => _tracks = t);
      _atualizarTemFaixas();
      _autoSelecionarAudio(t);
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

    // Botao "proximo episodio": aparece a partir de ~90% do episodio. Roda
    // enquanto houver contexto de serie (a troca in-place pode mudar _proximoEp).
    if (widget.episodiosSerie != null) {
      _subPosition = _player.stream.position.listen((pos) {
        if (!mounted) return;
        final dur = _player.state.duration;
        _mostrarProximoEp.value = _proximoEp != null &&
            dur.inSeconds > 30 &&
            pos.inSeconds >= dur.inSeconds * 0.90;
      });
    }
  }

  /// As barras laterais (volume/brilho) e o botao "proximo episodio" seguem os
  /// controles do media_kit.
  ///
  /// ANTES isto era um toggle cego: cada toque na tela invertia um booleano
  /// nosso, torcendo para bater com o estado interno do media_kit. Bastava um
  /// evento que mexesse so num dos lados — arrastar a barra de progresso
  /// (reinicia o timer DELE), arrastar o volume (reiniciava o NOSSO), ou o
  /// simples fato de comecarmos visiveis enquanto ele comeca escondido — para
  /// os dois ficarem em contrafase: um toque escondia a barra e mostrava os
  /// controles laterais, o toque seguinte fazia o contrario.
  void _sincronizarBarras() {
    final alvo = _mkVisivel || _arrastandoBarras;
    if (_barraVodVisivel.value != alvo) _barraVodVisivel.value = alvo;
  }

  /// Chamado pela sentinela quando os controles do media_kit entram/saem.
  void _mkVisibilidade(bool visivel) {
    if (!mounted) return;
    _mkVisivel = visivel;
    _sincronizarBarras();
  }

  /// Mantem as barras visiveis enquanto o usuario ARRASTA volume/brilho — sem
  /// isso o auto-hide do media_kit sumiria com elas no meio do gesto.
  void _manterBarraVod() {
    _timerBarraVod?.cancel();
    _arrastandoBarras = true;
    _sincronizarBarras();
    _timerBarraVod = Timer(const Duration(milliseconds: 3500), () {
      _arrastandoBarras = false;
      _sincronizarBarras();
    });
  }

  /// Aplica o modo de tela atual ao sistema: tela cheia = imersivo + paisagem;
  /// janela = edge-to-edge + orientacoes liberadas. No desktop e no-op de fato.
  void _aplicarModoTela() {
    if (_telaCheia) {
      SystemChrome.setEnabledSystemUIMode(SystemUiMode.immersiveSticky,
          overlays: []);
      SystemChrome.setPreferredOrientations(const [
        DeviceOrientation.landscapeLeft,
        DeviceOrientation.landscapeRight,
      ]);
    } else {
      SystemChrome.setEnabledSystemUIMode(SystemUiMode.edgeToEdge);
      SystemChrome.setPreferredOrientations(DeviceOrientation.values);
    }
  }

  /// Alterna entre tela cheia e janela (botao de minimizar/maximizar).
  void _alternarTelaCheia() {
    setState(() => _telaCheia = !_telaCheia);
    _aplicarModoTela();
  }

  /// Alterna o ajuste do video entre "mostrar inteiro" (contain) e "preencher"
  /// (cover, cortando) — para quem nao quiser as faixas laterais.
  void _alternarAjuste() {
    setState(() {
      _ajuste = _ajuste == BoxFit.contain ? BoxFit.cover : BoxFit.contain;
    });
  }

  /// Atualiza a visibilidade do botao CC (faixas/legendas). Disponivel quando o
  /// video ja iniciou e ha faixas reportadas pelo player.
  void _atualizarTemFaixas() {
    _temFaixas.value = _iniciado && _player.state.tracks.audio.isNotEmpty;
  }

  /// Recalcula o proximo episodio com base no [_episodio] atual.
  void _recalcularProximoEp() {
    final eps = widget.episodiosSerie;
    _proximoEp = null;
    if (eps != null) {
      final i = eps.indexWhere((e) => e.url == _episodio.url);
      if (i >= 0 && i + 1 < eps.length) _proximoEp = eps[i + 1];
    }
  }

  /// Liga a gravacao periodica do progresso do VOD. Nao vale para ao vivo
  /// (nao ha onde retomar).
  void _iniciarTimerProgresso() {
    if (widget.canal.tipo != TipoCanal.filme) return;
    _timerProgresso?.cancel();
    _timerProgresso = Timer.periodic(_intervaloSalvarProgresso, (_) {
      if (!mounted || !_player.state.playing) return;
      _salvarProgressoEp(_episodio, notificar: false);
    });
  }

  /// App foi para segundo plano: grava AGORA. Depois de `paused` o sistema pode
  /// matar o processo sem avisar — e o dispose() nunca roda.
  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    super.didChangeAppLifecycleState(state);
    if (state == AppLifecycleState.paused ||
        state == AppLifecycleState.inactive ||
        state == AppLifecycleState.hidden) {
      _salvarProgressoEp(_episodio, notificar: false);
    }
  }

  /// Salva (ou limpa) o progresso de [ep] com base na posicao atual do player.
  ///
  /// [notificar] `false` nas gravacoes periodicas: escreve no Hive sem
  /// reconstruir quem escuta o provider — a cada 15s isso custaria rebuild da
  /// arvore inteira durante a reproducao.
  void _salvarProgressoEp(Canal ep, {bool notificar = true}) {
    if (!_iniciado || ep.tipo != TipoCanal.filme) return;
    final posicaoSeg = _player.state.position.inSeconds;
    if (posicaoSeg <= 120) return;
    final duracaoSeg = _player.state.duration.inSeconds;
    final fracao = duracaoSeg > 0 ? posicaoSeg / duracaoSeg : 0.0;
    if (fracao < 0.9) {
      _provider
          .salvarProgresso(ep, posicaoSeg, duracaoSeg > 0 ? duracaoSeg : null,
              notificar: notificar)
          .ignore();
    } else if (widget.episodiosSerie != null) {
      // EPISODIO no fim: marca como concluido em vez de apagar. A serie segue
      // em "Continuar assistindo" e a retomada pula para o proximo episodio.
      _provider
          .salvarProgresso(ep, posicaoSeg, duracaoSeg > 0 ? duracaoSeg : null,
              notificar: notificar, concluido: true)
          .ignore();
    } else {
      // FILME no fim: nao ha proximo — sai da fila.
      _provider.removerProgresso(ep, notificar: notificar).ignore();
    }
  }

  /// Avanca para o proximo episodio IN-PLACE: salva o progresso do atual, troca
  /// o episodio e reabre o stream — sem trocar de rota, entao a tela cheia
  /// (fullscreen) continua ativa.
  void _irProximoEp() {
    final prox = _proximoEp;
    if (prox == null) return;
    _salvarProgressoEp(_episodio); // progresso do episodio que esta saindo
    _provider.registrarVisualizacao(prox);
    final prog = _provider.obterProgresso(prox);
    // Episodio ja concluido volta do inicio, nao do fim.
    final progUtil = (prog != null && !prog.concluido) ? prog : null;
    _mostrarProximoEp.value = false;
    setState(() {
      _episodio = prox;
      _fonteAtual = prox.temFontes ? prox.fontes.first : prox;
      _varianteAtual = prox.agrupado ? prox.variantes.first : prox;
      _posicaoInicial =
          progUtil != null ? Duration(seconds: progUtil.posicaoSeg) : null;
      _recalcularProximoEp();
    });
    _abrirStream();
  }

  /// Seleciona automaticamente a faixa de audio no idioma do perfil (config de
  /// Idioma). As faixas vem rotuladas como ENG/POR/etc. no `language`/`title`.
  /// Roda UMA vez por stream e so quando ha mais de uma faixa — assim respeita
  /// uma troca manual feita depois pelo usuario.
  void _autoSelecionarAudio(Tracks t) {
    if (_audioAuto) return;
    final faixas =
        t.audio.where((a) => a.id != 'auto' && a.id != 'no').toList();
    if (faixas.isEmpty) return; // faixas ainda nao descobertas; espera proxima
    _audioAuto = true; // tenta apenas uma vez por stream
    if (faixas.length < 2) return; // so uma faixa: nada a escolher

    final tokens =
        context.read<PreferenciasProvider>().idiomaEfetivo.tokensAudio;
    AudioTrack? alvo;
    for (final a in faixas) {
      final lang = (a.language ?? '').toLowerCase().trim();
      final hay = '$lang ${(a.title ?? '').toLowerCase()}';
      final combina = tokens.any(
        (tk) =>
            (tk.length <= 3 && lang == tk) ||
            (tk.length >= 3 && hay.contains(tk)),
      );
      if (combina) {
        alvo = a;
        break;
      }
    }
    if (alvo != null && alvo.id != _track.audio.id) {
      _player.setAudioTrack(alvo);
    }
  }

  /// Executa o seek de retomada uma única vez, quando a mídia já está
  /// pronta (duração conhecida). Chamado tanto pelo evento de duração
  /// quanto pelo de playing.
  void _tentarSeekInicial() {
    if (_seekFeito) return;
    final alvo = _posicaoInicial;
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
    _cancelarTimersBuffering();
    _iniciado = false;
    _temFaixas.value = false;
    _seekFeito = false;
    _retryPendente = false;
    _streamAberto = false;
    _audioAuto = false; // novo stream: refaz a auto-selecao de audio
    if (!deAutoRetry) {
      // Abertura iniciada pelo usuario (ou inicial): zera o estado de
      // recuperacao para o failover poder tentar todas as fontes de novo.
      _tentouAutoRetry = false;
      _fontesFalhas.clear();
    }
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
      final url = _normalizarUrl(_varianteAtual.url);
      if (url != _varianteAtual.url) _registrarLog('url normalizada: $url');

      // Garante estado limpo antes de abrir nova mídia no player compartilhado.
      // O dispose() da sessão anterior chama _player.stop() sem await (Flutter
      // não permite async no dispose). Se esse stop ainda estiver em andamento
      // quando open() for chamado, a transição stop→open emite erros transitórios
      // que seriam mostrados ao usuário. Aguardar stop() aqui absorve o stop
      // pendente e evita esses erros por completo.
      if (_compartilhado) {
        await _player.stop();
        await Future.delayed(const Duration(milliseconds: 600));
        if (!mounted) return;
      }
      _streamAberto = true;

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
        // Ja esperou 20s — vai direto ao failover (sem novo retry da mesma).
        _tratarFalha(
          'Timeout: o player nao conseguiu iniciar em 20 segundos.',
          pularRetry: true,
        );
      });
    } catch (e) {
      _tratarFalha('Falha ao abrir stream: $e');
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
    await Clipboard.setData(ClipboardData(text: _varianteAtual.url));
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
        canal: widget.canal,
        fonteAtualNome: _fonteAtual.nome,
        varianteAtualUrl: _varianteAtual.url,
        onTrocarFonte: _trocarFonte,
        onTrocarQualidade: _trocarQualidade,
      ),
    );
  }

  Widget _buildControlesAoVivo(VideoState state) {
    final idLista = context.read<IptvProvider>().listaAtiva?.id;
    final temEpg = idLista != null &&
        widget.canal.tvgId != null &&
        widget.canal.tvgId!.isNotEmpty;
    return _ControlesAoVivo(
      state: state,
      iniciado: _iniciado,
      tracks: _tracks,
      temQualidades: widget.canal.agrupado || widget.canal.temFontes,
      onFaixas: () => _mostrarFaixas(state.context),
      player: _player,
      onEpg: temEpg
          ? () => mostrarModalProgramacao(
                state.context,
                canal: widget.canal,
                idLista: idLista,
              )
          : null,
    );
  }

  Widget _buildControls(VideoState state) {
    List<Widget> topBar() => [
      // Sentinela invisivel: vive DENTRO da arvore que o media_kit monta e
      // desmonta junto com os controles. E o unico jeito de saber quando eles
      // aparecem/somem — ver _sincronizarBarras.
      _SentinelaControles(aoMudar: _mkVisibilidade),
      // Voltar — só no player maximizado (que força paisagem). No modo janela
      // /retrato a AppBar já tem a seta, então não duplicamos.
      if (_telaCheia)
        IconButton(
          icon: const Icon(
            Icons.arrow_back_rounded,
            color: Colors.white,
            shadows: [Shadow(color: Colors.black54, blurRadius: 6)],
          ),
          tooltip: 'Voltar',
          onPressed: () => Navigator.of(state.context).maybePop(),
        ),
      const Spacer(),
      // Volume agora e a barra vertical lateral (_BarrasVolumeBrilho), nao mais
      // um botao aqui.
      // CC: slot SEMPRE presente (ValueListenableBuilder), so a visibilidade
      // interna reage a `_temFaixas`. Assim o botao surge quando as faixas
      // carregam mesmo que o media_kit nao re-invoque este builder (antes ele
      // so aparecia ao recriar o Video — minimizar+maximizar).
      ValueListenableBuilder<bool>(
        valueListenable: _temFaixas,
        builder: (_, mostra, _) => mostra
            ? IconButton(
                icon: const Icon(
                  Icons.closed_caption_rounded,
                  color: Colors.white,
                  shadows: [Shadow(color: Colors.black54, blurRadius: 6)],
                ),
                tooltip: 'Faixas e legendas',
                onPressed: () => _mostrarFaixas(state.context),
              )
            : const SizedBox.shrink(),
      ),
    ];
    // Barra inferior: posicao + zoom (contain/cover) + minimizar/maximizar.
    // Substitui o MaterialFullscreenButton do media_kit (que abriria uma rota
    // de fullscreen separada, com problemas de reatividade) pelo nosso proprio
    // botao de tela cheia, que apenas alterna o estado desta mesma tela.
    List<Widget> bottomBar() => [
      const MaterialPositionIndicator(),
      const Spacer(),
      IconButton(
        icon: Icon(
          _ajuste == BoxFit.cover
              ? Icons.fit_screen_rounded
              : Icons.aspect_ratio_rounded,
          color: Colors.white,
          shadows: const [Shadow(color: Colors.black54, blurRadius: 6)],
        ),
        tooltip: _ajuste == BoxFit.cover ? 'Mostrar inteiro' : 'Preencher tela',
        onPressed: _alternarAjuste,
      ),
      IconButton(
        icon: Icon(
          _telaCheia ? Icons.fullscreen_exit_rounded : Icons.fullscreen_rounded,
          color: Colors.white,
          shadows: const [Shadow(color: Colors.black54, blurRadius: 6)],
        ),
        tooltip: _telaCheia ? 'Minimizar' : 'Tela cheia',
        onPressed: _alternarTelaCheia,
      ),
    ];
    // Respiro lateral da barra de progresso. Com os 12px do padrao o "thumb"
    // no inicio/fim ficava a ~19px da borda: dificil de pegar com o polegar e
    // em conflito com o gesto de voltar do Android. Em tela cheia (paisagem)
    // ainda soma o recorte/notch, que no landscape cai nas laterais.
    final recorte = MediaQuery.paddingOf(context);
    final margemH = _telaCheia
        ? 32.0 + (recorte.left > recorte.right ? recorte.left : recorte.right)
        : 20.0;

    return MaterialVideoControlsTheme(
      normal: MaterialVideoControlsThemeData(
        topButtonBar: topBar(),
        bottomButtonBar: bottomBar(),
        controlsHoverDuration: const Duration(milliseconds: 3500),
        controlsTransitionDuration: _kFadeControles,
        seekBarHeight: 4.5,
        seekBarThumbSize: 14.0,
        seekBarContainerHeight: 52.0,
        seekBarMargin: EdgeInsets.only(bottom: 16, left: margemH, right: margemH),
        bottomButtonBarMargin:
            EdgeInsets.only(bottom: 16, left: margemH, right: margemH - 4),
      ),
      fullscreen: MaterialVideoControlsThemeData(
        topButtonBar: topBar(),
        bottomButtonBar: bottomBar(),
        controlsHoverDuration: const Duration(milliseconds: 3500),
        controlsTransitionDuration: _kFadeControles,
        seekBarHeight: 4.5,
        seekBarThumbSize: 14.0,
        seekBarContainerHeight: 52.0,
        seekBarMargin: EdgeInsets.only(bottom: 16, left: margemH, right: margemH),
        bottomButtonBarMargin:
            EdgeInsets.only(bottom: 16, left: margemH, right: margemH - 4),
      ),
      child: MaterialDesktopVideoControlsTheme(
        normal: MaterialDesktopVideoControlsThemeData(topButtonBar: topBar()),
        fullscreen: MaterialDesktopVideoControlsThemeData(topButtonBar: topBar()),
        // O botao "proximo episodio" fica DENTRO dos controles para aparecer
        // tambem no fullscreen nativo do media_kit (que reusa este builder).
        child: Stack(
            children: [
              AdaptiveVideoControls(state),
              _DoubleTapSeek(player: _player),
              // Barras de volume (direita) e brilho (esquerda) — somem junto com
              // os controles do media_kit (espelhados por _barraVodVisivel).
              ValueListenableBuilder<bool>(
                valueListenable: _barraVodVisivel,
                builder: (_, vis, _) => _BarrasVolumeBrilho(
                  visivel: vis,
                  player: _player,
                  aoInteragir: _manterBarraVod,
                ),
              ),
              if (widget.episodiosSerie != null)
                Positioned.fill(
                  child: AnimatedBuilder(
                    animation:
                        Listenable.merge([_mostrarProximoEp, _barraVodVisivel]),
                    builder: (context, _) => Align(
                      alignment: Alignment.bottomRight,
                      child: AnimatedPadding(
                        duration: const Duration(milliseconds: 220),
                        curve: Curves.easeOut,
                        padding: EdgeInsets.only(
                          right: 14,
                          bottom: _barraVodVisivel.value ? 62 : 14,
                        ),
                        child: AnimatedOpacity(
                          duration: const Duration(milliseconds: 280),
                          opacity: _mostrarProximoEp.value ? 1 : 0,
                          child: IgnorePointer(
                            ignoring: !_mostrarProximoEp.value,
                            child: _BotaoProximoEp(onTap: _irProximoEp),
                          ),
                        ),
                      ),
                    ),
                  ),
                ),
            ],
        ),
      ),
    );
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _timerProgresso?.cancel();
    _salvarProgressoEp(_episodio);
    _timeoutTimer?.cancel();
    _atualizadorStatus?.cancel();
    _cancelarTimersBuffering();
    _timerNotificacao?.cancel();
    _subPlaying?.cancel();
    _subBuffering?.cancel();
    _subError?.cancel();
    _subLog?.cancel();
    _subTracks?.cancel();
    _subTrack?.cancel();
    _subDuration?.cancel();
    _subPosition?.cancel();
    _timerBarraVod?.cancel();
    _mostrarProximoEp.dispose();
    _barraVodVisivel.dispose();
    _temFaixas.dispose();
    if (_bloqueadoPorPin) {
      // Saiu sem digitar o PIN: nenhum player foi criado (`_player` e `late` e
      // nunca foi atribuido) — nao ha nada para parar/liberar.
    } else if (widget.mantemPlayerAoSair) {
      // O player nao pertence a esta tela — o widget que a abriu (ex.: player
      // embutido do desktop) continua usando o stream apos o pop.
    } else if (_transferidoParaMini) {
      // Player foi para o mini player — segue vivo lá, não mexe.
    } else if (_compartilhado) {
      // Player VOD compartilhado: só para, mantém vivo para o próximo filme.
      _player.stop();
    } else {
      _player.dispose();
    }
    // Ao sair do player, devolve o brilho REAL da tela ao valor do sistema (no
    // mobile a barra de luminosidade altera o brilho do app). Vale p/ ao vivo E
    // VOD. Fica aqui (dispose da TELA) e nao nos controles — o fullscreen nativo
    // recria os controles numa rota separada e nao deve resetar enquanto assiste.
    if (Platform.isAndroid || Platform.isIOS) {
      ScreenBrightness().resetApplicationScreenBrightness().catchError(
            (Object _) {},
          );
    }
    // Ao sair do player, restaura o modo do app: orientacoes liberadas e
    // edge-to-edge (o fullscreen nativo do media_kit deixa o sistema em modo
    // 'manual' com as barras visiveis ao minimizar — sem isto a barra do
    // sistema ficaria aparecendo depois de assistir um filme).
    SystemChrome.setPreferredOrientations(DeviceOrientation.values);
    SystemChrome.setEnabledSystemUIMode(SystemUiMode.edgeToEdge);
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    // Travado pelo controle dos pais: tela preta ate o PIN ser aceito (o
    // dialogo esta por cima). Nada do conteudo — nem titulo — aparece.
    if (_bloqueadoPorPin) {
      return const Scaffold(backgroundColor: Colors.black, body: SizedBox());
    }

    final provider = context.watch<IptvProvider>();
    final favorito = provider.ehFavorito(widget.canal);
    final aoVivo = widget.canal.tipo == TipoCanal.aoVivo;
    final idLista = provider.listaAtiva?.id;
    final temEpgPossivel = aoVivo &&
        idLista != null &&
        widget.canal.tvgId != null &&
        widget.canal.tvgId!.isNotEmpty;

    // VOD em tela cheia esconde a AppBar (so o video). Modo janela e canais ao
    // vivo mantem a AppBar.
    final semAppBar = !aoVivo && _telaCheia;

    return PopScope(
      // Back: canais ao vivo minimizam para o mini player; VOD em tela cheia
      // volta primeiro para o modo janela (estilo YouTube); VOD em janela fecha.
      canPop: widget.mantemPlayerAoSair || (!aoVivo && !_telaCheia),
      onPopInvokedWithResult: (didPop, _) {
        if (didPop) return;
        if (aoVivo && !widget.mantemPlayerAoSair) {
          _minimizar();
        } else if (!aoVivo && _telaCheia) {
          _alternarTelaCheia(); // minimiza em vez de fechar
        }
      },
      child: Scaffold(
        backgroundColor: AppColors.surface0,
        appBar: semAppBar
            ? null
            : AppBar(
          title: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(_episodio.nome, overflow: TextOverflow.ellipsis),
              Text(
                _subtituloPlayer,
                style: const TextStyle(fontSize: 11, color: Colors.white70),
              ),
            ],
          ),
          backgroundColor: AppColors.surface0,
          foregroundColor: Colors.white,
          actions: [
            if (temEpgPossivel)
              IconButton(
                icon: const Icon(Icons.event_note_rounded, color: Colors.white),
                tooltip: 'Programacao',
                onPressed: () => mostrarModalProgramacao(
                  context,
                  canal: widget.canal,
                  idLista: idLista,
                ),
              ),
            IconButton(
              icon: const Icon(Icons.copy, color: Colors.white),
              tooltip: 'Copiar URL',
              onPressed: _copiarUrl,
            ),
            if (aoVivo) ...[ 
              IconButton(
                icon: const Icon(
                  Icons.playlist_add_rounded,
                  color: Colors.white,
                ),
                tooltip: 'Adicionar a categoria',
                onPressed: () => mostrarSeletorCategoria(context, widget.canal),
              ),
              IconButton(
                icon: Icon(
                  favorito ? Icons.star_rounded : Icons.star_outline_rounded,
                  color: favorito ? AppColors.accent : Colors.white,
                ),
                onPressed: () => provider.alternarFavorito(widget.canal),
              ),
            ],
          ],
        ),
        body: _erro != null
            ? _ViewErro(
                canal: _varianteAtual,
                erro: _erro!,
                estrategiaAtual: _estrategia,
                log: _log,
                onTentarMesmo: _abrirStream,
                onTentarOutraEstrategia: _tentarProximaEstrategia,
                onResetar: _resetarParaPadrao,
                onCopiarUrl: _copiarUrl,
              )
            : _buildCorpo(context, aoVivo: aoVivo, idLista: idLista),
      ),
    );
  }

  /// Decide entre layout split (player + EPG embaixo) e layout fullscreen.
  ///
  /// Split: somente para canais ao vivo, em phone/tablet em portrait. Desktop
  /// e landscape mantem o layout fullscreen tradicional.
  Widget _buildCorpo(
    BuildContext context, {
    required bool aoVivo,
    required String? idLista,
  }) {
    final orientacao = MediaQuery.orientationOf(context);
    final formFator = formFactor(context);
    final podeSplit = aoVivo &&
        idLista != null &&
        orientacao == Orientation.portrait &&
        (formFator == FormFactor.phone || formFator == FormFactor.tablet) &&
        widget.canal.tvgId != null &&
        widget.canal.tvgId!.isNotEmpty;

    if (!podeSplit) {
      // VOD em tela cheia: video preenche a tela inteira (sem box 16:9 nem
      // SafeArea). Caso contrario, mantem o comportamento original.
      final cheia = _telaCheia && !aoVivo;
      final area = _buildAreaPlayer(aoVivo: aoVivo, comAspectRatio: !cheia);
      return cheia ? area : SafeArea(top: false, child: area);
    }

    // Layout estilo YouTube: video 16:9 no topo, EPG rolavel embaixo.
    return SafeArea(
      top: false,
      child: Column(
        children: [
          AspectRatio(
            aspectRatio: 16 / 9,
            child: _buildAreaPlayer(aoVivo: aoVivo, comAspectRatio: false),
          ),
          Expanded(
            child: SingleChildScrollView(
              child: PainelEpg(canal: widget.canal, idLista: idLista),
            ),
          ),
        ],
      ),
    );
  }

  /// Constroi a area do video + overlays (conectando, banner auto-qualidade).
  ///
  /// Quando [comAspectRatio] e true, envolve o video num AspectRatio centrado
  /// — comportamento original para layout fullscreen. Quando false, deixa
  /// o pai (Column do split) controlar o tamanho.
  Widget _buildAreaPlayer({
    required bool aoVivo,
    bool comAspectRatio = true,
  }) {
    final conectando = _erro == null && !_iniciado;
    // O botao "proximo episodio" e o CC vivem DENTRO dos controles
    // (_buildControls). `fit: _ajuste` permite alternar contain/cover (zoom).
    // O CC reage por conta propria via ValueListenableBuilder(_temFaixas) — nao
    // depende do media_kit re-invocar o builder de controles.
    final Widget video = Video(
      controller: _controller,
      fit: _ajuste,
      controls: aoVivo ? _buildControlesAoVivo : _buildControls,
    );

    return Stack(
      alignment: Alignment.center,
      children: [
        if (comAspectRatio)
          Center(
            child: AspectRatio(aspectRatio: 16 / 9, child: video),
          )
        else
          Positioned.fill(child: video),
        if (conectando)
          _OverlayConectando(
            status: _status,
            estrategia: _estrategia,
            onCancelar: _cancelarTentativa,
            onProximaEstrategia: _tentarProximaEstrategia,
          ),
        if (_msgAutoQualidade != null)
          Positioned(
            top: 12,
            right: 12,
            child: _BannerAutoQualidade(msg: _msgAutoQualidade!),
          ),
      ],
    );
  }
}


// ─── Botao "Proximo episodio" (series) ────────────────────────────────────────

class _BotaoProximoEp extends StatelessWidget {
  final VoidCallback onTap;
  const _BotaoProximoEp({required this.onTap});

  @override
  Widget build(BuildContext context) {
    return Material(
      color: Colors.black.withValues(alpha: 0.62),
      borderRadius: BorderRadius.circular(AppRadius.pill),
      clipBehavior: Clip.antiAlias,
      child: InkWell(
        onTap: onTap,
        child: Padding(
          padding: const EdgeInsets.symmetric(
            horizontal: AppSpacing.base,
            vertical: AppSpacing.sm,
          ),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              const Text(
                'Próximo episódio',
                style: TextStyle(
                  color: Colors.white,
                  fontSize: 13,
                  fontWeight: FontWeight.w600,
                ),
              ),
              const SizedBox(width: AppSpacing.xs),
              const Icon(Icons.skip_next_rounded, color: Colors.white, size: 20),
            ],
          ),
        ),
      ),
    );
  }
}

class _DoubleTapSeek extends StatefulWidget {
  final Player player;
  const _DoubleTapSeek({required this.player});

  @override
  State<_DoubleTapSeek> createState() => _DoubleTapSeekState();
}

class _DoubleTapSeekState extends State<_DoubleTapSeek> {
  String? _label;
  Timer? _timer;
  int _accumSecs = 0;
  bool _direita = true;
  Duration? _seekBase;

  @override
  void dispose() {
    _timer?.cancel();
    super.dispose();
  }

  void _onDoubleTapDown(TapDownDetails d) {
    final width = MediaQuery.of(context).size.width;
    final isRight = d.globalPosition.dx > width / 2;

    if (_timer == null || isRight != _direita) {
      _accumSecs = 0;
      _seekBase = widget.player.state.position;
      _direita = isRight;
    }

    _accumSecs += isRight ? 10 : -10;

    final dur = widget.player.state.duration;
    final nova = Duration(
      milliseconds: (_seekBase! + Duration(seconds: _accumSecs))
          .inMilliseconds
          .clamp(0, dur.inMilliseconds),
    );
    widget.player.seek(nova);

    _timer?.cancel();
    setState(() => _label = _accumSecs > 0 ? '+${_accumSecs}s' : '${_accumSecs}s');
    _timer = Timer(const Duration(milliseconds: 1000), () {
      // Zera _timer tambem: senao o proximo toque na mesma direcao entra no
      // ramo "acumular" com _seekBase ja nulo e estoura o null-check.
      _timer = null;
      if (mounted) setState(() { _label = null; _accumSecs = 0; _seekBase = null; });
    });
  }

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      behavior: HitTestBehavior.translucent,
      onDoubleTapDown: _onDoubleTapDown,
      child: SizedBox.expand(
        child: _label == null
            ? const SizedBox.shrink()
            : Center(
                child: IgnorePointer(
                  child: Container(
                    padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 14),
                    decoration: BoxDecoration(
                      color: Colors.black.withValues(alpha: 0.72),
                      borderRadius: BorderRadius.circular(14),
                    ),
                    child: Text(
                      _label!,
                      style: const TextStyle(
                        color: Colors.white,
                        fontSize: 24,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                  ),
                ),
              ),
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

// ─── Controles canal ao vivo (toque → fullscreen/CC, sem barra de progresso) ─

class _ControlesAoVivo extends StatefulWidget {
  final VideoState state;
  final bool iniciado;
  final Tracks tracks;
  final bool temQualidades;
  final VoidCallback onFaixas;
  final Player player;
  /// Quando nao-null, mostra botao de programacao no overlay de controles.
  final VoidCallback? onEpg;

  const _ControlesAoVivo({
    required this.state,
    required this.iniciado,
    required this.tracks,
    required this.temQualidades,
    required this.onFaixas,
    required this.player,
    this.onEpg,
  });

  @override
  State<_ControlesAoVivo> createState() => _ControlesAoVivoState();
}

class _ControlesAoVivoState extends State<_ControlesAoVivo> {
  bool _visivel = false;
  Timer? _timer;

  @override
  void dispose() {
    _timer?.cancel();
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
    return Stack(
      children: [
        // ── Controles (auto-hide ao toque): scrim + badge + barra inferior ──
        GestureDetector(
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
                  const Positioned(top: 12, left: 12, child: _BadgeAoVivo()),
                  // ── Barra inferior: EPG / CC / Fullscreen (direita) ───────
                  Positioned(
                    bottom: 4,
                    left: 4,
                    right: 4,
                    child: SafeArea(
                      child: Row(
                        children: [
                          const Spacer(),
                          if (widget.onEpg != null)
                            IconButton(
                              icon: const Icon(
                                Icons.event_note_rounded,
                                color: Colors.white,
                              ),
                              tooltip: 'Programacao',
                              onPressed: widget.onEpg,
                            ),
                          if (widget.iniciado &&
                              (widget.tracks.audio.isNotEmpty ||
                                  widget.temQualidades))
                            IconButton(
                              icon: const Icon(
                                Icons.closed_caption_rounded,
                                color: Colors.white,
                              ),
                              tooltip: 'Qualidade, faixas e legendas',
                              onPressed: widget.onFaixas,
                            ),
                          IconButton(
                            icon: Icon(
                              emTela
                                  ? Icons.fullscreen_exit_rounded
                                  : Icons.fullscreen_rounded,
                              color: Colors.white,
                            ),
                            tooltip:
                                emTela ? 'Sair da tela cheia' : 'Tela cheia',
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
        ),
        // ── Barras de volume (direita) e brilho (esquerda) ──────────────────
        // Ficam sobre os controles e somem junto com eles; o dimmer (desktop)
        // persiste por dentro do proprio widget.
        _BarrasVolumeBrilho(
          visivel: _visivel,
          player: widget.player,
          aoInteragir: _resetTimer,
        ),
      ],
    );
  }
}

// ─── Barras de volume + brilho (reutilizavel: ao vivo E VOD) ─────────────────
//
// Volume = volume do DISPOSITIVO (volume_controller). Brilho = brilho REAL do
// app no mobile (screen_brightness) ou um dimmer (camada escura) no desktop.
// `visivel` controla o fade junto com os controles; o dimmer persiste sempre.
class _BarrasVolumeBrilho extends StatefulWidget {
  final bool visivel;
  final VoidCallback? aoInteragir;
  final Player player;

  const _BarrasVolumeBrilho({
    required this.visivel,
    required this.player,
    this.aoInteragir,
  });

  @override
  State<_BarrasVolumeBrilho> createState() => _BarrasVolumeBrilhoState();
}

class _BarrasVolumeBrilhoState extends State<_BarrasVolumeBrilho> {
  double _volume = 0.5;
  double _brilho = 1.0;
  StreamSubscription<double>? _subVolume;
  StreamSubscription<double>? _subBrilho;

  // Brilho real so faz sentido no mobile; no desktop usamos o dimmer.
  bool get _brilhoReal => Platform.isAndroid || Platform.isIOS;

  // Mobile: a barra controla o VOLUME DO SISTEMA (volume_controller).
  // Desktop: controla so o VOLUME DO APP (player) — nao mexe no SO inteiro.
  bool get _volumeDoSistema => Platform.isAndroid || Platform.isIOS;

  @override
  void initState() {
    super.initState();
    if (_volumeDoSistema) {
      // Volume do sistema (sem a UI nativa do SO — temos a nossa barra).
      VolumeController.instance.showSystemUI = false;
      VolumeController.instance.getVolume().then((v) {
        if (mounted) setState(() => _volume = v);
      }).catchError((Object _) {});
      _subVolume = VolumeController.instance.addListener(
        (v) {
          if (mounted) setState(() => _volume = v);
        },
        fetchInitialVolume: false,
      );
    } else {
      // Desktop: reflete/controla o volume do proprio player (0–100 → 0–1).
      _volume = (widget.player.state.volume / 100).clamp(0.0, 1.0);
      _subVolume = widget.player.stream.volume.listen((v) {
        if (mounted) setState(() => _volume = (v / 100).clamp(0.0, 1.0));
      });
    }
    // Brilho real (so no mobile le/observa).
    if (_brilhoReal) {
      ScreenBrightness().application.then((v) {
        if (mounted) setState(() => _brilho = v);
      }).catchError((Object _) {});
      _subBrilho =
          ScreenBrightness().onApplicationScreenBrightnessChanged.listen((v) {
        if (mounted) setState(() => _brilho = v);
      });
    }
  }

  @override
  void dispose() {
    _subVolume?.cancel();
    _subBrilho?.cancel();
    super.dispose();
  }

  void _definirVolume(double v) {
    setState(() => _volume = v);
    if (_volumeDoSistema) {
      VolumeController.instance.setVolume(v);
    } else {
      // Desktop: ajusta so o volume do app (0–1 → 0–100).
      widget.player.setVolume(v * 100);
    }
  }

  void _definirBrilho(double v) {
    setState(() => _brilho = v);
    if (_brilhoReal) {
      ScreenBrightness()
          .setApplicationScreenBrightness(v)
          .catchError((Object _) {});
    }
  }

  Widget _barra({
    required IconData icone,
    required double valor,
    required double altura,
    required ValueChanged<double> onChanged,
  }) {
    return AnimatedOpacity(
      opacity: widget.visivel ? 1.0 : 0.0,
      duration: const Duration(milliseconds: 200),
      child: IgnorePointer(
        ignoring: !widget.visivel,
        child: _BarraVertical(
          icone: icone,
          valor: valor,
          altura: altura,
          onChanged: (v) {
            onChanged(v);
            widget.aoInteragir?.call();
          },
          onChangeStart: (_) => widget.aoInteragir?.call(),
          onChangeEnd: (_) => widget.aoInteragir?.call(),
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, constraints) {
        // Barras com altura proporcional a area do video (cobre split + cheio).
        final altura = (constraints.maxHeight * 0.55).clamp(110.0, 240.0);
        return Stack(
          children: [
            // Dimmer (desktop): escurece o video conforme o brilho. Persiste
            // mesmo com os controles escondidos. So opacidade — 60 fps.
            if (!_brilhoReal)
              Positioned.fill(
                child: IgnorePointer(
                  child: ColoredBox(
                    color: Colors.black
                        .withValues(alpha: (1 - _brilho).clamp(0.0, 1.0) * 0.85),
                  ),
                ),
              ),
            // Luminosidade (esquerda).
            Positioned(
              left: 10,
              top: 0,
              bottom: 0,
              child: Center(
                child: _barra(
                  icone: Icons.brightness_6_rounded,
                  valor: _brilho,
                  altura: altura,
                  onChanged: _definirBrilho,
                ),
              ),
            ),
            // Volume do dispositivo (direita).
            Positioned(
              right: 10,
              top: 0,
              bottom: 0,
              child: Center(
                child: _barra(
                  icone: _volume == 0
                      ? Icons.volume_off_rounded
                      : Icons.volume_up_rounded,
                  valor: _volume,
                  altura: altura,
                  onChanged: _definirVolume,
                ),
              ),
            ),
          ],
        );
      },
    );
  }
}

// ─── Barra vertical reutilizavel (volume / luminosidade) ─────────────────────

class _BarraVertical extends StatelessWidget {
  final IconData icone;
  final double valor; // 0.0–1.0
  final double altura;
  final ValueChanged<double> onChanged;
  final ValueChanged<double>? onChangeStart;
  final ValueChanged<double>? onChangeEnd;

  const _BarraVertical({
    required this.icone,
    required this.valor,
    required this.altura,
    required this.onChanged,
    this.onChangeStart,
    this.onChangeEnd,
  });

  @override
  Widget build(BuildContext context) {
    // Sem fundo/"pilula": so a barra e o icone (com sombra p/ legibilidade
    // sobre video claro).
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        SizedBox(
          height: altura,
          // quarterTurns: 3 deixa o minimo embaixo e o maximo em cima.
          child: RotatedBox(
            quarterTurns: 3,
            child: SliderTheme(
              data: SliderTheme.of(context).copyWith(
                activeTrackColor: Colors.white,
                inactiveTrackColor: Colors.white30,
                thumbColor: Colors.white,
                overlayColor: Colors.white24,
                trackHeight: 3.0,
                thumbShape: const RoundSliderThumbShape(enabledThumbRadius: 7),
              ),
              child: Slider(
                value: valor.clamp(0.0, 1.0),
                onChanged: onChanged,
                onChangeStart: onChangeStart,
                onChangeEnd: onChangeEnd,
              ),
            ),
          ),
        ),
        const SizedBox(height: 6),
        Icon(
          icone,
          color: Colors.white,
          size: 20,
          shadows: const [Shadow(color: Colors.black54, blurRadius: 6)],
        ),
      ],
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
  final Canal canal;
  final String fonteAtualNome;
  final String varianteAtualUrl;
  final ValueChanged<Canal> onTrocarFonte;
  final ValueChanged<Canal> onTrocarQualidade;

  const _PainelFaixas({
    required this.player,
    required this.tracks,
    required this.track,
    required this.canal,
    required this.fonteAtualNome,
    required this.varianteAtualUrl,
    required this.onTrocarFonte,
    required this.onTrocarQualidade,
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
              widget.canal.agrupado || widget.canal.temFontes
                  ? 'Qualidade, Fontes e Faixas'
                  : 'Faixas e Legendas',
              style: Theme.of(context).textTheme.titleMedium,
            ),
            const SizedBox(height: AppSpacing.lg),

            // ── Fontes alternativas ───────────────────────────────────────
            if (widget.canal.temFontes) ...[
              _SecaoLabel('FONTES'),
              const SizedBox(height: AppSpacing.xs),
              ...widget.canal.fontes.map((f) {
                final qualidade = f.agrupado
                    ? detectarQualidade(f.variantes.first.nome).rotulo
                    : detectarQualidade(f.nome).rotulo;
                final temQualidade = qualidade != 'Padrao';
                return _ItemFaixa(
                  rotulo: temQualidade ? '${f.nome}  ·  $qualidade' : f.nome,
                  selecionado: f.nome == widget.fonteAtualNome,
                  onTap: () {
                    Navigator.pop(context);
                    widget.onTrocarFonte(f);
                  },
                );
              }),
              const SizedBox(height: AppSpacing.base),
            ],

            // ── Qualidade (fonte atual, se agrupada) ──────────────────────
            if (widget.canal.temFontes
                ? widget.canal.fontes
                    .firstWhere((f) => f.nome == widget.fonteAtualNome,
                        orElse: () => widget.canal.fontes.first)
                    .agrupado
                : widget.canal.agrupado) ...[
              _SecaoLabel('QUALIDADE'),
              const SizedBox(height: AppSpacing.xs),
              ...() {
                final fonte = widget.canal.temFontes
                    ? widget.canal.fontes.firstWhere(
                        (f) => f.nome == widget.fonteAtualNome,
                        orElse: () => widget.canal.fontes.first)
                    : widget.canal;
                return fonte.variantes.map((v) {
                  final q = detectarQualidade(v.nome);
                  return _ItemFaixa(
                    rotulo: q == Qualidade.desconhecida ? v.nome : q.rotulo,
                    selecionado: v.url == widget.varianteAtualUrl,
                    onTap: () {
                      Navigator.pop(context);
                      widget.onTrocarQualidade(v);
                    },
                  );
                });
              }(),
              const SizedBox(height: AppSpacing.base),
            ],

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

            if (!temAudio && !temLegenda && !widget.canal.agrupado && !widget.canal.temFontes)
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

class _BannerAutoQualidade extends StatelessWidget {
  final String msg;
  const _BannerAutoQualidade({required this.msg});

  @override
  Widget build(BuildContext context) {
    return Container(
      constraints: const BoxConstraints(maxWidth: 260),
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
      decoration: BoxDecoration(
        color: Colors.black.withValues(alpha: 0.80),
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: Colors.orange.shade400),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(Icons.signal_cellular_alt_rounded,
              color: Colors.orange.shade400, size: 16),
          const SizedBox(width: 8),
          Flexible(
            child: Text(
              msg,
              style: const TextStyle(color: Colors.white, fontSize: 12),
            ),
          ),
        ],
      ),
    );
  }
}

/// Duracao do fade dos controles do media_kit. Curta de proposito: a sentinela
/// so avisa que os controles sumiram quando a animacao TERMINA (e o momento em
/// que o media_kit desmonta a arvore), entao um fade longo faria as barras
/// laterais saírem visivelmente atrasadas.
const Duration _kFadeControles = Duration(milliseconds: 180);

/// Widget de tamanho zero cujo unico trabalho e avisar quando os controles do
/// media_kit sao montados e desmontados. O estado de visibilidade deles e
/// privado do pacote (`_MaterialVideoControlsState.visible`), mas a arvore
/// inteira sai do ar quando eles somem — entao montar/desmontar E a
/// visibilidade.
class _SentinelaControles extends StatefulWidget {
  final ValueChanged<bool> aoMudar;
  const _SentinelaControles({required this.aoMudar});

  @override
  State<_SentinelaControles> createState() => _SentinelaControlesState();
}

class _SentinelaControlesState extends State<_SentinelaControles> {
  @override
  void initState() {
    super.initState();
    // Fora do frame: mexer num ValueNotifier durante o build da arvore que o
    // escuta dispara "setState during build".
    final aoMudar = widget.aoMudar;
    WidgetsBinding.instance.addPostFrameCallback((_) => aoMudar(true));
  }

  @override
  void dispose() {
    final aoMudar = widget.aoMudar;
    WidgetsBinding.instance.addPostFrameCallback((_) => aoMudar(false));
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => const SizedBox.shrink();
}
