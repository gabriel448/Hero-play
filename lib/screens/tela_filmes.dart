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
import '../widgets/abertura_secao.dart';
import '../widgets/animado_entrada.dart';
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

const int _kDesktopVisibleCount = 14;

double _computeDesktopItemWidth(double availableWidth) =>
    (availableWidth - AppSpacing.lg * 2) / _kDesktopVisibleCount - AppSpacing.sm;

// Remove acentos e converte para minúsculas para comparação robusta.
String _normalizar(String s) => s
    .toLowerCase()
    .replaceAll(RegExp(r'[àáâãä]'), 'a')
    .replaceAll(RegExp(r'[èéêë]'), 'e')
    .replaceAll(RegExp(r'[ìíîï]'), 'i')
    .replaceAll(RegExp(r'[òóôõö]'), 'o')
    .replaceAll(RegExp(r'[ùúûü]'), 'u')
    .replaceAll('ç', 'c')
    .replaceAll('ñ', 'n');

// Palavras-chave que identificam categorias de lançamentos.
const _kwLancamento = ['lanca', 'cinema', 'estreia', 'cartaz', 'em alta'];

bool _ehCategoriaLancamento(String nome) {
  final n = _normalizar(nome);
  return _kwLancamento.any((k) => n.contains(k));
}

enum _OrdemCategoria { az, anoDesc, anoAsc, duracaoOuEp }

// Extrai o ano de lancamento do titulo (ex: "Avatar (2009)" -> 2009).
// Prefere o ultimo ano encontrado para evitar falso positivo em titulos
// como "2001: A Space Odyssey".
int? _extrairAno(String nome) {
  final matches =
      RegExp(r'\b(19[5-9]\d|20[0-3]\d)\b').allMatches(nome).toList();
  if (matches.isEmpty) return null;
  return int.tryParse(matches.last.group(0)!);
}

/// Entrada do cache de sessao do conteudo agrupado de VOD (filmes ou series).
/// Evita recomputar o agrupamento (e re-esperar o load) ao reentrar na secao.
class _VodCacheEntry {
  final Map<String, List<Object>> conteudo;
  final List<String> nomes;
  final List<Object> todosConteudos;
  final Map<String, Canal> canaisPorUrl;
  final Map<String, Serie> seriesPorUrlEpisodio;
  final Map<String, Object> todosPorChave;
  const _VodCacheEntry({
    required this.conteudo,
    required this.nomes,
    required this.todosConteudos,
    required this.canaisPorUrl,
    required this.seriesPorUrlEpisodio,
    required this.todosPorChave,
  });
}

// Cache em memoria por tipo (max 2 entradas: filmes + series da lista atual).
// Invalida sozinho quando muda a identidade do mapa `categorias` (lista/perfil).
int? _vodCacheIdentidade;
final Map<TipoVod, _VodCacheEntry> _vodCache = {};

/// Tela estilo streaming: carrosseis por categoria — filmes ou séries.
class TelaFilmes extends StatefulWidget {
  final Map<String, List<Canal>> categorias;
  final TipoVod tipo;
  /// Chamado quando o conteudo termina de carregar (parse/agrupamento). Usado
  /// pela animacao de abertura ([AberturaSecao]) para sair do estagio de pulso.
  final VoidCallback? aoCarregar;
  const TelaFilmes({
    super.key,
    required this.categorias,
    this.tipo = TipoVod.filmes,
    this.aoCarregar,
  });

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
  // Lookup chave ("c:url" ou "s:nome") → item (Canal ou Serie)
  Map<String, Object> _todosPorChave = const {};

