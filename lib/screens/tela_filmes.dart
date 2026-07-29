import 'dart:async';
import 'dart:ui';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../models/canal.dart';
import '../models/canal_assistido.dart';
import '../models/progresso_canal.dart';
import '../models/serie.dart';
import '../services/tmdb_service.dart';
import '../state/iptv_provider.dart';
import '../state/perfil_provider.dart';
import '../theme/app_theme.dart';
import '../utils/chave_conteudo.dart';
import '../utils/layout.dart';
import '../utils/recencia.dart';
import '../utils/qualidade.dart';
import '../widgets/abertura_secao.dart';
import '../widgets/animado_entrada.dart';
import 'tela_detalhes.dart';

enum TipoVod { filmes, series }

/// Callback de toque num item de conteúdo. [heroTag] (opcional) identifica o
/// banner de origem para a animação Hero até a tela de detalhes.
typedef AoTocarItem = void Function(Object item, [Object? heroTag]);

/// Tag estável de um item para o Hero (igual na origem e no destino).
String chaveHero(String prefixo, Object item) {
  final k = item is Canal ? 'c:${item.url}' : 's:${(item as Serie).nome}';
  return 'hero-$prefixo-$k';
}

/// Envolve [child] num Hero quando [tag] não é nulo (origem da animação até a
/// tela de detalhes). `flightShuttleBuilder` mantém o recorte arredondado.
Widget _comHero(Object? tag, Widget child) {
  if (tag == null) return child;
  return Hero(
    tag: tag,
    // Trajetória reta (diagonal) em vez do arco padrão do Material, que faz o
    // banner ir pro lado e depois pra cima.
    createRectTween: (begin, end) => RectTween(begin: begin, end: end),
    flightShuttleBuilder: (_, _, _, _, toCtx) => ClipRRect(
      borderRadius: BorderRadius.circular(AppRadius.sm),
      child: (toCtx.widget as Hero).child,
    ),
    child: child,
  );
}

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
    // Lançamentos / Em cartaz / Estreias: ordem de CHEGADA (mais novo primeiro),
    // não alfabética — numa fila de lançamentos o que interessa é o que acabou
    // de entrar no catálogo, e o A-Z escondia isso no meio da lista.
    final lista = _ehCategoriaLancamento(cat)
        ? ordenarPorRecencia(<Object>[...items])
        : (<Object>[...items]
          ..sort((a, b) => nomeItem(a).compareTo(nomeItem(b))));
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

