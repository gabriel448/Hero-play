import 'dart:async';
import 'dart:math';

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../models/canal.dart';
import '../models/lista_m3u.dart';
import '../models/perfil.dart';
import '../models/serie.dart';
import '../services/agrupador_canais.dart';
import '../state/iptv_provider.dart';
import '../state/perfil_provider.dart';
import '../theme/app_theme.dart';
import '../utils/layout.dart';
import '../widgets/abertura_secao.dart';
import '../widgets/avatar_perfil.dart';
import 'tela_canais.dart';
import 'tela_configuracoes.dart';
import 'tela_filmes.dart';
import 'tela_importar.dart';

/// Home unificada: tela de selecao entre Canais ao vivo, Filmes, Series, mais
/// um bloco secundario com Gerenciar listas e Configuracoes. Funciona em
/// phone, tablet e desktop — apenas a disposicao varia.
///
/// Quando nao existe lista ativa, mostra o empty state com CTA de importar.
class TelaInicial extends StatefulWidget {
  const TelaInicial({super.key});

  @override
  State<TelaInicial> createState() => _TelaInicialState();
}

class _TelaInicialState extends State<TelaInicial>
    with TickerProviderStateMixin {
  // Dados agrupados — calculados em ISOLATE (compute) para nao travar a UI.
  // Enquanto null, o conteudo ainda esta carregando (estagio 2 da animacao).
  Map<String, List<Canal>>? _aoVivo;
  Map<String, List<Canal>>? _filmes;
  int _totalMovies = 0;
  int _totalSeries = 0;
  String? _idCarregada;
  final Completer<void> _carregado = Completer<void>();

  // Coreografia de entrada em 3 ESTAGIOS independentes (assincronos):
  //  1) _centro : avatar do ponto tocado -> centro (maior) + fundo escurece
  //  2) _pulso  : pulsa no centro ENQUANTO carrega (dura o tempo do compute)
  //  3) _canto  : avatar -> canto superior direito; o preto some; cards surgem
  late final AnimationController _centro;
  late final AnimationController _pulso;
  late final AnimationController _canto;
  TickerFuture? _centroFut;
  Rect? _origem;
  bool _animar = false;
  // Titulo da secao em abertura — o card correspondente esconde seu conteudo
  // (icone+nome) para parecer que eles "sairam" do botao rumo ao centro.
  String? _secaoAtiva;
  // Frase de saudacao escolhida nesta entrada no perfil (alterna a cada vez).
  late final int _saudacao = _sortearSaudacao();

  @override
  void initState() {
    super.initState();
    final perfis = context.read<PerfilProvider>();
    _origem = perfis.origemEntrada;
    _animar = _origem != null;
    perfis.consumirEntrada();
    context.read<IptvProvider>().recarregarDadosDoPerfil();

    _centro = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 440),
    );
    _pulso = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 680),
    );
    _canto = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 900),
    );

    if (_animar) {
      // Pequeno atraso para o crossfade do gate terminar antes do estagio 1.
      Future<void>.delayed(const Duration(milliseconds: 220), () {
        if (!mounted) return;
        _centro.addStatusListener((s) {
          if (s == AnimationStatus.completed &&
              mounted &&
              !_pulso.isAnimating) {
            _pulso.repeat(
              reverse: true,
            ); // estagio 2 comeca ao chegar no centro
          }
        });
        _centroFut = _centro.forward(); // estagio 1
      });
      _orquestrar();
    } else {
      _centro.value = 1;
      _canto.value = 1;
    }
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    final lista = context.read<IptvProvider>().listaAtiva;
    if (lista != null && lista.id != _idCarregada) {
      _idCarregada = lista.id;
      _carregar(lista);
    }
  }

  @override
  void dispose() {
    _centro.dispose();
    _pulso.dispose();
    _canto.dispose();
    super.dispose();
  }

  /// Agrupa os canais em um isolate (nao trava a UI) e guarda o resultado.
  Future<void> _carregar(ListaM3U lista) async {
    final dados = await compute(_agruparHome, lista);
    if (!mounted) return;
    setState(() {
      _aoVivo = dados.aoVivo;
      _filmes = dados.filmes;
      _totalMovies = dados.totalMovies;
      _totalSeries = dados.totalSeries;
    });
    if (!_carregado.isCompleted) _carregado.complete();
  }

  /// Sequencia os 3 estagios de forma assincrona.
  Future<void> _orquestrar() async {
    // Espera o controller do estagio 1 ser criado (apos o atraso) e terminar.
    while (_centroFut == null) {
      await Future<void>.delayed(const Duration(milliseconds: 16));
      if (!mounted) return;
    }
    await _centroFut; // estagio 1 concluido (avatar no centro)
    // estagio 2: pulsa enquanto o carregamento acontece (com minimo perceptivel).
    final inicioPulso = DateTime.now();
    await _carregado.future;
    if (!mounted) return;
    final decorrido = DateTime.now().difference(inicioPulso);
    const minPulso = Duration(milliseconds: 480);
    if (decorrido < minPulso) {
      await Future<void>.delayed(minPulso - decorrido);
    }
    if (!mounted) return;
    // estagio 3: avatar vai ao canto e os cards surgem.
    _pulso.stop();
    await _canto.forward();
  }

  double _seg(double v, double a, double b) =>
      ((v - a) / (b - a)).clamp(0.0, 1.0);

  /// Revela [child] (fade + leve subida) durante o estagio 3 (controller _canto).
  Widget _revelar(double inicio, double fim, Widget child) {
    final anim = CurvedAnimation(
      parent: _canto,
      curve: Interval(inicio, fim, curve: Curves.easeOutCubic),
    );
    return AnimatedBuilder(
      animation: anim,
      builder: (_, c) => Opacity(
        opacity: anim.value.clamp(0.0, 1.0),
        child: Transform.translate(
          offset: Offset(0, (1 - anim.value) * 14),
          child: c,
        ),
      ),
      child: child,
    );
  }

  /// Animacao (0→1) de um card do grid, escalonada dentro do estagio 3
  /// (controller _canto). Usada para revelar o card E crescer sua sombra.
  Animation<double> _itemAnim(double inicio, double fim) => CurvedAnimation(
    parent: _canto,
    curve: Interval(inicio, fim, curve: Curves.easeOutCubic),
  );

  /// Overlay (coordenadas globais): scrim preto + avatar voando entre os 3
  /// estagios. Quando nao ha animacao, fica so o botao no canto.
  Widget _overlayEntrada(BuildContext context) {
    final mq = MediaQuery.of(context);
    final w = mq.size.width;
    final h = mq.size.height;
    const grande = 200.0; // ~2x
    const cantoTam = 50.0;
    final centro = Rect.fromCenter(
      center: Offset(w / 2, h / 2),
      width: grande,
      height: grande,
    );
    final cantoRect = Rect.fromLTWH(
      w - mq.padding.right - AppSpacing.base - cantoTam,
      mq.padding.top + AppSpacing.sm,
      cantoTam,
      cantoTam,
    );

    return AnimatedBuilder(
      animation: Listenable.merge([_centro, _pulso, _canto]),
      builder: (context, _) {
        Rect rect;
        double scrim;
        if (!_animar) {
          rect = cantoRect;
          scrim = 0;
        } else if (_canto.value == 0) {
          // estagios 1 e 2: origem -> centro (escurece junto) e pulso no centro.
          final toCentro = Curves.easeOutCubic.transform(_centro.value);
          var r = Rect.lerp(_origem!, centro, toCentro)!;
          if (_centro.isCompleted) {
            final p = 1 + 0.06 * _pulso.value;
            r = Rect.fromCenter(
              center: r.center,
              width: r.width * p,
              height: r.height * p,
            );
          }
          rect = r;
          scrim = toCentro; // fundo vai a 100% preto ao chegar no centro
        } else {
          // estagio 3: centro -> canto; o preto some.
          final t = Curves.easeInOutCubic.transform(
            _seg(_canto.value, 0.0, 0.55),
          );
          rect = Rect.lerp(centro, cantoRect, t)!;
          scrim = 1 - Curves.easeInOut.transform(_seg(_canto.value, 0.0, 0.55));
        }
        return Stack(
          children: [
            Positioned.fill(
              child: IgnorePointer(
                child: ColoredBox(color: Colors.black.withValues(alpha: scrim)),
              ),
            ),
            Positioned(
              left: rect.left,
              top: rect.top,
              width: rect.width,
              height: rect.height,
              child: _BotaoPerfil(tamanho: rect.width),
            ),
          ],
        );
      },
    );
  }

  @override
  Widget build(BuildContext context) {
    final lista = context.watch<IptvProvider>().listaAtiva;
    if (lista == null) return const _HomeSemLista();

    // Recalcula se a lista ativa mudou (fora a carga inicial).
    if (lista.id != _idCarregada) {
      _idCarregada = lista.id;
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted) _carregar(lista);
      });
    }

    final tablet = isTablet(context);
    final pronto = _aoVivo != null && _filmes != null;

    return Scaffold(
      backgroundColor: AppColors.surface0,
      body: Stack(
        children: [
          Positioned.fill(
            child: SafeArea(
              child: pronto
                  ? _conteudo(context, lista, tablet)
                  : const SizedBox.shrink(),
            ),
          ),
          // Seta de voltar -> "Quem está assistindo?" (canto superior esquerdo;
          // o avatar fica no direito). Abaixo do overlay de entrada, entao some
          // sob o preto durante a animacao e aparece junto com o conteudo.
          if (pronto)
            Positioned.fill(
              child: SafeArea(
                child: Align(
                  alignment: Alignment.topLeft,
                  child: Padding(
                    padding: const EdgeInsets.only(
                      top: AppSpacing.sm,
                      left: AppSpacing.sm,
                    ),
                    child: const _BotaoVoltarPerfis(),
                  ),
                ),
              ),
            ),
          Positioned.fill(child: _overlayEntrada(context)),
        ],
      ),
    );
  }

  /// Navega para uma secao envolvendo o destino em [AberturaSecao], que toca a
  /// animacao de abertura (icone+nome do botao -> centro -> topo).
  Future<void> _abrirSecao({
    required Rect origem,
    required IconData icone,
    required String titulo,
    required Color cor,
    required Widget destino,
    Future<void>? pronto,
    Duration duracaoMinima = const Duration(milliseconds: 600),
  }) async {
    // Esconde o conteudo do card de origem enquanto a secao esta aberta.
    setState(() => _secaoAtiva = titulo);
    // Rota NAO-OPACA: a home (botoes de selecao) continua visivel por baixo e
    // escurece com o scrim da AberturaSecao durante os estagios 1-2; o destino
    // so e revelado no estagio 3. transitionDuration zero = sem fade da rota na
    // entrada (a propria AberturaSecao faz a introducao); a saida tem um fade.
    await Navigator.of(context).push(
      PageRouteBuilder(
        opaque: false,
        transitionDuration: Duration.zero,
        reverseTransitionDuration: const Duration(milliseconds: 220),
        pageBuilder: (_, _, _) => AberturaSecao(
          origem: origem,
          icone: icone,
          titulo: titulo,
          corIcone: cor,
          pronto: pronto ?? Future<void>.value(),
          duracaoMinima: duracaoMinima,
          child: destino,
        ),
        transitionsBuilder: (_, animation, _, child) =>
            FadeTransition(opacity: animation, child: child),
      ),
    );
    // De volta na home: restaura o conteudo do card.
    if (mounted) setState(() => _secaoAtiva = null);
  }

  Widget _conteudo(BuildContext context, ListaM3U lista, bool tablet) {
    final aoVivo = _aoVivo!;
    final filmes = _filmes!;
    final totalLive = lista.canaisAoVivo.length;

    final cardAoVivo = _CardTipo(
      icone: Icons.live_tv_rounded,
      titulo: 'Canais ao vivo',
      legenda: _legendaContagem(totalLive, 'canal'),
      destaque: true,
      anim: _itemAnim(0.30, 0.62),
      ocultarConteudo: _secaoAtiva == 'Canais ao vivo',
      onTap: (origem) => _abrirSecao(
        origem: origem,
        icone: Icons.live_tv_rounded,
        titulo: 'Canais ao vivo',
        cor: AppColors.accentBright,
        // Canais nao tem load — 1s de cadencia para casar com Filmes/Series.
        duracaoMinima: const Duration(milliseconds: 1000),
        destino: TelaCanais(categorias: aoVivo),
      ),
    );
    final cardFilmes = _CardTipo(
      icone: Icons.movie_creation_outlined,
      titulo: 'Filmes',
      legenda: _legendaContagem(_totalMovies, 'filme'),
      destaque: false,
      anim: _itemAnim(0.40, 0.72),
      ocultarConteudo: _secaoAtiva == 'Filmes',
      onTap: (origem) {
        final pronto = Completer<void>();
        _abrirSecao(
          origem: origem,
          icone: Icons.movie_creation_outlined,
          titulo: 'Filmes',
          cor: AppColors.textSecondary,
          pronto: pronto.future,
          destino: TelaFilmes(categorias: filmes, aoCarregar: pronto.complete),
        );
      },
    );
    final cardSeries = _CardTipo(
      icone: Icons.tv_rounded,
      titulo: 'Séries',
      legenda: _legendaContagem(_totalSeries, 'série'),
      destaque: false,
      anim: _itemAnim(0.50, 0.82),
      ocultarConteudo: _secaoAtiva == 'Séries',
      onTap: (origem) {
        final pronto = Completer<void>();
        _abrirSecao(
          origem: origem,
          icone: Icons.tv_rounded,
          titulo: 'Séries',
          cor: AppColors.textSecondary,
          pronto: pronto.future,
          destino: TelaFilmes(
            categorias: filmes,
            tipo: TipoVod.series,
            aoCarregar: pronto.complete,
          ),
        );
      },
    );
    final cardConfig = _CardTipo(
      icone: Icons.settings_rounded,
      titulo: 'Configurações',
      legenda: null,
      destaque: false,
      anim: _itemAnim(0.60, 0.92),
      // Configuracoes nao usa a abertura animada (nao tem load nem icone fixo).
      onTap: (_) => Navigator.of(
        context,
      ).push(MaterialPageRoute(builder: (_) => const TelaConfiguracoes())),
    );

    // Grid 2x2 centralizado. Largura limitada para sobrar respiro nas laterais
    // (cards menores, sem colar na borda) e nao ficar gigante em tablet/desktop.
    final largura = tablet ? 560.0 : 380.0;
    final nomePerfil = context.watch<PerfilProvider>().perfilAtivo?.nome ?? '';

    return LayoutBuilder(
      builder: (context, c) {
        return SingleChildScrollView(
          child: ConstrainedBox(
            constraints: BoxConstraints(minHeight: c.maxHeight),
            // Levemente acima do centro vertical — estava baixo demais.
            child: Align(
              alignment: const Alignment(0, -0.3),
              child: ConstrainedBox(
                constraints: BoxConstraints(maxWidth: largura),
                child: Padding(
                  padding: const EdgeInsets.symmetric(
                    horizontal: AppSpacing.xl,
                    vertical: AppSpacing.xxl,
                  ),
                  child: Column(
                    mainAxisAlignment: MainAxisAlignment.center,
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      _revelar(
                        0.15,
                        0.42,
                        Column(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            if (nomePerfil.isNotEmpty) ...[
                              _Saudacao(
                                texto: _fraseSaudacao(_saudacao, nomePerfil),
                              ),
                              const SizedBox(height: AppSpacing.md),
                            ],
                            _TituloLista(nome: lista.nome),
                          ],
                        ),
                      ),
                      const SizedBox(height: AppSpacing.xxl),
                      Row(
                        children: [
                          Expanded(child: cardAoVivo),
                          const SizedBox(width: AppSpacing.lg),
                          Expanded(child: cardFilmes),
                        ],
                      ),
                      const SizedBox(height: AppSpacing.lg),
                      Row(
                        children: [
                          Expanded(child: cardSeries),
                          const SizedBox(width: AppSpacing.lg),
                          Expanded(child: cardConfig),
                        ],
                      ),
                    ],
                  ),
                ),
              ),
            ),
          ),
        );
      },
    );
  }
}

