import 'dart:ui';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../models/canal.dart';
import '../models/serie.dart';
import '../services/controle_parental.dart';
import '../services/tmdb_service.dart';
import '../state/iptv_provider.dart';
import '../state/preferencias_provider.dart';
import '../theme/app_theme.dart';
import '../utils/chave_conteudo.dart';
import '../utils/layout.dart';
import '../widgets/skeleton.dart';
import 'tela_player.dart';

// Pôster — mobile/tablet.
const double _kPosterW = 132.0;
const double _kPosterH = 198.0; // proporcao 2:3
// Pôster — desktop (maior, vira o "herói" do layout de duas colunas).
const double _kPosterWDesktop = 300.0;
const double _kPosterHDesktop = 450.0;
const double _kMaxLarguraDesktop = 1120.0;

/// Tela intermediaria de detalhes de um filme ou serie.
///
/// Abre instantaneamente com o banner ja visivel. Sinopse, ano e elenco
/// chegam de forma assincrona — enquanto o TMDB responde, os textos
/// aparecem como skeleton/shimmer, sem travar a interface.
///
/// Layout adapta: no desktop usa duas colunas (poster grande + conteudo);
/// no mobile/tablet, layout empilhado.
class TelaDetalhes extends StatefulWidget {
  final Canal? filme;
  final Serie? serie;

  /// Tag do Hero do banner de origem (carrossel/destaque). Quando presente, o
  /// banner anima da posição clicada até aqui.
  final Object? heroTag;

  const TelaDetalhes.filme(Canal this.filme, {super.key, this.heroTag})
      : serie = null;
  const TelaDetalhes.serie(Serie this.serie, {super.key, this.heroTag})
      : filme = null;

  bool get ehSerie => serie != null;

  @override
  State<TelaDetalhes> createState() => _TelaDetalhesState();
}

/// Resultado do agrupamento de episodios por temporada.
typedef _EpisodiosAgrupados = ({
  Map<int, List<Canal>> porTemporada,
  List<int> temporadas,
  List<Object> itens, // int = marcador de temporada, Canal = episodio
});

/// Seleciona até 10 filmes do mesmo grupo (tag) do [filme], aleatórios.
/// `Serie.agrupar` separa filmes puros de episódios de série dentro do grupo.
List<Canal> _selecionarRelacionados(List<Canal> canais, Canal filme) {
  final mesmoGrupo = canais
      .where((c) => c.tipo == TipoCanal.filme && c.grupo == filme.grupo)
      .toList();
  if (mesmoGrupo.isEmpty) return const [];
  final ag = Serie.agrupar(mesmoGrupo);
  final rel = ag.filmes
      .where((c) => chaveConteudo(c.url) != chaveConteudo(filme.url))
      .toList()
    ..shuffle();
  return rel.take(10).toList();
}

class _TelaDetalhesState extends State<TelaDetalhes> {
  late Future<TmdbInfo> _infoFuture;
  Future<String?>? _posterSerieFuture;
  // Filmes relacionados (mesmo grupo/tag) — calculado async para não atrasar
  // a abertura da tela (FutureBuilder mostra skeleton enquanto seleciona).
  Future<List<Canal>>? _relacionadosFuture;
  // Escopo único deste detalhe para as tags Hero dos relacionados — evita
  // flights cruzados quando o próximo detalhe tem os mesmos filmes do grupo.
  late final String _heroEscopo = 'rel${identityHashCode(this)}';
  _EpisodiosAgrupados? _agrup;
  int? _temporadaSelecionada;

  String get _nome => widget.ehSerie ? widget.serie!.nome : widget.filme!.nome;

  String get _grupo =>
      widget.ehSerie ? widget.serie!.grupo : widget.filme!.grupo;

  /// `true` enquanto o controle dos pais nao liberou este titulo — a tela fica
  /// vazia (sem capa, sem sinopse) ate o PIN ser aceito.
  bool _bloqueadoPorPin = false;

  @override
  void initState() {
    super.initState();

    // Controle dos pais: nem os metadados sao carregados antes do PIN.
    if (ControleParental.exigePin(context, _grupo)) {
      _bloqueadoPorPin = true;
      _infoFuture = Future.value(TmdbInfo.vazio);
      WidgetsBinding.instance
          .addPostFrameCallback((_) => _pedirLiberacaoParental());
      return;
    }
    _carregarMetadados();
  }

  Future<void> _pedirLiberacaoParental() async {
    final liberou = await ControleParental.liberar(context, _grupo);
    if (!mounted) return;
    if (!liberou) {
      Navigator.of(context).maybePop();
      return;
    }
    setState(_carregarMetadados);
  }

  void _carregarMetadados() {
    _bloqueadoPorPin = false;
    final tmdb = context.read<TmdbService>();
    final idioma = context.read<PreferenciasProvider>().idiomaEfetivo.codigo;

    _infoFuture = tmdb.info(
      nome: _nome,
      ehSerie: widget.ehSerie,
      idioma: idioma,
      // A categoria da lista desempata homonimos — "ONE PIECE" em ANIMES e o
      // anime; em SERIES e o live action.
      categoria: _grupo,
    );
    if (widget.ehSerie) {
      _posterSerieFuture =
          tmdb.poster(widget.serie!.nome, categoria: widget.serie!.grupo);
      _agrup = _agruparEpisodios(widget.serie!);
      _temporadaSelecionada =
          _agrup!.temporadas.isNotEmpty ? _agrup!.temporadas.first : null;
    } else {
      // Captura o catálogo agora (sync) e seleciona depois, fora do 1º frame.
      final canais =
          context.read<IptvProvider>().listaAtiva?.canais ?? const <Canal>[];
      final filme = widget.filme!;
      _relacionadosFuture = Future(() => _selecionarRelacionados(canais, filme));
    }
  }

  /// Envolve o banner num Hero (destino da animação vinda do carrossel).
  /// Trajetória reta (diagonal) em vez do arco padrão do Material.
  Widget _bannerComHero(Widget banner) {
    if (widget.heroTag == null) return banner;
    return Hero(
      tag: widget.heroTag!,
      createRectTween: (begin, end) => RectTween(begin: begin, end: end),
      child: banner,
    );
  }

  /// Envolve o cabeçalho com o fundo desfocado do banner (que some em preto
  /// na base). Em série a URL do banner vem do TMDB (fallback: logo M3U).
  Widget _cabecalhoComFundo(Widget cabecalho) {
    if (!widget.ehSerie) {
      return _HeaderComFundo(url: widget.filme!.logoUrl, child: cabecalho);
    }
    return FutureBuilder<String?>(
      future: _posterSerieFuture,
      builder: (context, snap) {
        final url = (snap.data != null && snap.data!.isNotEmpty)
            ? snap.data
            : (widget.serie!.logoUrl?.isNotEmpty == true
                ? widget.serie!.logoUrl
                : null);
        return _HeaderComFundo(url: url, child: cabecalho);
      },
    );
  }

