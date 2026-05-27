import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:marquee/marquee.dart';
import 'package:provider/provider.dart';
import '../models/canal.dart';
import '../models/progresso_canal.dart';
import '../models/serie.dart';
import '../services/tmdb_service.dart';
import '../state/iptv_provider.dart';
import '../theme/app_theme.dart';
import '../utils/layout.dart';
import 'tela_detalhes.dart';

enum TipoVod { filmes, series }

const double _kScrollStep = (_kPosterWidth + AppSpacing.sm) * 3;

// Top-level: roda em Isolate separado via compute() para nao bloquear a UI.
({
  Map<String, List<Object>> conteudo,
  List<String> nomes,
  List<Object> todosConteudos,
}) _computarConteudoVod((Map<String, List<Canal>>, TipoVod) args) {
  final (categorias, tipo) = args;
  final conteudo = <String, List<Object>>{};
  final visto = <String>{};
  final todos = <Object>[];

  String nomeItem(Object item) =>
      item is Canal ? item.nome : (item as Serie).nome;

  for (final cat in categorias.keys) {
    final ag = Serie.agrupar(categorias[cat]!);
    final items = tipo == TipoVod.filmes ? ag.filmes : ag.series;
    if (items.isEmpty) continue;
    final lista = <Object>[...items]
      ..sort((a, b) => nomeItem(a).compareTo(nomeItem(b)));
    conteudo[cat] = lista;

    for (final item in lista) {
      final key =
          item is Canal ? 'c:${item.url}' : 's:${(item as Serie).nome}';
      if (visto.add(key)) todos.add(item);
    }
  }

  return (
    conteudo: conteudo,
    nomes: conteudo.keys.toList()..sort(),
    todosConteudos: todos,
  );
}

const double _kPosterWidth = 100.0;
const double _kPosterHeight = 150.0;
const double _kPosterLabel = 28.0;
const double _kItemExtent = _kPosterWidth + AppSpacing.sm;

/// Tela estilo streaming: carrosseis por categoria — filmes ou séries.
class TelaFilmes extends StatefulWidget {
  final Map<String, List<Canal>> categorias;
  final TipoVod tipo;
  const TelaFilmes({super.key, required this.categorias, this.tipo = TipoVod.filmes});

  @override
  State<TelaFilmes> createState() => _TelaFilmesState();
}

class _TelaFilmesState extends State<TelaFilmes> {
  final _buscaController = TextEditingController();
  bool _buscando = false;
  String _busca = '';

  bool _pronto = false;
  Map<String, List<Object>> _conteudo = const {};
  List<String> _nomes = const [];
  List<Object> _todosConteudos = const [];
  // Lookup rápido url→Canal (inclui episódios de series)
  Map<String, Canal> _canaisPorUrl = const {};
  // Lookup url-do-episódio → Serie a que ele pertence
  Map<String, Serie> _seriesPorUrlEpisodio = const {};

  @override
  void initState() {
    super.initState();
    compute(_computarConteudoVod, (widget.categorias, widget.tipo)).then((r) {
      if (!mounted) return;
      final lookup = <String, Canal>{};
      final seriesPorEp = <String, Serie>{};
      for (final item in r.todosConteudos) {
        if (item is Canal) {
          lookup[item.url] = item;
        } else {
          final serie = item as Serie;
          for (final ep in serie.episodios) {
            lookup[ep.url] = ep;
            seriesPorEp[ep.url] = serie;
          }
        }
      }
      setState(() {
        _conteudo = r.conteudo;
        _nomes = r.nomes;
        _todosConteudos = r.todosConteudos;
        _canaisPorUrl = lookup;
        _seriesPorUrlEpisodio = seriesPorEp;
        _pronto = true;
      });
    });
  }

  @override
  void dispose() {
    _buscaController.dispose();
    super.dispose();
  }

  List<Object> _filtrar(String busca) {
    final q = busca.toLowerCase();
    return _todosConteudos.where((item) {
      if (item is Canal) {
        return item.nome.toLowerCase().contains(q) ||
            item.grupo.toLowerCase().contains(q);
      }
      final s = item as Serie;
      return s.nome.toLowerCase().contains(q) ||
          s.grupo.toLowerCase().contains(q);
    }).toList();
  }