/// Formata uma contagem com unidade ("12 filmes", "1.2k canais").
String _legendaContagem(int n, String unidade) {
  if (n >= 1000) {
    final k = (n / 1000).toStringAsFixed(n % 1000 == 0 ? 0 : 1);
    return '${k}k ${unidade}s';
  }
  return '$n ${n == 1 ? unidade : "${unidade}s"}';
}

// ─── Saudacao da home ─────────────────────────────────────────────────────────

/// Frases de boas-vindas (modelo com o nome do perfil). Exibidas alternadamente
/// a cada entrada no perfil.
String _fraseSaudacao(int i, String nome) {
  switch (i % 5) {
    case 0:
      return 'Olá, $nome';
    case 1:
      return 'O que vai assistir hoje, $nome?';
    case 2:
      return 'Bem-vindo de volta, $nome';
    case 3:
      return 'Pronto pra maratonar, $nome?';
    default:
      return 'Boa sessão, $nome!';
  }
}

// Indice da ultima saudacao mostrada — para nao repetir na entrada seguinte.
int _ultimaSaudacao = -1;
int _sortearSaudacao() {
  int i;
  do {
    i = Random().nextInt(5);
  } while (i == _ultimaSaudacao);
  _ultimaSaudacao = i;
  return i;
}

/// Resultado do agrupamento da home (calculado em isolate).
class _DadosHome {
  final Map<String, List<Canal>> aoVivo;
  final Map<String, List<Canal>> filmes;
  final int totalMovies;
  final int totalSeries;
  const _DadosHome(
    this.aoVivo,
    this.filmes,
    this.totalMovies,
    this.totalSeries,
  );
}