  @override
  Widget build(BuildContext context) {
    if (_bloqueadoPorPin) {
      // Nada do titulo aparece enquanto o PIN nao for aceito.
      return const Scaffold(body: SizedBox());
    }
    return Scaffold(
      // Fundo blur do banner sobe atrás da appbar transparente (até o "voltar").
      extendBodyBehindAppBar: true,
      appBar: AppBar(
        backgroundColor: Colors.transparent,
        elevation: 0,
        scrolledUnderElevation: 0,
      ),
      body: isDesktop(context)
          ? _buildDesktop(context)
          : tabletBody(
              context,
              widget.ehSerie ? _buildSerieMobile() : _buildFilmeMobile(),
            ),
    );
  }

  // ─── Agrupamento de episodios (compartilhado) ────────────────────────────

  _EpisodiosAgrupados _agruparEpisodios(Serie serie) {
    final porTemporada = <int, List<Canal>>{};
    for (final ep in serie.episodios) {
      (porTemporada[Serie.seasonOf(ep)] ??= []).add(ep);
    }
    final temporadas = porTemporada.keys.toList()..sort();

    final itens = <Object>[];
    for (final t in temporadas) {
      itens.add(t);
      itens.addAll(porTemporada[t]!);
    }
    return (porTemporada: porTemporada, temporadas: temporadas, itens: itens);
  }

  // ─── Layout MOBILE / TABLET (empilhado) ──────────────────────────────────

  Widget _buildFilmeMobile() {
    return ListView(
      padding: const EdgeInsets.only(bottom: AppSpacing.xxl),
      children: [
        _cabecalhoComFundo(
          _Cabecalho(
            nome: _nome,
            banner: _bannerComHero(_BannerFilme(url: widget.filme!.logoUrl)),
            infoFuture: _infoFuture,
            acao: _AcaoFilme(filme: widget.filme!),
          ),
        ),
        const _Divisoria(),
        _SecaoSinopse(infoFuture: _infoFuture),
        _SecaoElenco(infoFuture: _infoFuture),
        if (_relacionadosFuture != null)
          _SecaoRelacionados(
            future: _relacionadosFuture!,
            escopo: _heroEscopo,
          ),
      ],
    );
  }

  Widget _buildSerieMobile() {
    final serie = widget.serie!;
    final agrup = _agrup!;
    final temporada = _temporadaSelecionada ?? agrup.temporadas.first;
    final episodios = agrup.porTemporada[temporada] ?? [];

    return CustomScrollView(
      slivers: [
        SliverToBoxAdapter(
          child: Column(
            children: [
              _cabecalhoComFundo(
                _Cabecalho(
                  nome: _nome,
                  banner: _bannerComHero(_BannerSerie(
                    posterFuture: _posterSerieFuture,
                    logoM3U: serie.logoUrl,
                  )),
                  infoFuture: _infoFuture,
                  acao: _AcaoSerie(serie: serie),
                  subtitulo: _descricaoSerie(
                    agrup.temporadas.length,
                    serie.totalEpisodios,
                  ),
                ),
              ),
              const _Divisoria(),
              _SecaoSinopse(infoFuture: _infoFuture),
              _SecaoElenco(infoFuture: _infoFuture),
              _SeletorTemporada(
                temporadas: agrup.temporadas,
                selecionada: temporada,
                onSelecionada: (t) => setState(() => _temporadaSelecionada = t),
              ),
            ],
          ),
        ),
        SliverList.builder(
          itemCount: episodios.length,
          itemBuilder: (_, i) => _ItemEpisodio(
            episodio: episodios[i],
            episodiosSerie: serie.episodios,
          ),
        ),
        const SliverToBoxAdapter(child: SizedBox(height: AppSpacing.xxl)),
      ],
    );
  }

  // ─── Layout DESKTOP (duas colunas) ───────────────────────────────────────

  Widget _buildDesktop(BuildContext context) {
    final serie = widget.serie;
    final agrup = _agrup;

    // Pôster grande com sombra suave.
    final banner = Container(
      width: _kPosterWDesktop,
      height: _kPosterHDesktop,
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(AppRadius.base),
        boxShadow: const [
          BoxShadow(
            color: Colors.black54,
            blurRadius: 24,
            offset: Offset(0, 10),
          ),
        ],
      ),
      child: _bannerComHero(
        widget.ehSerie
            ? _BannerSerie(
                posterFuture: _posterSerieFuture,
                logoM3U: serie!.logoUrl,
              )
            : _BannerFilme(url: widget.filme!.logoUrl),
      ),
    );

    // Coluna de conteudo ao lado do poster.
    final info = Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          _nome,
          style: Theme.of(context).textTheme.headlineMedium,
          maxLines: 3,
          overflow: TextOverflow.ellipsis,
        ),
        const SizedBox(height: AppSpacing.sm),
        _LinhaMeta(
          infoFuture: _infoFuture,
          subtitulo: agrup != null
              ? _descricaoSerie(agrup.temporadas.length, serie!.totalEpisodios)
              : null,
        ),
        _MetaDetalhe(infoFuture: _infoFuture),
        const SizedBox(height: AppSpacing.xl),
        ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 440),
          child: widget.ehSerie
              ? _AcaoSerie(serie: serie!)
              : _AcaoFilme(filme: widget.filme!),
        ),
        const SizedBox(height: AppSpacing.xl),
        _SecaoSinopse(infoFuture: _infoFuture, padH: 0),
        _SecaoElenco(infoFuture: _infoFuture, padH: 0),
      ],
    );

    final cabecalho = _cabecalhoComFundo(
      Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          banner,
          const SizedBox(width: AppSpacing.xxl),
          Expanded(child: info),
        ],
      ),
    );

    // Filme: rolagem simples do cabeçalho + relacionados.
    if (agrup == null) {
      return Center(
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: _kMaxLarguraDesktop),
          child: SingleChildScrollView(
            padding: const EdgeInsets.fromLTRB(
                AppSpacing.xxl, 0, AppSpacing.xxl, AppSpacing.xxl),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                cabecalho,
                if (_relacionadosFuture != null)
                  Padding(
                    padding: const EdgeInsets.only(top: AppSpacing.xl),
                    child: _SecaoRelacionados(
                      future: _relacionadosFuture!,
                      escopo: _heroEscopo,
                      padH: 0,
                    ),
                  ),
              ],
            ),
          ),
        ),
      );
    }

    // Série: cabeçalho + seletor + lista da temporada ativa.
    final temporada = _temporadaSelecionada ?? agrup.temporadas.first;
    final episodios = agrup.porTemporada[temporada] ?? [];

    return Center(
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: _kMaxLarguraDesktop),
        child: CustomScrollView(
          slivers: [
            SliverPadding(
              padding: const EdgeInsets.fromLTRB(AppSpacing.xxl, 0, AppSpacing.xxl, 0),
              sliver: SliverToBoxAdapter(child: cabecalho),
            ),
            SliverPadding(
              padding: const EdgeInsets.symmetric(horizontal: AppSpacing.xxl),
              sliver: SliverToBoxAdapter(
                child: _SeletorTemporada(
                  temporadas: agrup.temporadas,
                  selecionada: temporada,
                  onSelecionada: (t) => setState(() => _temporadaSelecionada = t),
                  padH: 0,
                  desktop: true,
                ),
              ),
            ),
            SliverPadding(
              padding: const EdgeInsets.symmetric(horizontal: AppSpacing.xxl),
              sliver: SliverList.builder(
                itemCount: episodios.length,
                itemBuilder: (_, i) => _ItemEpisodio(
                  episodio: episodios[i],
                  episodiosSerie: serie!.episodios,
                  padH: 0,
                  desktop: true,
                ),
              ),
            ),
            const SliverToBoxAdapter(child: SizedBox(height: AppSpacing.xxl)),
          ],
        ),
      ),
    );
  }

  static String _descricaoSerie(int t, int e) {
    final ts = t == 1 ? '1 temporada' : '$t temporadas';
    final es = e == 1 ? '1 episódio' : '$e episódios';
    return '$ts · $es';
  }
}