  void _navegar(BuildContext context, Object item) {
    // Filme ou série: sempre abre a tela de detalhes.
    Navigator.of(context).push(
      MaterialPageRoute(
        builder: (_) => item is Canal
            ? TelaDetalhes.filme(item)
            : TelaDetalhes.serie(item as Serie),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    if (!_pronto) {
      return Scaffold(
        appBar: AppBar(title: Text(widget.tipo == TipoVod.filmes ? 'Filmes' : 'Séries')),
        body: const Center(child: CircularProgressIndicator()),
      );
    }

    return PopScope(
      canPop: !_buscando,
      onPopInvokedWithResult: (didPop, _) {
        if (!didPop) {
          setState(() {
            _buscando = false;
            _buscaController.clear();
            _busca = '';
          });
        }
      },
      child: Scaffold(
      appBar: AppBar(
        titleSpacing: 0,
        title: _buscando
            ? Padding(
                padding: const EdgeInsets.only(right: AppSpacing.sm),
                child: TextField(
                  controller: _buscaController,
                  autofocus: true,
                  decoration: InputDecoration(
                    hintText: widget.tipo == TipoVod.filmes
                        ? 'Buscar filmes'
                        : 'Buscar séries',
                    border: InputBorder.none,
                    enabledBorder: InputBorder.none,
                    focusedBorder: InputBorder.none,
                    filled: false,
                    contentPadding: EdgeInsets.zero,
                  ),
                  style: Theme.of(context).textTheme.bodyLarge,
                  onChanged: (v) => setState(() => _busca = v),
                ),
              )
            : Text(widget.tipo == TipoVod.filmes ? 'Filmes' : 'Séries'),
        actions: [
          IconButton(
            icon: Icon(
              _buscando ? Icons.close_rounded : Icons.search_rounded,
              size: 22,
            ),
            onPressed: () {
              setState(() {
                _buscando = !_buscando;
                if (!_buscando) {
                  _buscaController.clear();
                  _busca = '';
                }
              });
            },
          ),
        ],
      ),
      body: _buscando && _busca.isNotEmpty
          ? _GradeResultados(
              itens: _filtrar(_busca),
              onTap: (item) => _navegar(context, item),
            )
          : _conteudo.isEmpty
              ? _Vazio(tipo: widget.tipo)
              : _BodyComCarrosseis(
                  nomes: _nomes,
                  conteudo: _conteudo,
                  canaisPorUrl: _canaisPorUrl,
                  seriesPorUrlEpisodio: _seriesPorUrlEpisodio,
                  progressos: context.watch<IptvProvider>().progressos,
                  onTap: (item) => _navegar(context, item),
                ),
      ),
    );
  }
}

class _Vazio extends StatelessWidget {
  final TipoVod tipo;
  const _Vazio({required this.tipo});

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(AppSpacing.xxl),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(
              tipo == TipoVod.filmes
                  ? Icons.movie_creation_outlined
                  : Icons.tv_rounded,
              size: 36,
              color: AppColors.textTertiary,
            ),
            const SizedBox(height: AppSpacing.base),
            Text(
              tipo == TipoVod.filmes
                  ? 'Sem filmes nesta lista'
                  : 'Sem séries nesta lista',
              style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                    color: AppColors.textSecondary,
                  ),
              textAlign: TextAlign.center,
            ),
          ],
        ),
      ),
    );
  }
}

// Corpo principal: carrossel "Continuar assistindo" + carrosseis por categoria.
class _BodyComCarrosseis extends StatelessWidget {
  final List<String> nomes;
  final Map<String, List<Object>> conteudo;
  final Map<String, Canal> canaisPorUrl;
  final Map<String, Serie> seriesPorUrlEpisodio;
  final List<ProgressoCanal> progressos;
  final void Function(Object) onTap;