/// Funcao top-level para `compute()`: agrupa canais ao vivo, separa filmes de
/// series e conta cada um. Roda em isolate para nao travar a UI.
_DadosHome _agruparHome(ListaM3U lista) {
  final aoVivo = agruparCanaisAoVivo(lista.canaisAoVivo);
  final filmes = lista.agruparPorCategoria(TipoCanal.filme);
  final seriesNomes = <String>{};
  var movies = 0;
  for (final canais in filmes.values) {
    for (final c in canais) {
      final nome = Serie.nomeSerie(c.nome);
      if (nome != null) {
        seriesNomes.add(nome);
      } else {
        movies++;
      }
    }
  }
  return _DadosHome(aoVivo, filmes, movies, seriesNomes.length);
}

// ─── Seta de voltar para a selecao de perfis ──────────────────────────────────

class _BotaoVoltarPerfis extends StatelessWidget {
  const _BotaoVoltarPerfis();

  @override
  Widget build(BuildContext context) {
    return Material(
      color: Colors.transparent,
      shape: const CircleBorder(),
      clipBehavior: Clip.antiAlias,
      child: InkWell(
        customBorder: const CircleBorder(),
        onTap: () {
          // Volta para "Quem está assistindo?": o gate (app.dart) troca a tela.
          context.read<PerfilProvider>().trocarPerfil();
          Navigator.of(context).popUntil((r) => r.isFirst);
        },
        child: const Padding(
          padding: EdgeInsets.all(AppSpacing.sm),
          child: Icon(
            Icons.arrow_back_rounded,
            size: 24,
            color: AppColors.textPrimary,
          ),
        ),
      ),
    );
  }
}