// ─── Cabecalho mobile (banner + titulo + ano + botoes empilhados) ──────────

class _Cabecalho extends StatelessWidget {
  final String nome;
  final Widget banner;
  final Future<TmdbInfo> infoFuture;
  final Widget acao;
  final String? subtitulo;

  const _Cabecalho({
    required this.nome,
    required this.banner,
    required this.infoFuture,
    required this.acao,
    this.subtitulo,
  });

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.all(AppSpacing.lg),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              SizedBox(width: _kPosterW, height: _kPosterH, child: banner),
              const SizedBox(width: AppSpacing.lg),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      nome,
                      style: Theme.of(context).textTheme.titleLarge,
                      maxLines: 4,
                      overflow: TextOverflow.ellipsis,
                    ),
                    const SizedBox(height: AppSpacing.sm),
                    _LinhaMeta(infoFuture: infoFuture, subtitulo: subtitulo),
                    _MetaDetalhe(infoFuture: infoFuture),
                  ],
                ),
              ),
            ],
          ),
          const SizedBox(height: AppSpacing.lg),
          acao,
        ],
      ),
    );
  }
}

/// Linha "ano · subtitulo". O ano chega do TMDB de forma assincrona.
class _LinhaMeta extends StatelessWidget {
  final Future<TmdbInfo> infoFuture;
  final String? subtitulo;

  const _LinhaMeta({required this.infoFuture, this.subtitulo});

  @override
  Widget build(BuildContext context) {
    final estilo = Theme.of(context).textTheme.bodySmall?.copyWith(
          color: AppColors.textSecondary,
        );
    return FutureBuilder<TmdbInfo>(
      future: infoFuture,
      builder: (context, snap) {
        final carregando = snap.connectionState != ConnectionState.done;
        // Sem subtitulo e ainda carregando -> nada para mostrar -> shimmer.
        if (carregando && subtitulo == null) {
          return const Shimmer(child: SkeletonBox(width: 64, height: 12));
        }
        final ano = snap.data?.ano;
        final partes = <String>[
          if (ano != null) '$ano',
          ?subtitulo,
        ];
        if (partes.isEmpty) return const SizedBox.shrink();
        return Text(partes.join('  ·  '), style: estilo);
      },
    );
  }
}

/// Bloco de metadados abaixo do nome/ano: nota (TMDB ~IMDB) e generos.
/// Preenche o espaco ao lado do poster. Chega de forma assincrona e some se
/// nao houver dado. (Os generos serao usados para recomendar titulos relacionados.)
class _MetaDetalhe extends StatelessWidget {
  final Future<TmdbInfo> infoFuture;

  const _MetaDetalhe({required this.infoFuture});

  @override
  Widget build(BuildContext context) {
    return FutureBuilder<TmdbInfo>(
      future: infoFuture,
      builder: (context, snap) {
        if (snap.connectionState != ConnectionState.done) {
          return const Padding(
            padding: EdgeInsets.only(top: AppSpacing.sm),
            child: Shimmer(child: SkeletonBox(width: 120, height: 13)),
          );
        }
        final info = snap.data;
        final nota = info?.nota;
        final generos = info?.generos ?? const <String>[];
        if (nota == null && generos.isEmpty) return const SizedBox.shrink();
        final valStyle = Theme.of(context).textTheme.bodySmall?.copyWith(
          color: AppColors.textSecondary,
        );
        return Padding(
          padding: const EdgeInsets.only(top: AppSpacing.sm),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              if (nota != null)
                Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    const Icon(
                      Icons.star_rounded,
                      size: 15,
                      color: AppColors.warn,
                    ),
                    const SizedBox(width: 4),
                    Text(
                      nota.toStringAsFixed(1),
                      style: Theme.of(context).textTheme.bodySmall?.copyWith(
                        color: AppColors.textPrimary,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                    Text(
                      ' /10',
                      style: Theme.of(context).textTheme.labelSmall?.copyWith(
                        color: AppColors.textTertiary,
                      ),
                    ),
                  ],
                ),
              if (generos.isNotEmpty)
                Padding(
                  padding: const EdgeInsets.only(top: 4),
                  child: Text(
                    generos.join(' · '),
                    style: valStyle,
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                  ),
                ),
            ],
          ),
        );
      },
    );
  }
}

// ─── Acoes (Assistir / Continuar + Voltar) ─────────────────────────────────

class _AcaoFilme extends StatelessWidget {
  final Canal filme;
  const _AcaoFilme({required this.filme});

  @override
  Widget build(BuildContext context) {
    final provider = context.watch<IptvProvider>();
    final progresso = provider.obterProgresso(filme);
    final continuar = progresso != null;
    final naLista = provider.ehMinhaLista(filme);

    return _BotoesAcao(
      label: continuar ? 'Continuar' : 'Assistir',
      naMinhaLista: naLista,
      onMinhaLista: () => provider.alternarMinhaLista(filme),
      onAssistir: () {
        provider.registrarVisualizacao(filme);
        Navigator.of(context).push(
          MaterialPageRoute(
            builder: (_) => TelaPlayer(
              canal: filme,
              posicaoInicial: continuar
                  ? Duration(seconds: progresso.posicaoSeg)
                  : null,
            ),
          ),
        );
      },
    );
  }
}