enum _OrdemCategoria { recentes, az, anoDesc, anoAsc, duracaoOuEp }

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
final Map<TipoVod, List<Object>> _destaqueCache = {};
// "Recomendacoes pra voce": itens do catalogo que batem com os generos TMDB do
// que o PERFIL assistiu. Cache junto com o destaque (mesma invalidacao).
final Map<TipoVod, List<Object>> _recomendadosCache = {};
// ID do perfil ativo quando o cache de destaque foi preenchido — invalida se trocar.
String? _destaquePerfilId;

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
      _destaqueCache.clear();
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
      // Lookups por CHAVE ESTAVEL (sobrevive a troca de IP/URL do provedor).
      final lookup = <String, Canal>{};
      final seriesPorEp = <String, Serie>{};
      for (final item in r.todosConteudos) {
        if (item is Canal) {
          lookup[chaveConteudo(item.url)] = item;
        } else {
          final serie = item as Serie;
          for (final ep in serie.episodios) {
            lookup[chaveConteudo(ep.url)] = ep;
            seriesPorEp[chaveConteudo(ep.url)] = serie;
          }
        }
      }
      final porChave = <String, Object>{};
      for (final item in r.todosConteudos) {
        porChave[chaveItemMinhaLista(item)] = item;
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
  /// antes disso pre-carrega as capas (TMDB) dos primeiros banners E computa o
  /// carrossel de destaque — assim a tela so abre com tudo pronto (sem pop-in).
  void _finalizarCarga() {
    if (widget.aoCarregar == null) {
      _garantirDestaqueCache();
      return;
    }
    if (widget.tipo == TipoVod.series) {
      Future.wait([
        _precarregarCapasSeries(),
        _garantirDestaqueCache(),
      ]).whenComplete(() => widget.aoCarregar?.call());
    } else {
      _garantirDestaqueCache()
          .whenComplete(() => widget.aoCarregar?.call());
    }
  }

  /// Preenche [_destaqueCache] para este tipo se nao existir ou se o perfil
  /// ativo mudou desde o ultimo preenchimento. Usa gêneros TMDB do histórico
  /// VOD do perfil para selecionar e ordenar os títulos em destaque.
  Future<void> _garantirDestaqueCache() async {
    if (!mounted) return;
    final perfilProvider = context.read<PerfilProvider>();
    final perfilId = perfilProvider.perfilAtivo?.id ?? '';

    // Invalida o cache quando o perfil muda (listas sao compartilhadas,
    // entao a identidade do mapa categorias nao muda na troca de perfil).
    if (_destaquePerfilId != perfilId) {
      _destaqueCache.clear();
      _recomendadosCache.clear();
      _destaquePerfilId = perfilId;
    }

    if (_destaqueCache.containsKey(widget.tipo)) return;

    final provider = context.read<IptvProvider>();
    final tmdb = context.read<TmdbService>();
    final idioma = perfilProvider.perfilAtivo?.idioma ?? 'pt-BR';
    final gostos = await _gostosTmdb(provider.historico, tmdb, idioma);

    final List<Object> itens;
    if (widget.tipo == TipoVod.filmes) {
      itens = await _selecionarFilmesDestaqueAsync(
          _todosConteudos, tmdb, idioma, gostos);
    } else {
      itens = await _selecionarSeriesDestaqueAsync(
          _todosConteudos, tmdb, idioma, gostos);
    }
    if (mounted) _destaqueCache[widget.tipo] = itens;

    // Recomendacoes usam os MESMOS gostos ja calculados — nenhuma consulta
    // extra ao TMDB alem da pontuacao dos candidatos.
    final recomendados = await _selecionarRecomendadosAsync(
      _todosConteudos,
      tmdb,
      idioma,
      gostos,
      ehSerie: widget.tipo == TipoVod.series,
    );
    if (mounted) _recomendadosCache[widget.tipo] = recomendados;
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
        final s = _seriesPorUrlEpisodio[chaveConteudo(p.url)];
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
              .poster(s.nome, categoria: s.grupo)
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

  /// Filtra por titulo/categoria E TAMBEM pelos nomes que o TMDB ja conhece
  /// deste item (traduzido e original) — assim "Demon Slayer" acha a lista que
  /// so tem "Kimetsu no Yaiba", e vice-versa. So usa o que ja esta em cache
  /// (nada de rede durante a digitacao); o cache agora sobrevive ao fechar o
  /// app, entao na pratica os titulos ja vistos casam.
  List<Object> _filtrar(String busca) {
    final q = Serie.chaveNome(busca);
    if (q.isEmpty) return _todosConteudos;
    final tmdb = context.read<TmdbService>();

    bool casa(String nome, String grupo, bool ehSerie) {
      if (Serie.chaveNome(nome).contains(q)) return true;
      if (Serie.chaveNome(grupo).contains(q)) return true;
      for (final apelido in tmdb.apelidosEmCache(nome, ehSerie: ehSerie)) {
        if (Serie.chaveNome(apelido).contains(q)) return true;
      }
      return false;
    }

    return _todosConteudos.where((item) {
      if (item is Canal) return casa(item.nome, item.grupo, false);
      final s = item as Serie;
      return casa(s.nome, s.grupo, true);
    }).toList();
  }

  void _navegar(BuildContext context, Object item, [Object? heroTag]) {
    // Filme ou série: sempre abre a tela de detalhes.
    Navigator.of(context).push(
      MaterialPageRoute(
        builder: (_) => item is Canal
            ? TelaDetalhes.filme(item, heroTag: heroTag)
            : TelaDetalhes.serie(item as Serie, heroTag: heroTag),
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
      // Banner do destaque flutua atrás da appbar transparente (estilo Prime).
      extendBodyBehindAppBar: true,
      appBar: AppBar(
        backgroundColor: Colors.transparent,
        elevation: 0,
        scrolledUnderElevation: 0,
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
          ? Padding(
              // Busca e vazio respeitam a appbar (só o destaque flutua atrás).
              padding: EdgeInsets.only(
                  top: MediaQuery.paddingOf(context).top + kToolbarHeight),
              child: _GradeResultados(
                itens: _filtrar(_busca),
                onTap: (item, [tag]) => _navegar(context, item, tag),
              ),
            )
          : _conteudo.isEmpty
              ? Padding(
                  padding: EdgeInsets.only(
                      top: MediaQuery.paddingOf(context).top + kToolbarHeight),
                  child: _Vazio(tipo: widget.tipo),
                )
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
                    recomendados: _recomendadosCache[widget.tipo] ?? const [],
                    todosItens: _todosConteudos,
                    tipo: widget.tipo,
                    onTap: (item, [tag]) => _navegar(context, item, tag),
                  );
                }),
      ),
    );
  }
}

// ─── Destaque (hero banner, estilo Prime Video) ──────────────────────────────

/// Gêneros TMDB mais frequentes no histórico VOD do perfil ativo.
/// Ignora canais ao vivo (tipo == aoVivo). Async porque consulta o TMDB,
/// mas os resultados ficam em cache na sessão — resolve rápido na segunda vez.
Future<List<String>> _gostosTmdb(
  List<CanalAssistido> historico,
  TmdbService tmdb,
  String idioma,
) async {
  final vod =
      historico.where((a) => a.canal.tipo == TipoCanal.filme).toList();
  if (vod.isEmpty) return const [];

  // Deduplica por nome e limita a 12 títulos únicos mais recentes.
  final vistos = <String>{};
  final candidatos = <Canal>[];
  for (final a in vod) {
    final nome = a.canal.nome.trim();
    if (nome.isNotEmpty && vistos.add(nome)) {
      candidatos.add(a.canal);
      if (candidatos.length >= 12) break;
    }
  }

  final freq = <String, int>{};
  await Future.wait(candidatos.map((c) async {
    try {
      final info = await tmdb
          .info(nome: c.nome, ehSerie: false, idioma: idioma, categoria: c.grupo)
          .timeout(const Duration(seconds: 5));
      for (final g in info.generos) {
        freq[g] = (freq[g] ?? 0) + 1;
      }
    } catch (_) {}
  }));

  if (freq.isEmpty) return const [];
  return (freq.entries.toList()..sort((a, b) => b.value.compareTo(a.value)))
      .map((e) => e.key)
      .take(5)
      .toList();
}