// ─── Botão de perfil (avatar) com menu "Trocar usuário" ───────────────────────

class _BotaoPerfil extends StatelessWidget {
  final double tamanho;
  const _BotaoPerfil({this.tamanho = 50});

  Future<void> _abrirMenu(BuildContext context, Perfil perfil) async {
    final box = context.findRenderObject() as RenderBox?;
    final overlay =
        Overlay.of(context).context.findRenderObject() as RenderBox?;
    if (box == null || overlay == null) return;
    final origem = box.localToGlobal(Offset.zero, ancestor: overlay);
    final pos = RelativeRect.fromLTRB(
      origem.dx - 120,
      origem.dy + box.size.height + AppSpacing.xs,
      overlay.size.width - origem.dx - box.size.width,
      0,
    );

    final v = await showMenu<String>(
      context: context,
      position: pos,
      color: AppColors.surface2,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(AppRadius.base),
      ),
      items: [
        PopupMenuItem<String>(
          enabled: false,
          child: Row(
            children: [
              AvatarPerfil(chave: perfil.icone, tamanho: 32),
              const SizedBox(width: AppSpacing.sm),
              Flexible(
                child: Text(
                  perfil.nome,
                  style: Theme.of(context).textTheme.titleSmall,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
              ),
            ],
          ),
        ),
        const PopupMenuDivider(),
        const PopupMenuItem<String>(
          value: 'trocar',
          child: ListTile(
            dense: true,
            contentPadding: EdgeInsets.zero,
            leading: Icon(Icons.switch_account_rounded, size: 20),
            title: Text('Trocar usuário'),
          ),
        ),
        const PopupMenuItem<String>(
          value: 'config',
          child: ListTile(
            dense: true,
            contentPadding: EdgeInsets.zero,
            leading: Icon(Icons.settings_rounded, size: 20),
            title: Text('Configurações'),
          ),
        ),
      ],
    );

    if (!context.mounted) return;
    if (v == 'trocar') {
      // Volta para "Quem está assistindo?": o app.dart troca a tela raiz.
      context.read<PerfilProvider>().trocarPerfil();
      Navigator.of(context).popUntil((r) => r.isFirst);
    } else if (v == 'config') {
      Navigator.of(
        context,
      ).push(MaterialPageRoute(builder: (_) => const TelaConfiguracoes()));
    }
  }