class _AcaoSerie extends StatelessWidget {
  final Serie serie;
  const _AcaoSerie({required this.serie});

  @override
  Widget build(BuildContext context) {
    final provider = context.watch<IptvProvider>();
    final retomada = _calcularRetomada(serie, provider);
    final naLista = provider.ehMinhaLista(serie);

    final label = retomada.continuar
        ? 'Continuar T${Serie.seasonOf(retomada.episodio)}'
            ':E${Serie.episodeOf(retomada.episodio)}'
        : 'Assistir';

    return _BotoesAcao(
      label: label,
      naMinhaLista: naLista,
      onMinhaLista: () => provider.alternarMinhaLista(serie),
      onAssistir: () {
        provider.registrarVisualizacao(retomada.episodio);
        Navigator.of(context).push(
          MaterialPageRoute(
            builder: (_) => TelaPlayer(
              canal: retomada.episodio,
              episodiosSerie: serie.episodios,
              posicaoInicial: retomada.posicao > Duration.zero
                  ? retomada.posicao
                  : null,
            ),
          ),
        );
      },
    );
  }
}

class _BotoesAcao extends StatelessWidget {
  final String label;
  final VoidCallback onAssistir;
  final bool naMinhaLista;
  final VoidCallback onMinhaLista;

  const _BotoesAcao({
    required this.label,
    required this.onAssistir,
    required this.naMinhaLista,
    required this.onMinhaLista,
  });

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        FilledButton.icon(
          onPressed: onAssistir,
          icon: const Icon(Icons.play_arrow_rounded, size: 20),
          label: Text(label),
        ),
        const SizedBox(height: AppSpacing.sm),
        OutlinedButton.icon(
          onPressed: onMinhaLista,
          icon: Icon(
            naMinhaLista
                ? Icons.bookmark_rounded
                : Icons.bookmark_border_rounded,
            size: 18,
          ),
          label: Text(
            naMinhaLista ? 'Remover da minha lista' : 'Adicionar à minha lista',
          ),
        ),
        const SizedBox(height: AppSpacing.sm),
        OutlinedButton(
          onPressed: () => Navigator.of(context).maybePop(),
          child: const Text('Voltar'),
        ),
      ],
    );
  }
}

/// Decisao de onde a serie deve retomar.
class _Retomada {
  final Canal episodio;
  final Duration posicao;

  /// `true` quando o usuario ja viu algo da serie (botao vira "Continuar").
  final bool continuar;

  const _Retomada({
    required this.episodio,
    required this.posicao,
    required this.continuar,
  });
}

/// Calcula em que episodio a serie deve abrir:
///  1. Ha episodio com progresso salvo -> retoma o de progresso mais recente.
///  2. Sem progresso, mas ha episodios no historico -> avanca para o
///     episodio seguinte ao mais avancado ja assistido.
///  3. Nada visto -> primeiro episodio ("Assistir").
_Retomada _calcularRetomada(Serie serie, IptvProvider provider) {
  // 1. Episodio com progresso mais recente.
  Canal? epProgresso;
  int posSeg = 0;
  DateTime? maisRecente;
  for (final ep in serie.episodios) {
    final p = provider.obterProgresso(ep);
    if (p == null) continue;
    if (maisRecente == null || p.atualizadoEm.isAfter(maisRecente)) {
      maisRecente = p.atualizadoEm;
      epProgresso = ep;
      posSeg = p.posicaoSeg;
    }
  }
  if (epProgresso != null) {
    return _Retomada(
      episodio: epProgresso,
      posicao: Duration(seconds: posSeg),
      continuar: true,
    );
  }

  // 2. Episodio mais avancado ja aberto (historico). episodios ja vem
  //    ordenados por (temporada, episodio), entao o ultimo match e o maior.
  final urlsHistorico =
      provider.historico.map((h) => chaveConteudo(h.canal.url)).toSet();
  Canal? maisAvancado;
  for (final ep in serie.episodios) {
    if (urlsHistorico.contains(chaveConteudo(ep.url))) maisAvancado = ep;
  }
  if (maisAvancado != null) {
    final idx = serie.episodios.indexOf(maisAvancado);
    if (idx >= 0 && idx + 1 < serie.episodios.length) {
      return _Retomada(
        episodio: serie.episodios[idx + 1],
        posicao: Duration.zero,
        continuar: true,
      );
    }
    // Ja viu o ultimo episodio: reabre nele mesmo.
    return _Retomada(
      episodio: maisAvancado,
      posicao: Duration.zero,
      continuar: true,
    );
  }

  // 3. Nada visto.
  return _Retomada(
    episodio: serie.episodios.first,
    posicao: Duration.zero,
    continuar: false,
  );
}

// ─── Fundo desfocado do topo (estilo destaque) ─────────────────────────────

/// Empilha o fundo desfocado do banner atrás do cabeçalho. O blur preenche
/// toda a área (inclusive atrás da appbar transparente) e some em preto na
/// base; o cabeçalho recebe um respiro no topo para não ficar sob o "voltar".
class _HeaderComFundo extends StatelessWidget {
  final String? url;
  final Widget child;
  const _HeaderComFundo({required this.url, required this.child});

  @override
  Widget build(BuildContext context) {
    final topInset = MediaQuery.paddingOf(context).top + kToolbarHeight;
    return Stack(
      children: [
        Positioned.fill(child: _FundoBlur(url: url)),
        Padding(
          padding: EdgeInsets.only(top: topInset),
          child: child,
        ),
      ],
    );
  }
}

/// Fundo desfocado: imagem borrada sobre base preta sólida. A imagem some
/// (vira transparente) antes da borda inferior via ShaderMask, deixando só a
/// base preta — assim o corte do ClipRect cai sobre preto e não há linha nem
/// rebarba do blur (mesma técnica do carrossel de destaque).
class _FundoBlur extends StatelessWidget {
  final String? url;
  const _FundoBlur({required this.url});