/// Seleciona até [n] filmes 4K para o destaque, pontuando por gêneros TMDB.
/// Amostra 25 filmes aleatórios e prefere os que mais batem com [gostos].
Future<List<Canal>> _selecionarFilmesDestaqueAsync(
  List<Object> todos,
  TmdbService tmdb,
  String idioma,
  List<String> gostos, {
  int n = 5,
}) async {
  final filmes4k = todos
      .whereType<Canal>()
      .where((c) => detectarQualidade(c.nome) == Qualidade.uhd)
      .toList();
  if (filmes4k.isEmpty) return const [];

  final amostra = (List.of(filmes4k)..shuffle()).take(n + 20).toList();
  if (gostos.isEmpty) return amostra.take(n).toList();

  final gostoSet = gostos.toSet();
  final pontos = List<int>.filled(amostra.length, 0);
  await Future.wait(List.generate(amostra.length, (i) async {
    try {
      final info = await tmdb
          .info(nome: amostra[i].nome, ehSerie: false, idioma: idioma, categoria: amostra[i].grupo)
          .timeout(const Duration(seconds: 5));
      pontos[i] = info.generos.where(gostoSet.contains).length;
    } catch (_) {}
  }));

  final indices = List.generate(amostra.length, (i) => i)
    ..sort((a, b) => pontos[b].compareTo(pontos[a]));
  return indices.take(n).map((i) => amostra[i]).toList();
}

/// Seleciona até [n] séries com banner TMDB, priorizando gostos do perfil.
Future<List<Object>> _selecionarSeriesDestaqueAsync(
  List<Object> todos,
  TmdbService tmdb,
  String idioma,
  List<String> gostos, {
  int n = 5,
}) async {
  final todas = (todos.whereType<Serie>().toList()..shuffle()).take(40).toList();
  final comBanner = <Serie>[];
  for (final s in todas) {
    if (comBanner.length >= 15) break;
    try {
      final url =
          await tmdb.poster(s.nome, categoria: s.grupo).timeout(const Duration(seconds: 3));
      if (url != null && url.isNotEmpty) comBanner.add(s);
    } catch (_) {}
  }
  if (comBanner.isEmpty) return const [];
  if (gostos.isEmpty) return (comBanner..shuffle()).take(n).toList();

  // Pontua cada série pelo número de gêneros TMDB que batem com os gostos.
  final gostoSet = gostos.toSet();
  final pontos = List<int>.filled(comBanner.length, 0);
  await Future.wait(List.generate(comBanner.length, (i) async {
    try {
      final info = await tmdb
          .info(nome: comBanner[i].nome, ehSerie: true, idioma: idioma, categoria: comBanner[i].grupo)
          .timeout(const Duration(seconds: 5));
      pontos[i] = info.generos.where(gostoSet.contains).length;
    } catch (_) {}
  }));

  final indices = List.generate(comBanner.length, (i) => i)
    ..sort((a, b) => pontos[b].compareTo(pontos[a]));
  return indices.take(n).map((i) => comBanner[i]).toList();
}

/// "Recomendacoes pra voce": pontua uma amostra do catalogo pelos generos TMDB
/// que o perfil mais assistiu. Sem historico, nao ha recomendacao (a fila
/// simplesmente nao aparece) — melhor do que fingir personalizacao.
///
/// Porte de `Biblioteca.recomendacoes` do app de TV. So consulta o TMDB de uma
/// AMOSTRA (o catalogo tem dezenas de milhares de itens) e o cache agora e
/// persistido em disco, entao a partir da 2a sessao isto sai quase de graca.
Future<List<Object>> _selecionarRecomendadosAsync(
  List<Object> todos,
  TmdbService tmdb,
  String idioma,
  List<String> gostos, {
  required bool ehSerie,
  int n = 18,
}) async {
  if (gostos.isEmpty) return const [];
  final candidatos = (List.of(todos)..shuffle()).take(60).toList();
  final gostoSet = gostos.toSet();
  final pontos = List<int>.filled(candidatos.length, 0);

  await Future.wait(List.generate(candidatos.length, (i) async {
    final item = candidatos[i];
    final nome = item is Canal ? item.nome : (item as Serie).nome;
    try {
      final info = await tmdb
          .info(nome: nome, ehSerie: ehSerie, idioma: idioma, categoria: item is Canal ? item.grupo : (item as Serie).grupo)
          .timeout(const Duration(seconds: 5));
      pontos[i] = info.generos.where(gostoSet.contains).length;
    } catch (_) {}
  }));

  final indices = List.generate(candidatos.length, (i) => i)
    ..sort((a, b) => pontos[b].compareTo(pontos[a]));
  return [
    for (final i in indices)
      if (pontos[i] > 0) candidatos[i],
  ].take(n).toList();
}

class _SecaoDestaque extends StatefulWidget {
  final List<Object> todosItens;
  final TipoVod tipo;
  final AoTocarItem onTap;

  const _SecaoDestaque({
    required this.todosItens,
    required this.tipo,
    required this.onTap,
  });

  @override
  State<_SecaoDestaque> createState() => _SecaoDestaqueState();
}