  @override
  Widget build(BuildContext context) {
    final perfil = context.watch<PerfilProvider>().perfilAtivo;
    if (perfil == null) return SizedBox(width: tamanho, height: tamanho);

    // InkWell com recorte CIRCULAR: o splash/realce respeita o circulo do
    // avatar (antes o PopupMenuButton mostrava um quadrado branco atras).
    return Material(
      color: Colors.transparent,
      shape: const CircleBorder(),
      clipBehavior: Clip.antiAlias,
      child: InkWell(
        customBorder: const CircleBorder(),
        onTap: () => _abrirMenu(context, perfil),
        child: AvatarPerfil(chave: perfil.icone, tamanho: tamanho),
      ),
    );
  }
}

// ─── Home sem lista (empty state) ─────────────────────────────────────────────

class _HomeSemLista extends StatelessWidget {
  const _HomeSemLista();

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.surface0,
      body: SafeArea(
        child: Stack(
          children: [
            Align(
              alignment: Alignment.topRight,
              child: Padding(
                padding: const EdgeInsets.only(
                  top: AppSpacing.xs,
                  right: AppSpacing.xs,
                ),
                child: const _BotaoPerfil(tamanho: 50),
              ),
            ),
            Center(
              child: ConstrainedBox(
                constraints: const BoxConstraints(maxWidth: 480),
                child: Padding(
                  padding: const EdgeInsets.symmetric(
                    horizontal: AppSpacing.xl,
                  ),
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      const Spacer(),
                      Center(
                        child: Container(
                          width: 88,
                          height: 88,
                          decoration: BoxDecoration(
                            color: AppColors.surface1,
                            borderRadius: BorderRadius.circular(AppRadius.lg),
                          ),
                          child: const Icon(
                            Icons.playlist_play_rounded,
                            size: 44,
                            color: AppColors.accent,
                          ),
                        ),
                      ),
                      const SizedBox(height: AppSpacing.xl),
                      Text(
                        'Bem-vindo',
                        style: Theme.of(context).textTheme.headlineMedium,
                        textAlign: TextAlign.center,
                      ),
                      const SizedBox(height: AppSpacing.sm),
                      Text(
                        'Importe sua primeira lista IPTV para começar a assistir.',
                        style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                          color: AppColors.textSecondary,
                        ),
                        textAlign: TextAlign.center,
                      ),
                      const SizedBox(height: AppSpacing.xl),
                      FilledButton.icon(
                        onPressed: () => Navigator.of(context).push(
                          MaterialPageRoute(
                            builder: (_) => const TelaImportar(),
                          ),
                        ),
                        icon: const Icon(Icons.add_rounded),
                        label: const Text('Importar lista M3U'),
                        style: FilledButton.styleFrom(
                          padding: const EdgeInsets.symmetric(
                            vertical: AppSpacing.base,
                          ),
                        ),
                      ),
                      const SizedBox(height: AppSpacing.md),
                      OutlinedButton.icon(
                        onPressed: () => Navigator.of(context).push(
                          MaterialPageRoute(
                            builder: (_) => const TelaConfiguracoes(),
                          ),
                        ),
                        icon: const Icon(Icons.settings_rounded, size: 18),
                        label: const Text('Configurações'),
                        style: OutlinedButton.styleFrom(
                          padding: const EdgeInsets.symmetric(
                            vertical: AppSpacing.base,
                          ),
                        ),
                      ),
                      const Spacer(flex: 2),
                    ],
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

// ─── Saudacao (boas-vindas) ───────────────────────────────────────────────────

class _Saudacao extends StatelessWidget {
  final String texto;
  const _Saudacao({required this.texto});

  @override
  Widget build(BuildContext context) {
    return Text(
      texto,
      textAlign: TextAlign.center,
      maxLines: 2,
      overflow: TextOverflow.ellipsis,
      // Grande e bold para se destacar, mas na mesma fonte (Manrope) do app.
      style: Theme.of(context).textTheme.headlineMedium?.copyWith(
            fontWeight: FontWeight.w800,
            letterSpacing: -0.4,
            height: 1.15,
          ),
    );
  }
}

// ─── Titulo da lista ativa (centralizado, discreto) ───────────────────────────

class _TituloLista extends StatelessWidget {
  final String nome;
  const _TituloLista({required this.nome});

  @override
  Widget build(BuildContext context) {
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        Text(
          'LISTA ATIVA',
          textAlign: TextAlign.center,
          style: Theme.of(context).textTheme.labelSmall?.copyWith(
            color: AppColors.textTertiary,
            letterSpacing: 1.6,
          ),
        ),
        const SizedBox(height: 4),
        Text(
          nome,
          textAlign: TextAlign.center,
          style: Theme.of(context).textTheme.titleLarge,
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
        ),
      ],
    );
  }
}

// ─── Card de tipo (grid 2x2): icone + nome dentro, sombra offset animada ──────

class _CardTipo extends StatefulWidget {
  final IconData icone;
  final String titulo;
  final String? legenda;
  final bool destaque;
  final Animation<double> anim;

  /// Recebe o Rect GLOBAL do icone tocado — origem da animacao de abertura.
  final void Function(Rect origemIcone) onTap;

  /// Quando true, esconde o icone+nome (o card fica vazio) — usado enquanto a
  /// secao esta aberta, para parecer que o conteudo "saiu" rumo ao centro.
  final bool ocultarConteudo;

  const _CardTipo({
    required this.icone,
    required this.titulo,
    required this.legenda,
    required this.destaque,
    required this.anim,
    required this.onTap,
    this.ocultarConteudo = false,
  });

  @override
  State<_CardTipo> createState() => _CardTipoState();
}

class _CardTipoState extends State<_CardTipo> {
  static const _radius = 22.0;
  // Chave no icone para descobrir sua posicao global no momento do toque.
  final GlobalKey _iconeKey = GlobalKey();

  void _aoTocar() {
    final box = _iconeKey.currentContext?.findRenderObject() as RenderBox?;
    if (box != null && box.hasSize) {
      widget.onTap(box.localToGlobal(Offset.zero) & box.size);
    } else {
      widget.onTap(Rect.zero);
    }
  }

  @override
  Widget build(BuildContext context) {
    final icone = widget.icone;
    final titulo = widget.titulo;
    final legenda = widget.legenda;
    final destaque = widget.destaque;
    final anim = widget.anim;

    // Sombra offset: vermelha no card de destaque (TV ao vivo), cinza-quente
    // (mais clara que o fundo, por isso visivel no dark) nos demais.
    final corSombra = destaque ? AppColors.accent : AppColors.surface3;

    return AnimatedBuilder(
      animation: anim,
      builder: (context, child) {
        final t = anim.value.clamp(0.0, 1.0);
        return Opacity(
          opacity: t,
          child: Transform.translate(
            offset: Offset(0, (1 - t) * 22),
            child: Transform.scale(
              scale: 0.90 + 0.10 * t,
              child: AspectRatio(
                aspectRatio: 1,
                child: DecoratedBox(
                  decoration: BoxDecoration(
                    color: AppColors.surface1,
                    borderRadius: BorderRadius.circular(_radius),
                    border: Border.all(
                      color: destaque
                          ? AppColors.accent.withValues(alpha: 0.30)
                          : AppColors.outlineSubtle,
                    ),
                    // A sombra cresce junto com o card (blur/offset/alpha * t).
                    // O vermelho do destaque fica mais discreto que o cinza dos
                    // demais (a saturacao ja chama atencao por si).
                    boxShadow: [
                      BoxShadow(
                        color: corSombra.withValues(
                          alpha: (destaque ? 0.34 : 0.45) * t,
                        ),
                        blurRadius: (destaque ? 24 : 26) * t,
                        spreadRadius: -4,
                        offset: Offset(0, (destaque ? 14 : 13) * t),
                      ),
                    ],
                  ),
                  child: child,
                ),
              ),
            ),
          ),
        );
      },
      // Conteudo (icone+nome). Fica invisivel enquanto a secao esta aberta —
      // assim parece que ele "saiu" do botao para o centro (sem duplicar).
      child: Opacity(
        opacity: widget.ocultarConteudo ? 0 : 1,
        child: Material(
          color: Colors.transparent,
          borderRadius: BorderRadius.circular(_radius),
          clipBehavior: Clip.antiAlias,
          child: InkWell(
            onTap: _aoTocar,
            borderRadius: BorderRadius.circular(_radius),
            child: Padding(
              padding: const EdgeInsets.all(AppSpacing.base),
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Container(
                    key: _iconeKey,
                    width: 56,
                    height: 56,
                    decoration: BoxDecoration(
                      color: destaque
                          ? AppColors.accent.withValues(alpha: 0.12)
                          : AppColors.surface2,
                      borderRadius: BorderRadius.circular(AppRadius.base),
                    ),
                    child: Icon(
                      icone,
                      size: 28,
                      color: destaque
                          ? AppColors.accentBright
                          : AppColors.textSecondary,
                    ),
                  ),
                  const SizedBox(height: AppSpacing.md),
                  Text(
                    titulo,
                    textAlign: TextAlign.center,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: Theme.of(context).textTheme.titleMedium,
                  ),
                  if (legenda != null) ...[
                    const SizedBox(height: 2),
                    Text(
                      legenda,
                      textAlign: TextAlign.center,
                      style: tabular(
                        Theme.of(context).textTheme.bodySmall?.copyWith(
                          color: AppColors.textTertiary,
                        ),
                      ),
                    ),
                  ],
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}