  @override
  Widget build(BuildContext context) {
    if (url == null || url!.isEmpty) {
      return const ColoredBox(color: AppColors.surface0);
    }
    // No desktop o blur é um retângulo dentro do conteúdo centralizado — as
    // bordas precisam dissolver em preto (no mobile ele ocupa a largura toda).
    final desktop = isDesktop(context);
    return ClipRect(
      child: Stack(
        fit: StackFit.expand,
        clipBehavior: Clip.hardEdge,
        children: [
          const ColoredBox(color: AppColors.surface0),
          ShaderMask(
            shaderCallback: (rect) => const LinearGradient(
              begin: Alignment.topCenter,
              end: Alignment.bottomCenter,
              stops: [0.0, 0.45, 0.72],
              colors: [Colors.white, Colors.white, Colors.transparent],
            ).createShader(rect),
            blendMode: BlendMode.dstIn,
            child: ImageFiltered(
              imageFilter: ImageFilter.blur(sigmaX: 26, sigmaY: 26),
              child: Image.network(
                url!,
                fit: BoxFit.cover,
                errorBuilder: (_, _, _) =>
                    const ColoredBox(color: AppColors.surface0),
              ),
            ),
          ),
          // Topo dissolve em preto (e dá contraste para o botão voltar).
          const DecoratedBox(
            decoration: BoxDecoration(
              gradient: LinearGradient(
                begin: Alignment.topCenter,
                end: Alignment.bottomCenter,
                stops: [0.0, 0.28],
                colors: [AppColors.surface0, Colors.transparent],
              ),
            ),
          ),
          // Laterais (desktop): dissolvem as bordas retas do retângulo.
          if (desktop) ...[
            const DecoratedBox(
              decoration: BoxDecoration(
                gradient: LinearGradient(
                  begin: Alignment.centerLeft,
                  end: Alignment.centerRight,
                  stops: [0.0, 0.16],
                  colors: [AppColors.surface0, Colors.transparent],
                ),
              ),
            ),
            const DecoratedBox(
              decoration: BoxDecoration(
                gradient: LinearGradient(
                  begin: Alignment.centerRight,
                  end: Alignment.centerLeft,
                  stops: [0.0, 0.16],
                  colors: [AppColors.surface0, Colors.transparent],
                ),
              ),
            ),
          ],
        ],
      ),
    );
  }
}

// ─── Banners ───────────────────────────────────────────────────────────────

class _BannerFilme extends StatelessWidget {
  final String? url;
  const _BannerFilme({required this.url});

  @override
  Widget build(BuildContext context) {
    return _MolduraBanner(
      child: (url != null && url!.isNotEmpty)
          ? Image.network(
              url!,
              fit: BoxFit.cover,
              errorBuilder: (_, _, _) => const _BannerFallback(),
            )
          : const _BannerFallback(),
    );
  }
}

class _BannerSerie extends StatelessWidget {
  final Future<String?>? posterFuture;
  final String? logoM3U;

  const _BannerSerie({required this.posterFuture, required this.logoM3U});

  @override
  Widget build(BuildContext context) {
    return _MolduraBanner(
      child: FutureBuilder<String?>(
        future: posterFuture,
        builder: (context, snap) {
          final temLogoM3U = logoM3U != null && logoM3U!.isNotEmpty;
          final carregando = snap.connectionState != ConnectionState.done;

          // Ainda buscando o poster e sem logo da M3U -> skeleton.
          if (carregando && !temLogoM3U) {
            return const Shimmer(
              child: SkeletonBox(width: _kPosterW, height: _kPosterH),
            );
          }

          final url = (snap.data != null && snap.data!.isNotEmpty)
              ? snap.data
              : (temLogoM3U ? logoM3U : null);
          if (url == null) return const _BannerFallback();

          return Image.network(
            url,
            fit: BoxFit.cover,
            errorBuilder: (_, _, _) => const _BannerFallback(),
          );
        },
      ),
    );
  }
}

class _MolduraBanner extends StatelessWidget {
  final Widget child;
  const _MolduraBanner({required this.child});

  @override
  Widget build(BuildContext context) {
    return ClipRRect(
      borderRadius: BorderRadius.circular(AppRadius.base),
      child: ColoredBox(
        color: AppColors.surface2,
        child: SizedBox.expand(child: child),
      ),
    );
  }
}

class _BannerFallback extends StatelessWidget {
  const _BannerFallback();

  @override
  Widget build(BuildContext context) {
    return const ColoredBox(
      color: AppColors.surface2,
      child: Center(
        child: Icon(
          Icons.movie_creation_outlined,
          size: 36,
          color: AppColors.textTertiary,
        ),
      ),
    );
  }
}

// ─── Secoes (sinopse / elenco) ─────────────────────────────────────────────

class _SecaoSinopse extends StatelessWidget {
  final Future<TmdbInfo> infoFuture;
  final double padH;

  const _SecaoSinopse({required this.infoFuture, this.padH = AppSpacing.lg});

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _TituloSecao('Sinopse', padH: padH),
        Padding(
          padding: EdgeInsets.fromLTRB(padH, 0, padH, AppSpacing.base),
          child: FutureBuilder<TmdbInfo>(
            future: infoFuture,
            builder: (context, snap) {
              if (snap.connectionState != ConnectionState.done) {
                return const SkeletonLinhas(linhas: 4);
              }
              final sinopse = snap.data?.sinopse;
              if (sinopse == null) {
                return Text(
                  'Sinopse não disponível.',
                  style: Theme.of(context).textTheme.bodySmall?.copyWith(
                        color: AppColors.textTertiary,
                      ),
                );
              }
              return Text(
                sinopse,
                style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                      color: AppColors.textSecondary,
                      height: 1.5,
                    ),
              );
            },
          ),
        ),
      ],
    );
  }
}

class _SecaoElenco extends StatefulWidget {
  final Future<TmdbInfo> infoFuture;
  final double padH;

  const _SecaoElenco({required this.infoFuture, this.padH = AppSpacing.lg});

  @override
  State<_SecaoElenco> createState() => _SecaoElencoState();
}

class _SecaoElencoState extends State<_SecaoElenco> {
  static const double _altura = 118;
  // 3 cards (avatar 72 + separador 16) por clique.
  static const double _passo = (72 + AppSpacing.base) * 3;

  final _ctrl = ScrollController();
  bool _podeEsq = false;
  bool _podeDir = true;

  @override
  void initState() {
    super.initState();
    _ctrl.addListener(_atualizar);
    WidgetsBinding.instance.addPostFrameCallback((_) => _atualizar());
  }

  @override
  void dispose() {
    _ctrl.dispose();
    super.dispose();
  }

  void _atualizar() {
    if (!_ctrl.hasClients) return;
    final pos = _ctrl.position;
    final e = pos.pixels > 0;
    final d = pos.pixels < pos.maxScrollExtent;
    if (e != _podeEsq || d != _podeDir) {
      setState(() {
        _podeEsq = e;
        _podeDir = d;
      });
    }
  }