class _SecaoDestaqueState extends State<_SecaoDestaque>
    with SingleTickerProviderStateMixin, AutomaticKeepAliveClientMixin {
  @override
  bool get wantKeepAlive => true;
  final _pageCtrl = PageController();
  late final AnimationController _animCtrl;
  Timer? _autoTimer;

  int _pagina = 0;
  List<Object> _itens = const [];
  final _posterUrls = <int, String?>{};
  final _infos = <int, TmdbInfo>{};

  static const _intervalo = Duration(seconds: 7);
  static const _duracaoAnim = Duration(milliseconds: 700);
  static const _duracaoTransicao = Duration(milliseconds: 500);

  @override
  void initState() {
    super.initState();
    _animCtrl = AnimationController(vsync: this, duration: _duracaoAnim);
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (_itens.isEmpty) _lerCache();
  }

  void _lerCache() {
    final cached = _destaqueCache[widget.tipo];
    if (cached == null || cached.isEmpty) return;
    setState(() => _itens = cached);
    _animCtrl.forward();
    _iniciarTimer();
    _precarregarInfos();
  }

  Future<void> _precarregarInfos() async {
    if (!mounted) return;
    final tmdb = context.read<TmdbService>();
    final idioma =
        context.read<PerfilProvider>().perfilAtivo?.idioma ?? 'pt-BR';

    for (int i = 0; i < _itens.length; i++) {
      if (!mounted) return;
      final item = _itens[i];
      final nome = item is Canal ? item.nome : (item as Serie).nome;
      final ehSerie = item is Serie;

      if (!_posterUrls.containsKey(i)) {
        if (item is Canal) {
          _posterUrls[i] =
              (item.logoUrl?.isNotEmpty == true) ? item.logoUrl : null;
        } else {
          try {
            _posterUrls[i] = await tmdb
                .poster((item as Serie).nome, categoria: item.grupo)
                .timeout(const Duration(seconds: 4));
          } catch (_) {
            _posterUrls[i] = null;
          }
        }
      }

      if (!_infos.containsKey(i)) {
        try {
          _infos[i] = await tmdb
              .info(nome: nome, ehSerie: ehSerie, idioma: idioma, categoria: item is Canal ? item.grupo : (item as Serie).grupo)
              .timeout(const Duration(seconds: 5));
        } catch (_) {
          _infos[i] = TmdbInfo.vazio;
        }
      }

      if (mounted) setState(() {});
    }
  }

  void _iniciarTimer() {
    _autoTimer?.cancel();
    if (_itens.length <= 1) return;
    _autoTimer = Timer.periodic(_intervalo, (_) {
      if (!mounted) return;
      final prox = (_pagina + 1) % _itens.length;
      _pageCtrl.animateToPage(
        prox,
        duration: _duracaoTransicao,
        curve: Curves.easeInOutCubic,
      );
    });
  }

  void _irPara(int i) {
    _autoTimer?.cancel();
    _pageCtrl.animateToPage(
      i,
      duration: _duracaoTransicao,
      curve: Curves.easeInOutCubic,
    );
    _iniciarTimer();
  }

  @override
  void dispose() {
    _autoTimer?.cancel();
    _pageCtrl.dispose();
    _animCtrl.dispose();
    super.dispose();
  }

  // ── Animações (só opacity + transform → compositor GPU, 60 fps) ──────────

  Animation<double> _fade(double from, double to) => CurvedAnimation(
        parent: _animCtrl,
        curve: Interval(from, to, curve: Curves.easeOut),
      );

  Animation<Offset> _slide(double from, double to) =>
      Tween<Offset>(begin: const Offset(0, 0.22), end: Offset.zero).animate(
        CurvedAnimation(
          parent: _animCtrl,
          curve: Interval(from, to, curve: Curves.easeOutCubic),
        ),
      );

  @override
  Widget build(BuildContext context) {
    super.build(context); // AutomaticKeepAliveClientMixin
    if (_itens.isEmpty) return const SizedBox.shrink();

    final ff = formFactor(context);
    final isPhone = ff == FormFactor.phone;
    final isTabletLandscape = ff == FormFactor.tablet &&
        MediaQuery.orientationOf(context) == Orientation.landscape;
    final centrado = ff == FormFactor.desktop || isTabletLandscape;
    final h = isPhone ? 220.0 : (ff == FormFactor.tablet ? 300.0 : 360.0);

    // Espaço atrás da appbar transparente: o fundo blur sobe até o topo da tela
    // (status bar + toolbar), com gradiente no topo.
    final topInset = MediaQuery.paddingOf(context).top + kToolbarHeight;
    final alturaTotal = h + topInset;
    // Conteúdo (poster/info) sobe um pouco para dentro da zona da appbar
    // transparente — menos distância vazia entre a barra e o destaque.
    final topConteudo = topInset - 22;
    final alturaConteudo = alturaTotal - topConteudo;

    // Gradiente até AppColors.surface0 em vez de ShaderMask+dstIn.
    // dstIn cria pixels transparentes → linha visível ao scrollar no ListView.
    Widget banner = SizedBox(
      height: alturaTotal,
      // ClipRect: o blur (ImageFiltered) expande a camada além dos limites do
      // banner e sangra para baixo/laterais — sem clip, esse sangramento vira
      // a linha visível abaixo do destaque. Clipamos para a área real.
      child: ClipRect(
        child: Stack(
        clipBehavior: Clip.hardEdge,
        children: [
          // ── Banners (fundo blur + poster) — preenche tudo, atrás da appbar ─
          PageView.builder(
            controller: _pageCtrl,
            onPageChanged: (i) {
              setState(() => _pagina = i);
              _animCtrl.forward(from: 0);
              _iniciarTimer();
            },
            itemCount: _itens.length,
            itemBuilder: (_, i) => _buildBackground(i, topConteudo, isPhone),
          ),

          // ── Info animada (sobreposta) — alinhada ao topo (abaixo da appbar).
          // Animação de SAÍDA: a opacidade do texto cai conforme o PageView se
          // afasta da página atual, então o texto antigo some antes do banner
          // novo passar por trás (e volta com o stagger quando assenta).
          Positioned(
            top: topInset,
            left: 0,
            right: 0,
            bottom: 0,
            child: IgnorePointer(
              child: AnimatedBuilder(
                animation: _pageCtrl,
                builder: (context, child) {
                  final page = _pageCtrl.hasClients
                      ? (_pageCtrl.page ?? _pagina.toDouble())
                      : _pagina.toDouble();
                  final dist = (page - page.roundToDouble()).abs();
                  final op = (1 - dist / 0.5).clamp(0.0, 1.0);
                  return Opacity(opacity: op, child: child);
                },
                child: AnimatedBuilder(
                  animation: _animCtrl,
                  builder: (_, _) =>
                      _buildInfo(context, isPhone, alturaConteudo, centrado),
                ),
              ),
            ),
          ),

          // ── Tap overlay ────────────────────────────────────────────────
          Positioned(
            top: topConteudo,
            left: 0,
            right: 0,
            bottom: 0,
            child: GestureDetector(
              behavior: HitTestBehavior.translucent,
              onTap: _pagina < _itens.length
                  ? () => widget.onTap(
                        _itens[_pagina],
                        chaveHero('destaque', _itens[_pagina]),
                      )
                  : null,
            ),
          ),

          // ── Fade superior (gradiente no topo, atrás da appbar) ─────────
          Positioned(
            top: 0,
            left: 0,
            right: 0,
            height: topInset + 24,
            child: IgnorePointer(
              child: DecoratedBox(
                decoration: BoxDecoration(
                  gradient: LinearGradient(
                    begin: Alignment.topCenter,
                    end: Alignment.bottomCenter,
                    colors: [AppColors.surface0, Colors.transparent],
                  ),
                ),
              ),
            ),
          ),

          // ── Blend do blur para o preto, logo acima da barra opaca ──────
          Positioned(
            left: 0,
            right: 0,
            bottom: 22,
            height: h * 0.34,
            child: IgnorePointer(
              child: DecoratedBox(
                decoration: BoxDecoration(
                  gradient: LinearGradient(
                    begin: Alignment.topCenter,
                    end: Alignment.bottomCenter,
                    colors: [Colors.transparent, AppColors.surface0],
                  ),
                ),
              ),
            ),
          ),

          // ── Fades laterais (desktop / tablet landscape) ────────────────
          if (centrado) ...[
            Positioned(
              left: 0,
              top: 0,
              bottom: 0,
              width: 72,
              child: IgnorePointer(
                child: DecoratedBox(
                  decoration: BoxDecoration(
                    gradient: LinearGradient(
                      begin: Alignment.centerLeft,
                      end: Alignment.centerRight,
                      colors: [AppColors.surface0, Colors.transparent],
                    ),
                  ),
                ),
              ),
            ),
            Positioned(
              right: 0,
              top: 0,
              bottom: 0,
              width: 72,
              child: IgnorePointer(
                child: DecoratedBox(
                  decoration: BoxDecoration(
                    gradient: LinearGradient(
                      begin: Alignment.centerRight,
                      end: Alignment.centerLeft,
                      colors: [AppColors.surface0, Colors.transparent],
                    ),
                  ),
                ),
              ),
            ),
          ],

          // ── Barra preta OPACA da base até logo acima das bolinhas. O
          // gradiente é semi-transparente e deixava o blur passar em banner
          // claro; esta barra é 100% opaca, então nada vaza no fim. ─────────
          Positioned(
            left: 0,
            right: 0,
            bottom: 0,
            height: 22,
            child: const ColoredBox(color: AppColors.surface0),
          ),

          // ── Bolinhas (na frente de tudo p/ não escurecerem) ────────────
          Positioned(
            bottom: 10,
            left: 0,
            right: 0,
            child: _buildDots(),
          ),
        ],
        ),
      ),
    );

    // Phone e tablet portrait: largura toda
    if (!centrado) return banner;

    // Desktop/tablet landscape: 70% centrado.
    // Setas nas margens externas — apenas desktop.
    final mostrarSetas = ff == FormFactor.desktop && _itens.length > 1;

    return SizedBox(
      height: alturaTotal,
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Expanded(
            flex: 15,
            child: mostrarSetas
                ? Center(child: _buildSeta(esquerda: true))
                : const SizedBox.shrink(),
          ),
          Expanded(flex: 70, child: banner),
          Expanded(
            flex: 15,
            child: mostrarSetas
                ? Center(child: _buildSeta(esquerda: false))
                : const SizedBox.shrink(),
          ),
        ],
      ),
    );
  }

  Widget _buildBackground(int i, double topConteudo, bool isPhone) {
    final poster = _posterUrls[i];

    return Stack(
      fit: StackFit.expand,
      clipBehavior: Clip.hardEdge,
      children: [
        // Base sólida = fundo do app. Garante que nenhuma transparência/void
        // apareça sob a deformação do overscroll (sem linha na borda).
        const ColoredBox(color: AppColors.surface0),

        // Fundo desfocado (sobre a base sólida). A imagem desaparece (vira
        // transparente) antes da borda inferior via ShaderMask → no fim só
        // sobra a base preta sólida, então o corte do ClipRect cai sobre
        // preto e não há linha brilhante do blur. dstIn aqui é seguro porque
        // a base (ColoredBox surface0) mantém o banner opaco.
        if (poster != null)
          ShaderMask(
            shaderCallback: (rect) => const LinearGradient(
              begin: Alignment.topCenter,
              end: Alignment.bottomCenter,
              // Imagem 100% transparente já em 0.80 → os ~20% finais são só a
              // base preta sólida (blur nem é pintado lá). Em banner branco
              // não sobra nada para o clip antiserrilhar na borda.
              stops: [0.0, 0.58, 0.80],
              colors: [Colors.white, Colors.white, Colors.transparent],
            ).createShader(rect),
            blendMode: BlendMode.dstIn,
            child: ImageFiltered(
              imageFilter: ImageFilter.blur(sigmaX: 30, sigmaY: 30),
              child: Image.network(
                poster,
                fit: BoxFit.cover,
                errorBuilder: (_, _, _) =>
                    Container(color: AppColors.surface2),
              ),
            ),
          )
        else
          const ColoredBox(color: AppColors.surface2),

        // Gradiente escuro (horizontal: direita → esquerda)
        Container(
          decoration: BoxDecoration(
            gradient: LinearGradient(
              begin: Alignment.centerRight,
              end: Alignment.centerLeft,
              stops: const [0.0, 0.4, 1.0],
              colors: [
                Colors.transparent,
                Colors.black54,
                Colors.black.withValues(alpha: 0.92),
              ],
            ),
          ),
        ),
        // Poster à esquerda (na região abaixo da appbar)
        if (poster != null)
          Positioned(
            left: AppSpacing.lg,
            top: topConteudo,
            bottom: AppSpacing.xl + 4, // acima das bolinhas
            child: AspectRatio(
              aspectRatio: 2 / 3,
              child: _comHero(
                i < _itens.length
                    ? chaveHero('destaque', _itens[i])
                    : null,
                ClipRRect(
                  borderRadius: BorderRadius.circular(8),
                  child: Image.network(
                    poster,
                    fit: BoxFit.cover,
                    errorBuilder: (_, _, _) =>
                        Container(color: AppColors.surface2),
                  ),
                ),
              ),
            ),
          ),
      ],
    );
  }

  Widget _buildInfo(BuildContext context, bool isPhone, double alturaConteudo,
      bool centrado) {
    if (_pagina >= _itens.length) return const SizedBox.shrink();

    final item = _itens[_pagina];
    final nome = item is Canal ? item.nome : (item as Serie).nome;
    final info = _infos[_pagina];
    // Largura real do poster: o poster ocupa a região de conteúdo de
    // topConteudo até (bottom: xl+4) — concordância evita o texto começar
    // antes do fim do poster.
    final posterAlturaReal = alturaConteudo - AppSpacing.xl - 4;
    final posterW = posterAlturaReal * (2 / 3);
    final leftMargin = AppSpacing.lg + posterW + AppSpacing.base;

    return Padding(
      padding: EdgeInsets.only(
        left: leftMargin,
        right: centrado ? AppSpacing.xl : AppSpacing.base,
        top: 6,
        bottom: 16,
      ),
      child: Column(
        mainAxisAlignment: MainAxisAlignment.start,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Nome
          FadeTransition(
            opacity: _fade(0.0, 0.55),
            child: SlideTransition(
              position: _slide(0.0, 0.55),
              child: Text(
                nome,
                style: Theme.of(context).textTheme.titleLarge?.copyWith(
                      fontWeight: FontWeight.w800,
                      color: Colors.white,
                      fontSize: centrado ? 26.0 : null,
                      shadows: const [
                        Shadow(color: Colors.black54, blurRadius: 8)
                      ],
                    ),
                maxLines: 2,
                overflow: TextOverflow.ellipsis,
              ),
            ),
          ),

          SizedBox(height: centrado ? 8 : 6),

          // Nota + ano
          if (info != null && (info.nota != null || info.ano != null))
            FadeTransition(
              opacity: _fade(0.25, 0.70),
              child: Row(
                children: [
                  if (info.nota != null) ...[
                    Icon(Icons.star_rounded,
                        size: centrado ? 16 : 13,
                        color: Colors.amber.shade400),
                    const SizedBox(width: 3),
                    Text(
                      info.nota!.toStringAsFixed(1),
                      style:
                          Theme.of(context).textTheme.labelMedium?.copyWith(
                                color: Colors.white70,
                                fontWeight: FontWeight.w700,
                                fontSize: centrado ? 15.0 : null,
                              ),
                    ),
                    const SizedBox(width: 8),
                  ],
                  if (info.ano != null)
                    Text(
                      '${info.ano}',
                      style:
                          Theme.of(context).textTheme.labelMedium?.copyWith(
                                color: Colors.white54,
                                fontSize: centrado ? 15.0 : null,
                              ),
                    ),
                ],
              ),
            ),

          SizedBox(height: centrado ? 10 : 8),

          // Sinopse
          if (info?.sinopse != null)
            FadeTransition(
              opacity: _fade(0.45, 1.0),
              child: SlideTransition(
                position: _slide(0.45, 1.0),
                child: Text(
                  info!.sinopse!,
                  style: Theme.of(context)
                      .textTheme
                      .bodySmall
                      ?.copyWith(
                        color: Colors.white60,
                        height: 1.45,
                        fontSize: centrado ? 13.5 : null,
                      ),
                  maxLines: isPhone ? 4 : 6,
                  overflow: TextOverflow.ellipsis,
                ),
              ),
            ),
        ],
      ),
    );
  }

  Widget _buildSeta({required bool esquerda}) {
    return MouseRegion(
      cursor: SystemMouseCursors.click,
      child: GestureDetector(
        onTap: () => _irPara(
          esquerda
              ? (_pagina - 1 + _itens.length) % _itens.length
              : (_pagina + 1) % _itens.length,
        ),
        child: Container(
          width: 34,
          height: 34,
          decoration: BoxDecoration(
            color: Colors.white.withValues(alpha: 0.10),
            shape: BoxShape.circle,
            border: Border.all(
              color: Colors.white.withValues(alpha: 0.22),
              width: 1,
            ),
          ),
          child: Icon(
            esquerda
                ? Icons.chevron_left_rounded
                : Icons.chevron_right_rounded,
            color: Colors.white.withValues(alpha: 0.80),
            size: 20,
          ),
        ),
      ),
    );
  }

  Widget _buildDots() {
    return Row(
      mainAxisAlignment: MainAxisAlignment.center,
      children: List.generate(_itens.length, (i) {
        final ativo = i == _pagina;
        return GestureDetector(
          onTap: () => _irPara(i),
          child: AnimatedContainer(
            duration: const Duration(milliseconds: 300),
            curve: Curves.easeOutCubic,
            margin: const EdgeInsets.symmetric(horizontal: 3),
            width: ativo ? 18 : 5,
            height: 5,
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(2.5),
              color: ativo ? AppColors.accent : Colors.white30,
            ),
          ),
        );
      }),
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
  final List<Object> recomendados;
  final List<Object> todosItens;
  final TipoVod tipo;
  final AoTocarItem onTap;

  const _BodyComCarrosseis({
    required this.nomes,
    required this.conteudo,
    required this.canaisPorUrl,
    required this.seriesPorUrlEpisodio,
    required this.progressos,
    required this.minhaListaItens,
    required this.recomendados,
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
      final canal = canaisPorUrl[chaveConteudo(p.url)];
      if (canal == null) continue;
      final serie = seriesPorUrlEpisodio[chaveConteudo(p.url)];
      if (serie != null) {
        if (seriesVistas.add(serie.nome)) {
          continuar.add(_ItemContinuar.serie(serie));
        }
      } else {
        continuar.add(_ItemContinuar.filme(canal, p));
      }
    }

    final temAndamento = continuar.isNotEmpty;
    final temRecomendados = recomendados.isNotEmpty;
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

    // Carrosseis especiais no topo, nesta ordem:
    // Continuar → Recomendacoes → Minha lista → Todos/Todas.
    int especialCount = 0;
    if (temAndamento) especialCount++;
    if (temRecomendados) especialCount++;
    if (temMinhaLista) especialCount++;
    especialCount++; // "Todos"/"Todas" sempre presente

    final total = ordemCategorias.length + especialCount;

    return ListView.builder(
      padding: const EdgeInsets.only(
        bottom: AppSpacing.xxl,
      ),
      itemCount: total + 1, // +1 para a seção destaque no topo
      itemBuilder: (_, i) {
        // Item 0 → seção destaque (hero banner)
        if (i == 0) {
          return _SecaoDestaque(
            todosItens: todosItens,
            tipo: tipo,
            onTap: onTap,
          );
        }
        final j = i - 1; // índice real nos carrosseis
        final Widget linha;
        final posRecomendados = temAndamento ? 1 : 0;
        final posMinhaLista = posRecomendados + (temRecomendados ? 1 : 0);
        if (temAndamento && j == 0) {
          linha = _CarrosselContinuar(itens: continuar, onTap: onTap);
        } else if (temRecomendados && j == posRecomendados) {
          linha = _CarrosselCategoria(
            nomeCategoria: 'Recomendações pra você',
            itens: recomendados,
            onTap: onTap,
          );
        } else if (temMinhaLista && j == posMinhaLista) {
          linha = _CarrosselCategoria(
            nomeCategoria: 'Minha lista',
            itens: minhaListaItens,
            onTap: onTap,
          );
        } else if (j == especialCount - 1) {
          linha = _CarrosselCategoria(
            nomeCategoria: nomeTodos,
            itens: todosOrdenados,
            onTap: onTap,
          );
        } else {
          final idx = j - especialCount;
          final nome = ordemCategorias[idx];
          linha = _CarrosselCategoria(
            nomeCategoria: nome,
            itens: conteudo[nome]!,
            onTap: onTap,
          );
        }
        final Widget conteudoLinha = j < _kFilasAnimadas
            ? AnimadoEntrada(
                delay: Duration(milliseconds: 70 * j),
                child: linha,
              )
            : linha;

        // Primeira categoria: "chapéu" preto opaco que invade pra cima o
        // espaço do destaque (até perto das bolinhas), cobrindo qualquer
        // resíduo/linha do blur que sobre na borda — sem engordar a barra.
        if (j == 0) {
          return Stack(
            clipBehavior: Clip.none,
            children: [
              conteudoLinha,
              const Positioned(
                // Bolinhas ficam a 10px da borda do destaque; sobe só 8px
                // para cobrir a linha sem tampar a seleção.
                top: -8,
                left: 0,
                right: 0,
                height: 10,
                child: ColoredBox(color: AppColors.surface0),
              ),
            ],
          );
        }
        return conteudoLinha;
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
  final AoTocarItem onTap;

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
              height: posterH,
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
                    final tag = chaveHero('cont', serie);
                    return _PosterSerie(
                      key: ValueKey('cont:${serie.nome}'),
                      serie: serie,
                      width: itemW,
                      heroTag: tag,
                      onTap: () => widget.onTap(serie, tag),
                    );
                  }
                  final filme = item.filme!;
                  final tag = chaveHero('cont', filme);
                  return _Poster(
                    canal: filme,
                    progresso: item.progresso,
                    width: itemW,
                    heroTag: tag,
                    onTap: () => widget.onTap(filme, tag),
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
  final AoTocarItem onTap;

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
              height: posterH,
              scrollStep: itemExtent * 3,
              child: ListView.builder(
                controller: _ctrl,
                scrollDirection: Axis.horizontal,
                padding:
                    const EdgeInsets.symmetric(horizontal: AppSpacing.lg),
                itemCount: widget.itens.length,
                itemExtent: itemExtent,
                itemBuilder: (_, i) {
                  final item = widget.itens[i];
                  final tag = chaveHero(widget.nomeCategoria, item);
                  return _CardConteudo(
                    item: item,
                    width: itemW,
                    heroTag: tag,
                    onTap: () => widget.onTap(item, tag),
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
  final Object? heroTag;
  const _CardConteudo({
    required this.item,
    required this.onTap,
    this.width = _kPosterWidth,
    this.heroTag,
  });

  @override
  Widget build(BuildContext context) {
    if (item is Canal) {
      return _Poster(
        canal: item as Canal,
        onTap: onTap,
        width: width,
        heroTag: heroTag,
      );
    }
    final serie = item as Serie;
    return _PosterSerie(
      key: ValueKey(serie.nome),
      serie: serie,
      onTap: onTap,
      width: width,
      heroTag: heroTag,
    );
  }
}

class _Poster extends StatelessWidget {
  final Canal canal;
  final VoidCallback onTap;
  final ProgressoCanal? progresso;
  final double width;
  final Object? heroTag;
  const _Poster({
    required this.canal,
    required this.onTap,
    this.progresso,
    this.width = _kPosterWidth,
    this.heroTag,
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
                        child: _comHero(
                          heroTag,
                          canal.logoUrl != null &&
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
  final Object? heroTag;
  const _PosterSerie({
    super.key,
    required this.serie,
    required this.onTap,
    this.width = _kPosterWidth,
    this.heroTag,
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
        context.read<TmdbService>().poster(widget.serie.nome, categoria: widget.serie.grupo);
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
                            child: _comHero(
                              widget.heroTag,
                              url != null
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
  final AoTocarItem onTap;

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
        childAspectRatio: _kPosterWidth / _kPosterHeight,
        crossAxisSpacing: AppSpacing.sm,
        mainAxisSpacing: AppSpacing.sm,
      ),
      itemCount: itens.length,
      itemBuilder: (_, i) {
        final item = itens[i];
        final tag = chaveHero('busca', item);
        return _CardConteudo(
          item: item,
          heroTag: tag,
          onTap: () => onTap(item, tag),
        );
      },
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
  late _OrdemCategoria _ordem;

  @override
  void initState() {
    super.initState();
    // Em categoria de lançamento a ordem padrão é a de chegada; nas demais,
    // A-Z (que é o que faz sentido para procurar um título específico).
    _ordem = _ehCategoriaLancamento(widget.nomeCategoria)
        ? _OrdemCategoria.recentes
        : _OrdemCategoria.az;
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
      case _OrdemCategoria.recentes:
        return ordenarPorRecencia(copia);
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

  void _navegar(Object item, [Object? heroTag]) {
    Navigator.of(context).push(
      MaterialPageRoute(
        builder: (_) => item is Canal
            ? TelaDetalhes.filme(item, heroTag: heroTag)
            : TelaDetalhes.serie(item as Serie, heroTag: heroTag),
      ),
    );
  }

  String get _labelOrdem {
    switch (_ordem) {
      case _OrdemCategoria.recentes:
        return 'Adicionados por último';
      case _OrdemCategoria.az:
        return 'A-Z';
      case _OrdemCategoria.anoDesc:
        return 'Ano (mais novo)';
      case _OrdemCategoria.anoAsc:
        return 'Ano (mais antigo)';
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
                _OrdemCategoria.recentes,
                'Adicionados por último',
                Icons.new_releases_rounded,
              ),
              _itemOrdem(
                _OrdemCategoria.az,
                'A-Z',
                Icons.sort_by_alpha_rounded,
              ),
              _itemOrdem(
                _OrdemCategoria.anoDesc,
                'Ano (mais novo)',
                Icons.calendar_today_rounded,
              ),
              _itemOrdem(
                _OrdemCategoria.anoAsc,
                'Ano (mais antigo)',
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
                childAspectRatio: _kPosterWidth / _kPosterHeight,
                crossAxisSpacing: AppSpacing.sm,
                mainAxisSpacing: AppSpacing.sm,
              ),
              itemCount: exibidos.length,
              itemBuilder: (_, i) {
                final item = exibidos[i];
                final tag = chaveHero('cat', item);
                return _CardConteudo(
                  item: item,
                  heroTag: tag,
                  onTap: () => _navegar(item, tag),
                );
              },
            ),
    );
  }
}