  const _BodyComCarrosseis({
    required this.nomes,
    required this.conteudo,
    required this.canaisPorUrl,
    required this.seriesPorUrlEpisodio,
    required this.progressos,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    // Monta o "Continuar assistindo": filmes entram como o próprio Canal
    // (retomam direto no player); episódios de série entram como o objeto
    // Serie — abrem a tela de detalhes, onde já aparece "Continuar T1:E2".
    // Cada série aparece uma única vez (o progresso mais recente vence).
    final continuar = <_ItemContinuar>[];
    final seriesVistas = <String>{};
    for (final p in progressos) {
      final canal = canaisPorUrl[p.url];
      if (canal == null) continue;
      final serie = seriesPorUrlEpisodio[p.url];
      if (serie != null) {
        if (seriesVistas.add(serie.nome)) {
          continuar.add(_ItemContinuar.serie(serie));
        }
      } else {
        continuar.add(_ItemContinuar.filme(canal, p));
      }
    }

    final temAndamento = continuar.isNotEmpty;
    final total = nomes.length + (temAndamento ? 1 : 0);

    return ListView.builder(
      padding: const EdgeInsets.only(
        top: AppSpacing.sm,
        bottom: AppSpacing.xxl,
      ),
      itemCount: total,
      itemBuilder: (_, i) {
        if (temAndamento && i == 0) {
          return _CarrosselContinuar(itens: continuar, onTap: onTap);
        }
        final idx = temAndamento ? i - 1 : i;
        final nome = nomes[idx];
        return _CarrosselCategoria(
          nomeCategoria: nome,
          itens: conteudo[nome]!,
          onTap: (item) => onTap(item),
        );
      },
    );
  }
}

/// Um item do carrossel "Continuar assistindo": ou um filme (com seu
/// progresso, para retomar direto no player), ou uma série (abre a tela
/// de detalhes).
class _ItemContinuar {
  final Serie? serie;
  final Canal? filme;
  final ProgressoCanal? progresso;

  const _ItemContinuar.serie(Serie this.serie)
      : filme = null,
        progresso = null;
  const _ItemContinuar.filme(Canal this.filme, ProgressoCanal this.progresso)
      : serie = null;
}

class _CarrosselContinuar extends StatefulWidget {
  final List<_ItemContinuar> itens;
  final void Function(Object) onTap;

  const _CarrosselContinuar({required this.itens, required this.onTap});

  @override
  State<_CarrosselContinuar> createState() => _CarrosselContinuarState();
}

class _CarrosselContinuarState extends State<_CarrosselContinuar> {
  final _ctrl = ScrollController();

  @override
  void dispose() {
    _ctrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(
            AppSpacing.lg,
            AppSpacing.lg,
            AppSpacing.lg,
            AppSpacing.sm,
          ),
          child: Row(
            children: [
              const Icon(
                Icons.play_circle_outline_rounded,
                size: 16,
                color: AppColors.accent,
              ),
              const SizedBox(width: AppSpacing.xs),
              Text(
                'Continuar assistindo',
                style: Theme.of(context).textTheme.titleSmall,
              ),
            ],
          ),
        ),
        _CarrosselComBotoes(
          ctrl: _ctrl,
          height: _kPosterHeight + _kPosterLabel,
          child: ListView.builder(
            controller: _ctrl,
            scrollDirection: Axis.horizontal,
            padding: const EdgeInsets.symmetric(horizontal: AppSpacing.lg),
            itemCount: widget.itens.length,
            itemExtent: _kItemExtent,
            itemBuilder: (_, i) {
              final item = widget.itens[i];
              final serie = item.serie;
              if (serie != null) {
                return _PosterSerie(
                  key: ValueKey('cont:${serie.nome}'),
                  serie: serie,
                  onTap: () => widget.onTap(serie),
                );
              }
              final filme = item.filme!;
              return _Poster(
                canal: filme,
                progresso: item.progresso,
                onTap: () => widget.onTap(filme),
              );
            },
          ),
        ),
      ],
    );
  }
}

class _CarrosselCategoria extends StatefulWidget {
  final String nomeCategoria;
  final List<Object> itens;
  final void Function(Object) onTap;

  const _CarrosselCategoria({
    required this.nomeCategoria,
    required this.itens,
    required this.onTap,
  });

  @override
  State<_CarrosselCategoria> createState() => _CarrosselCategoriaState();
}