  void _rolar(double delta) {
    if (!_ctrl.hasClients) return;
    final pos = _ctrl.position;
    _ctrl.animateTo(
      (pos.pixels + delta).clamp(pos.minScrollExtent, pos.maxScrollExtent),
      duration: const Duration(milliseconds: 220),
      curve: Curves.easeOutCubic,
    );
  }

  @override
  Widget build(BuildContext context) {
    final padH = widget.padH;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _TituloSecao('Elenco', padH: padH),
        FutureBuilder<TmdbInfo>(
          future: widget.infoFuture,
          builder: (context, snap) {
            if (snap.connectionState != ConnectionState.done) {
              return SizedBox(
                height: _altura,
                child: Shimmer(
                  child: ListView.separated(
                    scrollDirection: Axis.horizontal,
                    padding: EdgeInsets.fromLTRB(padH, 0, padH, AppSpacing.base),
                    itemCount: 5,
                    separatorBuilder: (_, _) =>
                        const SizedBox(width: AppSpacing.base),
                    itemBuilder: (_, _) => const _CardAtorSkeleton(),
                  ),
                ),
              );
            }
            final elenco = snap.data?.elenco ?? const <AtorTmdb>[];
            if (elenco.isEmpty) {
              return Padding(
                padding: EdgeInsets.fromLTRB(padH, 0, padH, AppSpacing.base),
                child: Text(
                  'Elenco não disponível.',
                  style: Theme.of(context).textTheme.bodySmall?.copyWith(
                        color: AppColors.textTertiary,
                      ),
                ),
              );
            }
            return SizedBox(
              height: _altura,
              child: Stack(
                children: [
                  ListView.separated(
                    controller: _ctrl,
                    scrollDirection: Axis.horizontal,
                    padding:
                        EdgeInsets.fromLTRB(padH, 0, padH, AppSpacing.base),
                    itemCount: elenco.length,
                    separatorBuilder: (_, _) =>
                        const SizedBox(width: AppSpacing.base),
                    itemBuilder: (_, i) => _CardAtor(ator: elenco[i]),
                  ),
                  // Setas discretas — só desktop, alinhadas ao avatar.
                  if (isDesktop(context) && _podeEsq)
                    Positioned(
                      left: AppSpacing.sm,
                      top: 0,
                      height: _kAvatarElenco,
                      child: Center(
                        child: _SetaElenco(
                          icone: Icons.chevron_left_rounded,
                          onTap: () => _rolar(-_passo),
                        ),
                      ),
                    ),
                  if (isDesktop(context) && _podeDir)
                    Positioned(
                      right: AppSpacing.sm,
                      top: 0,
                      height: _kAvatarElenco,
                      child: Center(
                        child: _SetaElenco(
                          icone: Icons.chevron_right_rounded,
                          onTap: () => _rolar(_passo),
                        ),
                      ),
                    ),
                ],
              ),
            );
          },
        ),
      ],
    );
  }
}

class _SetaElenco extends StatelessWidget {
  final IconData icone;
  final VoidCallback onTap;
  const _SetaElenco({required this.icone, required this.onTap});

  @override
  Widget build(BuildContext context) {
    return Material(
      color: AppColors.surface2.withValues(alpha: 0.92),
      shape: const CircleBorder(),
      child: InkWell(
        onTap: onTap,
        customBorder: const CircleBorder(),
        child: SizedBox(
          width: 28,
          height: 28,
          child: Icon(icone, size: 18, color: AppColors.textSecondary),
        ),
      ),
    );
  }
}

// ─── Filmes relacionados ───────────────────────────────────────────────────

class _SecaoRelacionados extends StatefulWidget {
  final Future<List<Canal>> future;
  final String escopo;
  final double padH;

  const _SecaoRelacionados({
    required this.future,
    required this.escopo,
    this.padH = AppSpacing.lg,
  });

  @override
  State<_SecaoRelacionados> createState() => _SecaoRelacionadosState();
}

class _SecaoRelacionadosState extends State<_SecaoRelacionados> {
  static const double _cardW = 108;
  static const double _cardH = _cardW * 1.5; // pôster 2:3
  static const double _altura = _cardH + AppSpacing.base;
  static const double _passo = (_cardW + AppSpacing.sm) * 3;

  final _ctrl = ScrollController();
  bool _podeEsq = false;
  bool _podeDir = true;

  @override
  void initState() {
    super.initState();
    _ctrl.addListener(_atualizar);
    WidgetsBinding.instance.addPostFrameCallback((_) => _atualizar());
  }

  @override
  void dispose() {
    _ctrl.dispose();
    super.dispose();
  }

  void _atualizar() {
    if (!_ctrl.hasClients) return;
    final pos = _ctrl.position;
    final e = pos.pixels > 0;
    final d = pos.pixels < pos.maxScrollExtent;
    if (e != _podeEsq || d != _podeDir) {
      setState(() {
        _podeEsq = e;
        _podeDir = d;
      });
    }
  }

  void _rolar(double delta) {
    if (!_ctrl.hasClients) return;
    final pos = _ctrl.position;
    _ctrl.animateTo(
      (pos.pixels + delta).clamp(pos.minScrollExtent, pos.maxScrollExtent),
      duration: const Duration(milliseconds: 220),
      curve: Curves.easeOutCubic,
    );
  }

  @override
  Widget build(BuildContext context) {
    final padH = widget.padH;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        FutureBuilder<List<Canal>>(
          future: widget.future,
          builder: (context, snap) {
            if (snap.connectionState != ConnectionState.done) {
              // Skeleton: a tela abre na hora; aqui mostra "carregando".
              return Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  _TituloSecao('Relacionados', padH: padH),
                  SizedBox(
                    height: _altura,
                    child: Shimmer(
                      child: ListView.separated(
                        scrollDirection: Axis.horizontal,
                        padding: EdgeInsets.fromLTRB(
                            padH, 0, padH, AppSpacing.base),
                        itemCount: 6,
                        separatorBuilder: (_, _) =>
                            const SizedBox(width: AppSpacing.sm),
                        itemBuilder: (_, _) =>
                            const SkeletonBox(width: _cardW, height: _cardH),
                      ),
                    ),
                  ),
                ],
              );
            }
            final filmes = snap.data ?? const <Canal>[];
            if (filmes.isEmpty) return const SizedBox.shrink();
            return Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                _TituloSecao('Relacionados', padH: padH),
                SizedBox(
                  height: _altura,
                  child: Stack(
                    children: [
                      ListView.separated(
                        controller: _ctrl,
                        scrollDirection: Axis.horizontal,
                        padding: EdgeInsets.fromLTRB(
                            padH, 0, padH, AppSpacing.base),
                        itemCount: filmes.length,
                        separatorBuilder: (_, _) =>
                            const SizedBox(width: AppSpacing.sm),
                        itemBuilder: (_, i) => _CardRelacionado(
                          filme: filmes[i],
                          escopo: widget.escopo,
                          width: _cardW,
                        ),
                      ),
                      if (isDesktop(context) && _podeEsq)
                        Positioned(
                          left: AppSpacing.sm,
                          top: 0,
                          bottom: AppSpacing.base,
                          child: Center(
                            child: _SetaElenco(
                              icone: Icons.chevron_left_rounded,
                              onTap: () => _rolar(-_passo),
                            ),
                          ),
                        ),
                      if (isDesktop(context) && _podeDir)
                        Positioned(
                          right: AppSpacing.sm,
                          top: 0,
                          bottom: AppSpacing.base,
                          child: Center(
                            child: _SetaElenco(
                              icone: Icons.chevron_right_rounded,
                              onTap: () => _rolar(_passo),
                            ),
                          ),
                        ),
                    ],
                  ),
                ),
              ],
            );
          },
        ),
      ],
    );
  }
}