  @override
  void initState() {
    super.initState();
    // Cache de sessao: invalida se a fonte (mapa categorias) mudou de
    // identidade — a home so o recria ao trocar de lista/perfil.
    final identidade = identityHashCode(widget.categorias);
    if (_vodCacheIdentidade != identidade) {
      _vodCache.clear();
      _vodCacheIdentidade = identidade;
    }

    final cache = _vodCache[widget.tipo];
    if (cache != null) {
      // Reentrada: conteudo ja agrupado antes — sem espera de carregamento.
      _conteudo = cache.conteudo;
      _nomes = cache.nomes;
      _todosConteudos = cache.todosConteudos;
      _canaisPorUrl = cache.canaisPorUrl;
      _seriesPorUrlEpisodio = cache.seriesPorUrlEpisodio;
      _todosPorChave = cache.todosPorChave;
      _pronto = true;
      _finalizarCarga();
      return;
    }

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
      final porChave = <String, Object>{};
      for (final item in r.todosConteudos) {
        if (item is Canal) {
          porChave['c:${item.url}'] = item;
        } else {
          final s = item as Serie;
          porChave['s:${s.nome}'] = s;
        }
      }
      // Guarda no cache para acelerar as proximas visitas a esta secao.
      _vodCache[widget.tipo] = _VodCacheEntry(
        conteudo: r.conteudo,
        nomes: r.nomes,
        todosConteudos: r.todosConteudos,
        canaisPorUrl: lookup,
        seriesPorUrlEpisodio: seriesPorEp,
        todosPorChave: porChave,
      );
      setState(() {
        _conteudo = r.conteudo;
        _nomes = r.nomes;
        _todosConteudos = r.todosConteudos;
        _canaisPorUrl = lookup;
        _seriesPorUrlEpisodio = seriesPorEp;
        _todosPorChave = porChave;
        _pronto = true;
      });
      _finalizarCarga();
    });
  }

  /// Sinaliza para a animacao de abertura que o conteudo esta pronto. Em SERIES,
  /// antes disso pre-carrega as capas (TMDB) dos primeiros banners — assim a
  /// tela so abre quando os posters visiveis ja estao prontos (sem pop-in). Na
  /// reentrada (cache), tanto o agrupamento quanto as capas ja estao em cache,
  /// entao isto resolve quase instantaneamente.
  void _finalizarCarga() {
    if (widget.aoCarregar == null) return;
    if (widget.tipo == TipoVod.series) {
      _precarregarCapasSeries().whenComplete(() => widget.aoCarregar?.call());
    } else {
      widget.aoCarregar!.call();
    }
  }

  /// Pre-carrega (TMDB + cache de imagem) as capas das primeiras series na
  /// ordem em que aparecem (Continuar -> Minha lista -> Todas A-Z), para a
  /// tela de series abrir com os banners do topo ja prontos. Best-effort: cada
  /// capa tem timeout proprio e falhas nao travam a abertura.
  Future<void> _precarregarCapasSeries() async {
    try {
      if (!mounted) return;
      final tmdb = context.read<TmdbService>();
      final provider = context.read<IptvProvider>();

      final ordem = <Serie>[];
      final vistos = <String>{};
      void add(Serie s) {
        if (vistos.add(s.nome)) ordem.add(s);
      }

      // Continuar assistindo (series com progresso) — primeira fila do topo.
      for (final p in provider.progressos) {
        final s = _seriesPorUrlEpisodio[p.url];
        if (s != null) add(s);
      }
      // Minha lista.
      for (final k in provider.minhaListaChaves) {
        final item = _todosPorChave[k];
        if (item is Serie) add(item);
      }
      // Todas (A-Z) — o carrossel "Todas" do topo.
      final todas = _todosConteudos.whereType<Serie>().toList()
        ..sort((a, b) => a.nome.toLowerCase().compareTo(b.nome.toLowerCase()));
      for (final s in todas) {
        add(s);
      }

      const maxCapas = 12;
      final alvo = ordem.take(maxCapas).toList();

      await Future.wait(alvo.map((s) async {
        try {
          final url = await tmdb
              .posterSerie(s.nome)
              .timeout(const Duration(seconds: 4));
          final fonte = (url != null && url.isNotEmpty)
              ? url
              : (s.logoUrl != null && s.logoUrl!.isNotEmpty
                  ? s.logoUrl
                  : null);
          if (fonte != null && mounted) {
            await precacheImage(NetworkImage(fonte), context)
                .timeout(const Duration(seconds: 4));
          }
        } catch (_) {
          /* uma capa que falhar nao deve travar a abertura */
        }
      }));
    } catch (_) {
      /* best-effort */
    }
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
    final icone = widget.tipo == TipoVod.filmes
        ? Icons.movie_creation_outlined
        : Icons.tv_rounded;
    final nomeSecao = widget.tipo == TipoVod.filmes ? 'Filmes' : 'Séries';
    // So construimos o conteudo quando a abertura comeca a revelar — assim os
    // carrosseis entram com stagger em sincronia (igual aos botoes da home).
    final revelar = AberturaSecao.conteudoRevelado(context);

    if (!_pronto) {
      // Sem spinner: durante a animacao de abertura esta tela fica invisivel
      // (a AberturaSecao mostra o pulso); o conteudo surge so quando pronto.
      return Scaffold(
        appBar: AppBar(
          centerTitle: true,
          title: TituloSecao(
            icone: icone,
            texto: nomeSecao,
            corIcone: AppColors.textSecondary,
          ),
        ),
        body: const SizedBox.shrink(),
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
        centerTitle: !_buscando,
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
            : TituloSecao(
                icone: icone,
                texto: nomeSecao,
                corIcone: AppColors.textSecondary,
              ),
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
      body: !revelar
          ? const SizedBox.shrink()
          : _buscando && _busca.isNotEmpty
          ? _GradeResultados(
              itens: _filtrar(_busca),
              onTap: (item) => _navegar(context, item),
            )
          : _conteudo.isEmpty
              ? _Vazio(tipo: widget.tipo)
              : Builder(builder: (context) {
                  final provider = context.watch<IptvProvider>();
                  final minhaListaItens = provider.minhaListaChaves
                      .map((k) => _todosPorChave[k])
                      .whereType<Object>()
                      .toList();
                  return _BodyComCarrosseis(
                    nomes: _nomes,
                    conteudo: _conteudo,
                    canaisPorUrl: _canaisPorUrl,
                    seriesPorUrlEpisodio: _seriesPorUrlEpisodio,
                    progressos: provider.progressos,
                    minhaListaItens: minhaListaItens,
                    todosItens: _todosConteudos,
                    tipo: widget.tipo,
                    onTap: (item) => _navegar(context, item),
                  );
                }),
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
  final List<Object> minhaListaItens;
  final List<Object> todosItens;
  final TipoVod tipo;
  final void Function(Object) onTap;

  const _BodyComCarrosseis({
    required this.nomes,
    required this.conteudo,
    required this.canaisPorUrl,
    required this.seriesPorUrlEpisodio,
    required this.progressos,
    required this.minhaListaItens,
    required this.todosItens,
    required this.tipo,
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
    final temMinhaLista = minhaListaItens.isNotEmpty;
    final nomeTodos = tipo == TipoVod.series ? 'Todas' : 'Todos';
    // Todos ordenados alfabeticamente para o carrossel fixo do topo.
    final todosOrdenados = [...todosItens]..sort((a, b) {
        String n(Object o) => o is Canal ? o.nome : (o as Serie).nome;
        return n(a).toLowerCase().compareTo(n(b).toLowerCase());
      });

    // Lançamentos sempre ficam logo após os carrosseis especiais.
    // Normaliza acentos antes de comparar (listas IPTV costumam omiti-los).
    final ordemCategorias = [
      ...nomes.where(_ehCategoriaLancamento),
      ...nomes.where((n) => !_ehCategoriaLancamento(n)),
    ];

    // Carrosseis especiais no topo: Continuar → Minha lista → Todos/Todas.
    int especialCount = 0;
    if (temAndamento) especialCount++;
    if (temMinhaLista) especialCount++;
    especialCount++; // "Todos"/"Todas" sempre presente

    final total = ordemCategorias.length + especialCount;

    return ListView.builder(
      padding: const EdgeInsets.only(
        top: AppSpacing.sm,
        bottom: AppSpacing.xxl,
      ),
      itemCount: total,
      itemBuilder: (_, i) {
        final Widget linha;
        if (temAndamento && i == 0) {
          linha = _CarrosselContinuar(itens: continuar, onTap: onTap);
        } else if (temMinhaLista && i == (temAndamento ? 1 : 0)) {
          linha = _CarrosselCategoria(
            nomeCategoria: 'Minha lista',
            itens: minhaListaItens,
            onTap: onTap,
          );
        } else if (i == especialCount - 1) {
          // Carrossel "Todos"/"Todas" — sempre no topo após os especiais acima.
          linha = _CarrosselCategoria(
            nomeCategoria: nomeTodos,
            itens: todosOrdenados,
            onTap: onTap,
          );
        } else {
          final idx = i - especialCount;
          final nome = ordemCategorias[idx];
          linha = _CarrosselCategoria(
            nomeCategoria: nome,
            itens: conteudo[nome]!,
            onTap: (item) => onTap(item),
          );
        }
        // Entrada animada (fade + slide) escalonada nas primeiras filas — as
        // visiveis no topo. As demais (so vistas ao rolar) entram sem animacao.
        if (i < _kFilasAnimadas) {
          return AnimadoEntrada(
            delay: Duration(milliseconds: 70 * i),
            child: linha,
          );
        }
        return linha;
      },
    );
  }
}

/// Quantas filas de carrossel animam na entrada (as visiveis no topo).
const int _kFilasAnimadas = 5;

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
    final desktop = isDesktop(context);
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
        LayoutBuilder(
          builder: (context, constraints) {
            final itemW = desktop
                ? _computeDesktopItemWidth(constraints.maxWidth)
                : _kPosterWidth;
            final posterH = desktop
                ? itemW * (_kPosterHeight / _kPosterWidth)
                : _kPosterHeight;
            final itemExtent = itemW + AppSpacing.sm;
            return _CarrosselComBotoes(
              ctrl: _ctrl,
              height: posterH + _kPosterLabel,
              scrollStep: itemExtent * 3,
              child: ListView.builder(
                controller: _ctrl,
                scrollDirection: Axis.horizontal,
                padding: const EdgeInsets.symmetric(horizontal: AppSpacing.lg),
                itemCount: widget.itens.length,
                itemExtent: itemExtent,
                itemBuilder: (_, i) {
                  final item = widget.itens[i];
                  final serie = item.serie;
                  if (serie != null) {
                    return _PosterSerie(
                      key: ValueKey('cont:${serie.nome}'),
                      serie: serie,
                      width: itemW,
                      onTap: () => widget.onTap(serie),
                    );
                  }
                  final filme = item.filme!;
                  return _Poster(
                    canal: filme,
                    progresso: item.progresso,
                    width: itemW,
                    onTap: () => widget.onTap(filme),
                  );
                },
              ),
            );
          },
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
        LayoutBuilder(
          builder: (context, constraints) {
            final desktop = isDesktop(context);
            final itemW = desktop
                ? _computeDesktopItemWidth(constraints.maxWidth)
                : _kPosterWidth;
            final posterH = desktop
                ? itemW * (_kPosterHeight / _kPosterWidth)
                : _kPosterHeight;
            final itemExtent = itemW + AppSpacing.sm;
            return _CarrosselComBotoes(
              ctrl: _ctrl,
              height: posterH + _kPosterLabel,
              scrollStep: itemExtent * 3,
              child: ListView.builder(
                controller: _ctrl,
                scrollDirection: Axis.horizontal,
                padding:
                    const EdgeInsets.symmetric(horizontal: AppSpacing.lg),
                itemCount: widget.itens.length,
                itemExtent: itemExtent,
                itemBuilder: (_, i) => _CardConteudo(
                  item: widget.itens[i],
                  width: itemW,
                  onTap: () => widget.onTap(widget.itens[i]),
                ),
              ),
            );
          },
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
  final double scrollStep;

  const _CarrosselComBotoes({
    required this.ctrl,
    required this.height,
    required this.child,
    this.scrollStep = _kScrollStep,
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
                  onTap: () => _rolar(-widget.scrollStep),
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
                  onTap: () => _rolar(widget.scrollStep),
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
  final double width;
  const _CardConteudo({
    required this.item,
    required this.onTap,
    this.width = _kPosterWidth,
  });

  @override
  Widget build(BuildContext context) {
    if (item is Canal) {
      return _Poster(canal: item as Canal, onTap: onTap, width: width);
    }
    final serie = item as Serie;
    return _PosterSerie(
      key: ValueKey(serie.nome),
      serie: serie,
      onTap: onTap,
      width: width,
    );
  }
}

class _Poster extends StatelessWidget {
  final Canal canal;
  final VoidCallback onTap;
  final ProgressoCanal? progresso;
  final double width;
  const _Poster({
    required this.canal,
    required this.onTap,
    this.progresso,
    this.width = _kPosterWidth,
  });

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(right: AppSpacing.sm),
      child: SizedBox(
        width: width,
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
  final double width;
  const _PosterSerie({
    super.key,
    required this.serie,
    required this.onTap,
    this.width = _kPosterWidth,
  });

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
        width: widget.width,
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
  late final bool _ehSeries;
  _OrdemCategoria _ordem = _OrdemCategoria.az;

  @override
  void initState() {
    super.initState();
    _filtrados = widget.itens;
    _numFilmes = widget.itens.whereType<Canal>().length;
    _numSeries = widget.itens.whereType<Serie>().length;
    _ehSeries = _numSeries > _numFilmes;
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

  String _nomeItem(Object o) => o is Canal ? o.nome : (o as Serie).nome;

  List<Object> _ordenar(List<Object> lista) {
    final copia = [...lista];
    switch (_ordem) {
      case _OrdemCategoria.az:
        copia.sort((a, b) =>
            _normalizar(_nomeItem(a)).compareTo(_normalizar(_nomeItem(b))));
      case _OrdemCategoria.anoDesc:
      case _OrdemCategoria.anoAsc:
        copia.sort((a, b) {
          final ya = _extrairAno(_nomeItem(a));
          final yb = _extrairAno(_nomeItem(b));
          if (ya == null && yb == null) {
            return _normalizar(_nomeItem(a))
                .compareTo(_normalizar(_nomeItem(b)));
          }
          if (ya == null) return 1;
          if (yb == null) return -1;
          return _ordem == _OrdemCategoria.anoDesc
              ? yb.compareTo(ya)
              : ya.compareTo(yb);
        });
      case _OrdemCategoria.duracaoOuEp:
        copia.sort((a, b) {
          if (a is Serie && b is Serie) {
            final diff = b.totalEpisodios.compareTo(a.totalEpisodios);
            return diff != 0
                ? diff
                : _normalizar(a.nome).compareTo(_normalizar(b.nome));
          }
          if (a is Canal && b is Canal) {
            final da = a.duracaoSegundos ?? 0;
            final db = b.duracaoSegundos ?? 0;
            final diff = db.compareTo(da);
            return diff != 0
                ? diff
                : _normalizar(a.nome).compareTo(_normalizar(b.nome));
          }
          return _normalizar(_nomeItem(a)).compareTo(_normalizar(_nomeItem(b)));
        });
    }
    return copia;
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

  String get _labelOrdem {
    switch (_ordem) {
      case _OrdemCategoria.az:
        return 'A-Z';
      case _OrdemCategoria.anoDesc:
        return 'Mais recentes';
      case _OrdemCategoria.anoAsc:
        return 'Mais antigos';
      case _OrdemCategoria.duracaoOuEp:
        return _ehSeries ? 'Mais episódios' : 'Duração';
    }
  }

  PopupMenuItem<_OrdemCategoria> _itemOrdem(
    _OrdemCategoria valor,
    String label,
    IconData icone,
  ) {
    final selecionado = _ordem == valor;
    return PopupMenuItem(
      value: valor,
      child: Row(
        children: [
          Icon(
            icone,
            size: 18,
            color: selecionado ? AppColors.accent : AppColors.textSecondary,
          ),
          const SizedBox(width: AppSpacing.sm),
          Expanded(
            child: Text(
              label,
              style: TextStyle(
                color: selecionado ? AppColors.accent : null,
                fontWeight:
                    selecionado ? FontWeight.w600 : FontWeight.normal,
              ),
            ),
          ),
          if (selecionado)
            const Icon(Icons.check_rounded,
                size: 16, color: AppColors.accent),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final exibidos = _ordenar(_filtrados);
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
        actions: [
          PopupMenuButton<_OrdemCategoria>(
            tooltip: 'Ordenar por',
            initialValue: _ordem,
            onSelected: (v) => setState(() => _ordem = v),
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: AppSpacing.sm),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  const Icon(Icons.sort_rounded, size: 20),
                  const SizedBox(width: 4),
                  Text(
                    _labelOrdem,
                    style: Theme.of(context).textTheme.labelMedium,
                  ),
                  const SizedBox(width: 4),
                ],
              ),
            ),
            itemBuilder: (_) => [
              _itemOrdem(
                _OrdemCategoria.az,
                'A-Z',
                Icons.sort_by_alpha_rounded,
              ),
              _itemOrdem(
                _OrdemCategoria.anoDesc,
                'Mais recentes',
                Icons.calendar_today_rounded,
              ),
              _itemOrdem(
                _OrdemCategoria.anoAsc,
                'Mais antigos',
                Icons.history_rounded,
              ),
              _itemOrdem(
                _OrdemCategoria.duracaoOuEp,
                _ehSeries ? 'Mais episódios' : 'Duração',
                _ehSeries
                    ? Icons.format_list_numbered_rounded
                    : Icons.timelapse_rounded,
              ),
            ],
          ),
        ],
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
      body: exibidos.isEmpty
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
              itemCount: exibidos.length,
              itemBuilder: (_, i) => _CardConteudo(
                item: exibidos[i],
                onTap: () => _navegar(exibidos[i]),
              ),
            ),
    );
  }
}