class _CarrosselCategoriaState extends State<_CarrosselCategoria> {
  final _ctrl = ScrollController();

  @override
  void dispose() {
    _ctrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        InkWell(
          onTap: () => Navigator.of(context).push(
            MaterialPageRoute(
              builder: (_) => _TelaCategoriaFilmes(
                nomeCategoria: widget.nomeCategoria,
                itens: widget.itens,
              ),
            ),
          ),
          child: Padding(
            padding: const EdgeInsets.fromLTRB(
              AppSpacing.lg,
              AppSpacing.lg,
              AppSpacing.lg,
              AppSpacing.sm,
            ),
            child: Row(
              children: [
                Expanded(
                  child: Text(
                    widget.nomeCategoria,
                    style: Theme.of(context).textTheme.titleSmall,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
                ),
                Text(
                  '${widget.itens.length}',
                  style: tabular(
                    Theme.of(context).textTheme.labelSmall?.copyWith(
                          color: AppColors.textTertiary,
                        ),
                  ),
                ),
                const SizedBox(width: AppSpacing.xs),
                const Icon(
                  Icons.chevron_right_rounded,
                  size: 16,
                  color: AppColors.textTertiary,
                ),
              ],
            ),
          ),
        ),
        _CarrosselComBotoes(
          ctrl: _ctrl,
          height: _kPosterHeight + _kPosterLabel,
          child: ListView.builder(
            controller: _ctrl,
            scrollDirection: Axis.horizontal,
            padding: const EdgeInsets.symmetric(horizontal: AppSpacing.lg),
            itemCount: widget.itens.length,
            itemExtent: _kItemExtent,
            itemBuilder: (_, i) => _CardConteudo(
              item: widget.itens[i],
              onTap: () => widget.onTap(widget.itens[i]),
            ),
          ),
        ),
      ],
    );
  }
}

// ─── Wrapper com botoes discretos de navegacao (desktop only) ─────────────────

class _CarrosselComBotoes extends StatefulWidget {
  final ScrollController ctrl;
  final double height;
  final Widget child;

  const _CarrosselComBotoes({
    required this.ctrl,
    required this.height,
    required this.child,
  });

  @override
  State<_CarrosselComBotoes> createState() => _CarrosselComBotoesState();
}

class _CarrosselComBotoesState extends State<_CarrosselComBotoes> {
  bool _podeEsquerda = false;
  bool _podeDireita = true;

  @override
  void initState() {
    super.initState();
    widget.ctrl.addListener(_atualizar);
    // Checa apos o layout, quando maxScrollExtent esta disponivel.
    WidgetsBinding.instance.addPostFrameCallback((_) => _atualizar());
  }

  @override
  void dispose() {
    widget.ctrl.removeListener(_atualizar);
    super.dispose();
  }

  void _atualizar() {
    if (!widget.ctrl.hasClients) return;
    final pos = widget.ctrl.position;
    final esq = pos.pixels > 0;
    final dir = pos.pixels < pos.maxScrollExtent;
    if (esq != _podeEsquerda || dir != _podeDireita) {
      setState(() {
        _podeEsquerda = esq;
        _podeDireita = dir;
      });
    }
  }

  void _rolar(double delta) {
    if (!widget.ctrl.hasClients) return;
    final pos = widget.ctrl.position;
    widget.ctrl.animateTo(
      (pos.pixels + delta).clamp(pos.minScrollExtent, pos.maxScrollExtent),
      duration: const Duration(milliseconds: 220),
      curve: Curves.easeOutCubic,
    );
  }

  @override
  Widget build(BuildContext context) {
    if (!isDesktop(context)) {
      return SizedBox(height: widget.height, child: widget.child);
    }
    return SizedBox(
      height: widget.height,
      child: Stack(
        children: [
          widget.child,
          if (_podeEsquerda)
            Positioned(
              left: AppSpacing.sm,
              top: 0,
              bottom: 0,
              child: Center(
                child: _BotaoNavCarrossel(
                  icone: Icons.chevron_left_rounded,
                  onTap: () => _rolar(-_kScrollStep),
                ),
              ),
            ),
          if (_podeDireita)
            Positioned(
              right: AppSpacing.sm,
              top: 0,
              bottom: 0,
              child: Center(
                child: _BotaoNavCarrossel(
                  icone: Icons.chevron_right_rounded,
                  onTap: () => _rolar(_kScrollStep),
                ),
              ),
            ),
        ],
      ),
    );
  }
}