class _CardRelacionado extends StatelessWidget {
  final Canal filme;
  final String escopo;
  final double width;

  const _CardRelacionado({
    required this.filme,
    required this.escopo,
    required this.width,
  });

  @override
  Widget build(BuildContext context) {
    final tag = 'hero-$escopo-${filme.url}';
    final temLogo = filme.logoUrl != null && filme.logoUrl!.isNotEmpty;
    return SizedBox(
      width: width,
      child: Material(
        color: AppColors.surface2,
        borderRadius: BorderRadius.circular(AppRadius.sm),
        clipBehavior: Clip.antiAlias,
        child: InkWell(
          onTap: () => Navigator.of(context).push(
            MaterialPageRoute(
              builder: (_) => TelaDetalhes.filme(filme, heroTag: tag),
            ),
          ),
          child: Hero(
            tag: tag,
            createRectTween: (b, e) => RectTween(begin: b, end: e),
            child: ClipRRect(
              borderRadius: BorderRadius.circular(AppRadius.sm),
              child: temLogo
                  ? Image.network(
                      filme.logoUrl!,
                      fit: BoxFit.cover,
                      errorBuilder: (_, _, _) => const _BannerFallback(),
                    )
                  : const _BannerFallback(),
            ),
          ),
        ),
      ),
    );
  }
}

const double _kAvatarElenco = 64;

class _CardAtor extends StatelessWidget {
  final AtorTmdb ator;
  const _CardAtor({required this.ator});

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      width: 72,
      child: Column(
        children: [
          ClipOval(
            child: SizedBox(
              width: _kAvatarElenco,
              height: _kAvatarElenco,
              child: (ator.fotoUrl != null)
                  ? Image.network(
                      ator.fotoUrl!,
                      fit: BoxFit.cover,
                      errorBuilder: (_, _, _) => const _AvatarVazio(),
                      loadingBuilder: (_, child, p) =>
                          p == null ? child : const _AvatarVazio(),
                    )
                  : const _AvatarVazio(),
            ),
          ),
          const SizedBox(height: 6),
          Expanded(
            child: Text(
              ator.nome,
              textAlign: TextAlign.center,
              maxLines: 2,
              overflow: TextOverflow.ellipsis,
              style: Theme.of(context).textTheme.labelSmall?.copyWith(
                    color: AppColors.textPrimary,
                    height: 1.15,
                  ),
            ),
          ),
        ],
      ),
    );
  }
}

class _AvatarVazio extends StatelessWidget {
  const _AvatarVazio();

  @override
  Widget build(BuildContext context) {
    return const ColoredBox(
      color: AppColors.surface2,
      child: Center(
        child: Icon(
          Icons.person_rounded,
          color: AppColors.textTertiary,
          size: 30,
        ),
      ),
    );
  }
}

class _CardAtorSkeleton extends StatelessWidget {
  const _CardAtorSkeleton();

  @override
  Widget build(BuildContext context) {
    return const SizedBox(
      width: 72,
      child: Column(
        children: [
          ClipOval(
            child: SkeletonBox(
              width: _kAvatarElenco,
              height: _kAvatarElenco,
            ),
          ),
          SizedBox(height: 6),
          SkeletonBox(width: 56, height: 10),
        ],
      ),
    );
  }
}

// ─── Seletor de temporada (estilo Prime Video) ────────────────────────────

class _SeletorTemporada extends StatelessWidget {
  final List<int> temporadas;
  final int selecionada;
  final ValueChanged<int> onSelecionada;
  final double padH;
  final bool desktop;

  const _SeletorTemporada({
    required this.temporadas,
    required this.selecionada,
    required this.onSelecionada,
    this.padH = AppSpacing.lg,
    this.desktop = false,
  });

  static String _rotulo(int t) => t == 0 ? 'Especiais' : 'Temporada $t';

  /// Altura aproximada de um ListTile — usada só para abrir a lista já na
  /// temporada atual quando a série tem muitas (One Piece tem 23).
  static const _alturaItem = 56.0;

