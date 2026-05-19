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
import 'tela_episodios.dart';
import 'tela_player.dart';

// Top-level: roda em Isolate separado via compute() para nao bloquear a UI.
({
  Map<String, List<Object>> conteudo,
  List<String> nomes,
  List<Object> todosConteudos,
}) _computarConteudoFilmes(Map<String, List<Canal>> categorias) {
  final conteudo = <String, List<Object>>{};
  final nomes = categorias.keys.toList()..sort();
  final visto = <String>{};
  final todos = <Object>[];

  String nomeItem(Object item) =>
      item is Canal ? item.nome : (item as Serie).nome;

  for (final cat in nomes) {
    final ag = Serie.agrupar(categorias[cat]!);
    final lista = <Object>[...ag.filmes, ...ag.series]
      ..sort((a, b) => nomeItem(a).compareTo(nomeItem(b)));
    conteudo[cat] = lista;

    for (final item in lista) {
      final key =
          item is Canal ? 'c:${item.url}' : 's:${(item as Serie).nome}';
      if (visto.add(key)) todos.add(item);
    }
  }

  return (conteudo: conteudo, nomes: nomes, todosConteudos: todos);
}

const double _kPosterWidth = 100.0;
const double _kPosterHeight = 150.0;
const double _kPosterLabel = 28.0;
const double _kItemExtent = _kPosterWidth + AppSpacing.sm;

/// Tela estilo streaming: carrosseis por categoria com filmes e series agrupadas.
/// Series sao detectadas pelo padrao SxxExx no nome e agrupadas em um unico card.
class TelaFilmes extends StatefulWidget {
  final Map<String, List<Canal>> categorias;
  const TelaFilmes({super.key, required this.categorias});

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

  @override
  void initState() {
    super.initState();
    compute(_computarConteudoFilmes, widget.categorias).then((r) {
      if (!mounted) return;
      final lookup = <String, Canal>{};
      for (final item in r.todosConteudos) {
        if (item is Canal) {
          lookup[item.url] = item;
        } else {
          for (final ep in (item as Serie).episodios) {
            lookup[ep.url] = ep;
          }
        }
      }
      setState(() {
        _conteudo = r.conteudo;
        _nomes = r.nomes;
        _todosConteudos = r.todosConteudos;
        _canaisPorUrl = lookup;
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

  void _navegar(BuildContext context, Object item, {Duration? posicaoInicial}) {
    final provider = context.read<IptvProvider>();
    if (item is Canal) {
      provider.registrarVisualizacao(item);
      Navigator.of(context).push(
        MaterialPageRoute(
          builder: (_) =>
              TelaPlayer(canal: item, posicaoInicial: posicaoInicial),
        ),
      );
    } else {
      Navigator.of(context).push(
        MaterialPageRoute(builder: (_) => TelaEpisodios(serie: item as Serie)),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    if (!_pronto) {
      return Scaffold(
        appBar: AppBar(title: const Text('Filmes e Séries')),
        body: const Center(child: CircularProgressIndicator()),
      );
    }

    return Scaffold(
      appBar: AppBar(
        titleSpacing: 0,
        title: _buscando
            ? Padding(
                padding: const EdgeInsets.only(right: AppSpacing.sm),
                child: TextField(
                  controller: _buscaController,
                  autofocus: true,
                  decoration: const InputDecoration(
                    hintText: 'Buscar filmes e séries',
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
            : const Text('Filmes e Séries'),
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
              ? const _Vazio()
              : _BodyComCarrosseis(
                  nomes: _nomes,
                  conteudo: _conteudo,
                  canaisPorUrl: _canaisPorUrl,
                  progressos: context.watch<IptvProvider>().progressos,
                  onTap: (item, {Duration? posicaoInicial}) =>
                      _navegar(context, item, posicaoInicial: posicaoInicial),
                ),
    );
  }
}

class _Vazio extends StatelessWidget {
  const _Vazio();

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(AppSpacing.xxl),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Icon(
              Icons.movie_creation_outlined,
              size: 36,
              color: AppColors.textTertiary,
            ),
            const SizedBox(height: AppSpacing.base),
            Text(
              'Sem filmes ou séries nesta lista',
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
  final List<ProgressoCanal> progressos;
  final void Function(Object, {Duration? posicaoInicial}) onTap;

  const _BodyComCarrosseis({
    required this.nomes,
    required this.conteudo,
    required this.canaisPorUrl,
    required this.progressos,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    // Filtra apenas progressos de canais presentes nesta lista, mais recente primeiro.
    final emAndamento = progressos
        .where((p) => canaisPorUrl.containsKey(p.url))
        .toList();

    final temAndamento = emAndamento.isNotEmpty;
    final total = nomes.length + (temAndamento ? 1 : 0);

    return ListView.builder(
      padding: const EdgeInsets.only(
        top: AppSpacing.sm,
        bottom: AppSpacing.xxl,
      ),
      itemCount: total,
      itemBuilder: (_, i) {
        if (temAndamento && i == 0) {
          return _CarrosselContinuar(
            progressos: emAndamento,
            canaisPorUrl: canaisPorUrl,
            onTap: (canal, progresso) => onTap(
              canal,
              posicaoInicial: Duration(seconds: progresso.posicaoSeg),
            ),
          );
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

class _CarrosselContinuar extends StatelessWidget {
  final List<ProgressoCanal> progressos;
  final Map<String, Canal> canaisPorUrl;
  final void Function(Canal canal, ProgressoCanal progresso) onTap;

  const _CarrosselContinuar({
    required this.progressos,
    required this.canaisPorUrl,
    required this.onTap,
  });

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
        SizedBox(
          height: _kPosterHeight + _kPosterLabel,
          child: ListView.builder(
            scrollDirection: Axis.horizontal,
            padding:
                const EdgeInsets.symmetric(horizontal: AppSpacing.lg),
            itemCount: progressos.length,
            itemExtent: _kItemExtent,
            itemBuilder: (_, i) {
              final p = progressos[i];
              final canal = canaisPorUrl[p.url]!;
              return _Poster(
                canal: canal,
                progresso: p,
                onTap: () => onTap(canal, p),
              );
            },
          ),
        ),
      ],
    );
  }
}

class _CarrosselCategoria extends StatelessWidget {
  final String nomeCategoria;
  final List<Object> itens;
  final void Function(Object) onTap;

  const _CarrosselCategoria({
    required this.nomeCategoria,
    required this.itens,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        InkWell(
          onTap: () => Navigator.of(context).push(
            MaterialPageRoute(
              builder: (_) => _TelaCategoriaFilmes(
                nomeCategoria: nomeCategoria,
                itens: itens,
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
                    nomeCategoria,
                    style: Theme.of(context).textTheme.titleSmall,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
                ),
                Text(
                  '${itens.length}',
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
        SizedBox(
          height: _kPosterHeight + _kPosterLabel,
          child: ListView.builder(
            scrollDirection: Axis.horizontal,
            padding: const EdgeInsets.symmetric(horizontal: AppSpacing.lg),
            itemCount: itens.length,
            itemExtent: _kItemExtent,
            itemBuilder: (_, i) => _CardConteudo(
              item: itens[i],
              onTap: () => onTap(itens[i]),
            ),
          ),
        ),
      ],
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
    if (item is Canal) {
      context.read<IptvProvider>().registrarVisualizacao(item);
      Navigator.of(context).push(
        MaterialPageRoute(builder: (_) => TelaPlayer(canal: item)),
      );
    } else {
      Navigator.of(context).push(
        MaterialPageRoute(builder: (_) => TelaEpisodios(serie: item as Serie)),
      );
    }
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