class _BotaoNavCarrossel extends StatelessWidget {
  final IconData icone;
  final VoidCallback onTap;

  const _BotaoNavCarrossel({required this.icone, required this.onTap});

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

// ─── Cards de poster ──────────────────────────────────────────────────────────

class _CardConteudo extends StatelessWidget {
  final Object item;
  final VoidCallback onTap;
  const _CardConteudo({required this.item, required this.onTap});

  @override
  Widget build(BuildContext context) {
    if (item is Canal) return _Poster(canal: item as Canal, onTap: onTap);
    final serie = item as Serie;
    return _PosterSerie(key: ValueKey(serie.nome), serie: serie, onTap: onTap);
  }
}

class _Poster extends StatelessWidget {
  final Canal canal;
  final VoidCallback onTap;
  final ProgressoCanal? progresso;
  const _Poster({required this.canal, required this.onTap, this.progresso});

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(right: AppSpacing.sm),
      child: SizedBox(
        width: _kPosterWidth,
        child: Material(
          color: AppColors.surface1,
          borderRadius: BorderRadius.circular(AppRadius.sm),
          clipBehavior: Clip.antiAlias,
          child: InkWell(
            onTap: onTap,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Expanded(
                  child: Stack(
                    children: [
                      Positioned.fill(
                        child: canal.logoUrl != null &&
                                canal.logoUrl!.isNotEmpty
                            ? Image.network(
                                canal.logoUrl!,
                                fit: BoxFit.cover,
                                errorBuilder: (ctx, err, st) =>
                                    const _PosterFallback(serie: false),
                                loadingBuilder: (_, child, p) =>
                                    p == null
                                        ? child
                                        : const _PosterFallback(
                                            serie: false),
                              )
                            : const _PosterFallback(serie: false),
                      ),
                      if (progresso != null)
                        Positioned(
                          bottom: 0,
                          left: 0,
                          right: 0,
                          child: LinearProgressIndicator(
                            value: progresso!.fracao,
                            minHeight: 3,
                            backgroundColor: Colors.white24,
                            valueColor: const AlwaysStoppedAnimation(
                                AppColors.accent),
                          ),
                        ),
                    ],
                  ),
                ),
                SizedBox(
                  height: _kPosterLabel,
                  child: Padding(
                    padding: const EdgeInsets.symmetric(
                      horizontal: AppSpacing.xs,
                      vertical: AppSpacing.xs,
                    ),
                    child: Marquee(
                      text: canal.nome,
                      style: Theme.of(context).textTheme.labelSmall!,
                      scrollAxis: Axis.horizontal,
                      crossAxisAlignment: CrossAxisAlignment.center,
                      blankSpace: 32.0,
                      velocity: 30.0,
                      pauseAfterRound: const Duration(seconds: 3),
                      startAfter: const Duration(seconds: 2),
                      fadingEdgeStartFraction: 0.0,
                      fadingEdgeEndFraction: 0.12,
                    ),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _PosterSerie extends StatefulWidget {
  final Serie serie;
  final VoidCallback onTap;
  const _PosterSerie({super.key, required this.serie, required this.onTap});

  @override
  State<_PosterSerie> createState() => _PosterSerieState();
}

class _PosterSerieState extends State<_PosterSerie> {
  late final Future<String?> _tmdbFuture;

  @override
  void initState() {
    super.initState();
    _tmdbFuture =
        context.read<TmdbService>().posterSerie(widget.serie.nome);
  }

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(right: AppSpacing.sm),
      child: SizedBox(
        width: _kPosterWidth,
        child: Material(
          color: AppColors.surface1,
          borderRadius: BorderRadius.circular(AppRadius.sm),
          clipBehavior: Clip.antiAlias,
          child: InkWell(
            onTap: widget.onTap,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Expanded(
                  child: FutureBuilder<String?>(
                    future: _tmdbFuture,
                    builder: (context, snap) {
                      // Prioridade: TMDB > tvg-logo da M3U > fallback
                      final url = snap.data?.isNotEmpty == true
                          ? snap.data
                          : (widget.serie.logoUrl?.isNotEmpty == true
                              ? widget.serie.logoUrl
                              : null);
                      return Stack(
                        children: [
                          Positioned.fill(
                            child: url != null
                                ? Image.network(
                                    url,
                                    fit: BoxFit.cover,
                                    errorBuilder: (ctx, err, st) =>
                                        const _PosterFallback(serie: true),
                                    loadingBuilder: (_, child, progress) =>
                                        progress == null
                                            ? child
                                            : const _PosterFallback(
                                                serie: true),
                                  )
                                : const _PosterFallback(serie: true),
                          ),
                          // Badge "SÉRIE"
                          Positioned(
                            top: 4,
                            left: 4,
                            child: Container(
                              padding: const EdgeInsets.symmetric(
                                horizontal: 4,
                                vertical: 2,
                              ),
                              decoration: BoxDecoration(
                                color: AppColors.accentDim,
                                borderRadius: BorderRadius.circular(3),
                              ),
                              child: const Text(
                                'SÉRIE',
                                style: TextStyle(
                                  color: AppColors.accentBright,
                                  fontSize: 8,
                                  fontWeight: FontWeight.w700,
                                  letterSpacing: 0.4,
                                ),
                              ),
                            ),
                          ),
                          // Contagem de episodios
                          Positioned(
                            bottom: 4,
                            right: 4,
                            child: Container(
                              padding: const EdgeInsets.symmetric(
                                horizontal: 4,
                                vertical: 2,
                              ),
                              decoration: BoxDecoration(
                                color: Colors.black54,
                                borderRadius: BorderRadius.circular(3),
                              ),
                              child: Text(
                                '${widget.serie.totalEpisodios} ep',
                                style: tabular(
                                  const TextStyle(
                                    color: Colors.white,
                                    fontSize: 9,
                                    fontWeight: FontWeight.w600,
                                  ),
                                ),
                              ),
                            ),
                          ),
                        ],
                      );
                    },
                  ),
                ),
                SizedBox(
                  height: _kPosterLabel,
                  child: Padding(
                    padding: const EdgeInsets.symmetric(
                      horizontal: AppSpacing.xs,
                      vertical: AppSpacing.xs,
                    ),
                    child: Marquee(
                      text: widget.serie.nome,
                      style: Theme.of(context).textTheme.labelSmall!,
                      scrollAxis: Axis.horizontal,
                      crossAxisAlignment: CrossAxisAlignment.center,
                      blankSpace: 32.0,
                      velocity: 30.0,
                      pauseAfterRound: const Duration(seconds: 3),
                      startAfter: const Duration(seconds: 2),
                      fadingEdgeStartFraction: 0.0,
                      fadingEdgeEndFraction: 0.12,
                    ),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _PosterFallback extends StatelessWidget {
  final bool serie;
  const _PosterFallback({required this.serie});

  @override
  Widget build(BuildContext context) {
    return ColoredBox(
      color: AppColors.surface2,
      child: Center(
        child: Icon(
          serie ? Icons.tv_rounded : Icons.movie_creation_outlined,
          size: 32,
          color: AppColors.textTertiary,
        ),
      ),
    );
  }
}

// ─── Grade de resultados de busca ────────────────────────────────────────────

class _GradeResultados extends StatelessWidget {
  final List<Object> itens;
  final void Function(Object) onTap;

  const _GradeResultados({required this.itens, required this.onTap});

  @override
  Widget build(BuildContext context) {
    if (itens.isEmpty) {
      return Center(
        child: Text(
          'Nenhum resultado encontrado',
          style: Theme.of(context)
              .textTheme
              .bodyMedium
              ?.copyWith(color: AppColors.textSecondary),
        ),
      );
    }

    return GridView.builder(
      padding: const EdgeInsets.all(AppSpacing.base),
      gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
        crossAxisCount: posterColumns(context),
        childAspectRatio: _kPosterWidth / (_kPosterHeight + _kPosterLabel),
        crossAxisSpacing: AppSpacing.sm,
        mainAxisSpacing: AppSpacing.sm,
      ),
      itemCount: itens.length,
      itemBuilder: (_, i) => _CardConteudo(
        item: itens[i],
        onTap: () => onTap(itens[i]),
      ),
    );
  }
}

// ─── Tela de detalhe de categoria ────────────────────────────────────────────

class _TelaCategoriaFilmes extends StatefulWidget {
  final String nomeCategoria;
  final List<Object> itens;

  const _TelaCategoriaFilmes({
    required this.nomeCategoria,
    required this.itens,
  });

  @override
  State<_TelaCategoriaFilmes> createState() => _TelaCategoriaFilmesState();
}

class _TelaCategoriaFilmesState extends State<_TelaCategoriaFilmes> {
  late List<Object> _filtrados;
  final _buscaController = TextEditingController();
  final _scrollCtrl = ScrollController();
  String _busca = '';
  late final int _numFilmes;
  late final int _numSeries;

  @override
  void initState() {
    super.initState();
    _filtrados = widget.itens;
    _numFilmes = widget.itens.whereType<Canal>().length;
    _numSeries = widget.itens.whereType<Serie>().length;
  }

  @override
  void dispose() {
    _buscaController.dispose();
    _scrollCtrl.dispose();
    super.dispose();
  }

  String get _contagemLabel {
    final parts = <String>[];
    if (_numFilmes > 0) {
      parts.add('$_numFilmes ${_numFilmes == 1 ? "filme" : "filmes"}');
    }
    if (_numSeries > 0) {
      parts.add('$_numSeries ${_numSeries == 1 ? "série" : "séries"}');
    }
    return parts.join(' · ');
  }

  void _filtrar(String q) {
    final lower = q.trim().toLowerCase();
    setState(() {
      _busca = q;
      _filtrados = lower.isEmpty
          ? widget.itens
          : widget.itens.where((item) {
              final nome =
                  item is Canal ? item.nome : (item as Serie).nome;
              return nome.toLowerCase().contains(lower);
            }).toList();
    });
  }

  void _navegar(Object item) {
    Navigator.of(context).push(
      MaterialPageRoute(
        builder: (_) => item is Canal
            ? TelaDetalhes.filme(item)
            : TelaDetalhes.serie(item as Serie),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              widget.nomeCategoria,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
            ),
            Text(
              _contagemLabel,
              style: tabular(Theme.of(context).textTheme.bodySmall),
            ),
          ],
        ),
        bottom: PreferredSize(
          preferredSize: const Size.fromHeight(64),
          child: Padding(
            padding: const EdgeInsets.fromLTRB(
              AppSpacing.lg,
              0,
              AppSpacing.lg,
              AppSpacing.md,
            ),
            child: TextField(
              controller: _buscaController,
              decoration: InputDecoration(
                hintText: 'Buscar nesta categoria',
                prefixIcon: const Icon(Icons.search_rounded, size: 18),
                suffixIcon: _busca.isNotEmpty
                    ? IconButton(
                        icon: const Icon(Icons.clear_rounded, size: 18),
                        onPressed: () {
                          _buscaController.clear();
                          _filtrar('');
                        },
                      )
                    : null,
              ),
              onChanged: _filtrar,
            ),
          ),
        ),
      ),
      body: _filtrados.isEmpty
          ? Center(
              child: Text(
                'Nenhum resultado encontrado',
                style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                      color: AppColors.textSecondary,
                    ),
              ),
            )
          : GridView.builder(
              controller: _scrollCtrl,
              padding: const EdgeInsets.all(AppSpacing.base),
              gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
                crossAxisCount: posterColumns(context),
                childAspectRatio:
                    _kPosterWidth / (_kPosterHeight + _kPosterLabel),
                crossAxisSpacing: AppSpacing.sm,
                mainAxisSpacing: AppSpacing.sm,
              ),
              itemCount: _filtrados.length,
              itemBuilder: (_, i) => _CardConteudo(
                item: _filtrados[i],
                onTap: () => _navegar(_filtrados[i]),
              ),
            ),
    );
  }
}