  void _abrirPicker(BuildContext context) {
    final iSel = temporadas.indexOf(selecionada);
    final altura = MediaQuery.sizeOf(context).height;
    // Sem `isScrollControlled` a folha nunca passa de metade da tela, e o
    // Column interno NÃO rolava: numa série com muitas temporadas a lista era
    // cortada e não havia como chegar nas últimas.
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: AppColors.surface2,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(AppRadius.lg)),
      ),
      builder: (_) => SafeArea(
        child: ConstrainedBox(
          // Deixa uma faixa do conteúdo à mostra (dá o "toque fora p/ fechar")
          // e ainda assim cabe muita temporada.
          constraints: BoxConstraints(maxHeight: altura * 0.75),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Container(
                width: 36,
                height: 4,
                margin: const EdgeInsets.symmetric(vertical: AppSpacing.base),
                decoration: BoxDecoration(
                  color: AppColors.outlineSubtle,
                  borderRadius: BorderRadius.circular(AppRadius.pill),
                ),
              ),
              Flexible(
                child: ListView.builder(
                  shrinkWrap: true,
                  padding: const EdgeInsets.only(bottom: AppSpacing.sm),
                  // Abre já mostrando a temporada atual, não a primeira.
                  controller: ScrollController(
                    initialScrollOffset:
                        iSel <= 2 ? 0 : (iSel - 2) * _alturaItem,
                  ),
                  itemCount: temporadas.length,
                  itemBuilder: (_, i) {
                    final t = temporadas[i];
                    return ListTile(
                      title: Text(_rotulo(t)),
                      trailing: t == selecionada
                          ? const Icon(Icons.check_rounded,
                              color: AppColors.accent)
                          : null,
                      selected: t == selecionada,
                      selectedColor: AppColors.textPrimary,
                      onTap: () {
                        Navigator.pop(context);
                        onSelecionada(t);
                      },
                    );
                  },
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final temVarias = temporadas.length > 1;
    final labelStyle = desktop
        ? Theme.of(context).textTheme.labelMedium?.copyWith(
              color: AppColors.textTertiary,
              letterSpacing: 0.8,
            )
        : Theme.of(context).textTheme.labelSmall?.copyWith(
              color: AppColors.textTertiary,
              letterSpacing: 0.6,
            );
    final botaoStyle = desktop
        ? Theme.of(context).textTheme.bodyMedium?.copyWith(
              color: AppColors.accent,
              fontWeight: FontWeight.w600,
            )
        : Theme.of(context).textTheme.bodySmall?.copyWith(
              color: AppColors.accent,
              fontWeight: FontWeight.w600,
            );
    final botaoPadding = desktop
        ? const EdgeInsets.symmetric(horizontal: AppSpacing.md, vertical: AppSpacing.sm)
        : const EdgeInsets.symmetric(horizontal: AppSpacing.sm, vertical: AppSpacing.xs);
    final iconSize = desktop ? 22.0 : 18.0;

    return Padding(
      padding: EdgeInsets.fromLTRB(padH, AppSpacing.base, padH, AppSpacing.xs),
      child: Row(
        children: [
          Expanded(
            child: Text('EPISÓDIOS', style: labelStyle),
          ),
          if (temVarias)
            InkWell(
              onTap: () => _abrirPicker(context),
              borderRadius: BorderRadius.circular(AppRadius.sm),
              child: Padding(
                padding: botaoPadding,
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Text(_rotulo(selecionada), style: botaoStyle),
                    const SizedBox(width: 2),
                    Icon(
                      Icons.keyboard_arrow_down_rounded,
                      size: iconSize,
                      color: AppColors.accent,
                    ),
                  ],
                ),
              ),
            )
          else
            Text(
              _rotulo(selecionada),
              style: desktop
                  ? Theme.of(context).textTheme.bodyMedium?.copyWith(
                        color: AppColors.textTertiary,
                      )
                  : Theme.of(context).textTheme.bodySmall?.copyWith(
                        color: AppColors.textTertiary,
                      ),
            ),
        ],
      ),
    );
  }
}

// ─── Episodios da serie ────────────────────────────────────────────────────

class _ItemEpisodio extends StatelessWidget {
  final Canal episodio;
  final List<Canal> episodiosSerie;
  final double padH;
  final bool desktop;

  const _ItemEpisodio({
    required this.episodio,
    required this.episodiosSerie,
    this.padH = AppSpacing.lg,
    this.desktop = false,
  });

  @override
  Widget build(BuildContext context) {
    final provider = context.watch<IptvProvider>();
    final progresso = provider.obterProgresso(episodio);
    return InkWell(
      onTap: () {
        provider.registrarVisualizacao(episodio);
        Navigator.of(context).push(
          MaterialPageRoute(
            builder: (_) => TelaPlayer(
              canal: episodio,
              episodiosSerie: episodiosSerie,
              posicaoInicial: progresso != null
                  ? Duration(seconds: progresso.posicaoSeg)
                  : null,
            ),
          ),
        );
      },
      child: Padding(
        padding: EdgeInsets.symmetric(
          horizontal: padH,
          vertical: desktop ? AppSpacing.base : AppSpacing.sm,
        ),
        child: Row(
          children: [
            ClipRRect(
              borderRadius: BorderRadius.circular(AppRadius.sm),
              child: SizedBox(
                width: desktop ? 120 : 80,
                height: desktop ? 69 : 46,
                child: Stack(
                  fit: StackFit.expand,
                  children: [
                    _MiniaturaEpisodio(logoUrl: episodio.logoUrl),
                    if (progresso != null && progresso.fracao > 0)
                      Positioned(
                        bottom: 0,
                        left: 0,
                        right: 0,
                        child: LinearProgressIndicator(
                          value: progresso.fracao,
                          minHeight: 3,
                          backgroundColor: Colors.white24,
                          valueColor: const AlwaysStoppedAnimation(
                            AppColors.accent,
                          ),
                        ),
                      ),
                  ],
                ),
              ),
            ),
            const SizedBox(width: AppSpacing.base),
            Expanded(
              child: Text(
                Serie.episodeLabel(episodio),
                style: desktop
                    ? Theme.of(context).textTheme.bodyLarge
                    : Theme.of(context).textTheme.bodyMedium,
                maxLines: 2,
                overflow: TextOverflow.ellipsis,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// Miniatura do episodio: usa o logo/banner que vem da lista M3U.
/// Cai no icone de play se nao houver imagem ou se o download falhar.
class _MiniaturaEpisodio extends StatelessWidget {
  final String? logoUrl;
  const _MiniaturaEpisodio({required this.logoUrl});

  @override
  Widget build(BuildContext context) {
    if (logoUrl == null || logoUrl!.isEmpty) return const _MiniaturaVazia();
    return Image.network(
      logoUrl!,
      fit: BoxFit.cover,
      errorBuilder: (_, _, _) => const _MiniaturaVazia(),
      loadingBuilder: (_, child, progress) =>
          progress == null ? child : const _MiniaturaVazia(),
    );
  }
}

class _MiniaturaVazia extends StatelessWidget {
  const _MiniaturaVazia();

  @override
  Widget build(BuildContext context) {
    return const ColoredBox(
      color: AppColors.surface2,
      child: Center(
        child: Icon(
          Icons.play_circle_outline_rounded,
          color: AppColors.textTertiary,
          size: 22,
        ),
      ),
    );
  }
}

// ─── Auxiliares ────────────────────────────────────────────────────────────

class _TituloSecao extends StatelessWidget {
  final String texto;
  final double padH;

  const _TituloSecao(this.texto, {this.padH = AppSpacing.lg});

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: EdgeInsets.fromLTRB(padH, AppSpacing.base, padH, AppSpacing.sm),
      child: Text(
        texto.toUpperCase(),
        style: Theme.of(context).textTheme.labelSmall?.copyWith(
              color: AppColors.textTertiary,
              letterSpacing: 0.6,
            ),
      ),
    );
  }
}

class _Divisoria extends StatelessWidget {
  const _Divisoria();

  @override
  Widget build(BuildContext context) {
    return const Padding(
      padding: EdgeInsets.symmetric(horizontal: AppSpacing.lg),
      child: Divider(height: 1),
    );
  }
}
