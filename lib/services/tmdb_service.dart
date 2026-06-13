import 'dart:convert';
import 'package:http/http.dart' as http;

/// Um ator do elenco: nome + foto (opcional) vindos do TMDB.
class AtorTmdb {
  final String nome;
  final String? fotoUrl;
  const AtorTmdb({required this.nome, this.fotoUrl});
}

/// Informacoes de um filme/serie vindas do TMDB — sinopse, ano e elenco.
///
/// O poster NAO entra aqui de proposito: filmes usam o banner da propria
/// lista M3U; series ja tiveram o poster buscado no carrossel.
class TmdbInfo {
  final String? sinopse;
  final int? ano;
  final List<AtorTmdb> elenco;

  /// Nota media (0..10) do TMDB — aproxima a nota do IMDB. Null se indisponivel.
  final double? nota;

  /// Generos (ex.: "Ação", "Comédia"). Vazio se indisponivel. Sera usado para
  /// recomendar titulos relacionados na tela do filme/serie.
  final List<String> generos;

  const TmdbInfo({
    this.sinopse,
    this.ano,
    this.elenco = const [],
    this.nota,
    this.generos = const [],
  });

  /// Resultado vazio — sem chave de API, sem match, ou erro de rede.
  static const vazio = TmdbInfo();

  /// `true` quando nenhuma informacao util foi encontrada.
  bool get semDados => sinopse == null && ano == null && elenco.isEmpty;
}

/// Busca dados de filmes/series na API publica do TMDB.
///
/// Dois caches em memoria (poster e info), independentes — cada consulta
/// e feita apenas uma vez por sessao.
///
/// Estrategia de match (por ordem de prioridade):
///   1. Correspondencia exata com nome ou nome original
///   2. Correspondencia "comeca com"
///   3. Correspondencia "contem"
///   4. Todas as palavras da query aparecem no resultado
///   5. Primeiro resultado (mais popular segundo o TMDB)
class TmdbService {
  static const _imgBase = 'https://image.tmdb.org/t/p/w500';
  // Foto de perfil do elenco — w185 é o tamanho ideal para avatares.
  static const _perfilBase = 'https://image.tmdb.org/t/p/w185';

  final String proxyBaseUrl;
  final _cachePoster = <String, String?>{};
  final _cacheInfo = <String, TmdbInfo>{};

  TmdbService(this.proxyBaseUrl);

  bool get configurado => proxyBaseUrl.trim().isNotEmpty;

  // ─── Poster (carrosseis de series) ───────────────────────────────────────

  /// Retorna URL do poster para o nome da serie, ou null se nao encontrar.
  /// Tenta TV shows primeiro, depois movies (cobre animes e OVAs).
  Future<String?> posterSerie(String nome) async {
    if (!configurado) return null;
    if (_cachePoster.containsKey(nome)) return _cachePoster[nome];

    final query = _prepararQuery(nome);
    final item = await _buscarItem('/3/search/tv', query, 'en-US', true) ??
        await _buscarItem('/3/search/movie', query, 'en-US', false);

    final poster = item?['poster_path'] as String?;
    final url = poster != null ? '$_imgBase$poster' : null;

    _cachePoster[nome] = url;
    return url;
  }

  // ─── Sinopse + ano + elenco (sob demanda, ao abrir o detalhe) ────────────

  /// Busca sinopse, ano de lancamento e elenco principal (top 5).
  ///
  /// [ehSerie] decide se procura primeiro em series ou em filmes (com
  /// fallback para o outro tipo). [idioma] e um codigo BCP-47 (ex.: 'pt-BR').
  Future<TmdbInfo> info({
    required String nome,
    required bool ehSerie,
    required String idioma,
  }) async {
    if (!configurado) return TmdbInfo.vazio;

    final chave = '$idioma|${ehSerie ? 'tv' : 'movie'}|$nome';
    final cache = _cacheInfo[chave];
    if (cache != null) return cache;

    final query = _prepararQuery(nome);

    // Procura no tipo primario; se nao achar nada, tenta o outro tipo.
    Map<String, dynamic>? item;
    bool ehTv;
    if (ehSerie) {
      item = await _buscarItem('/3/search/tv', query, idioma, true);
      ehTv = true;
      if (item == null) {
        item = await _buscarItem('/3/search/movie', query, idioma, false);
        ehTv = false;
      }
    } else {
      item = await _buscarItem('/3/search/movie', query, idioma, false);
      ehTv = false;
      if (item == null) {
        item = await _buscarItem('/3/search/tv', query, idioma, true);
        ehTv = true;
      }
    }

    if (item == null) {
      _cacheInfo[chave] = TmdbInfo.vazio;
      return TmdbInfo.vazio;
    }

    final id = item['id'] as int?;
    final sinopse = (item['overview'] as String?)?.trim();
    final data = (item['release_date'] ?? item['first_air_date']) as String?;
    final ano = (data != null && data.length >= 4)
        ? int.tryParse(data.substring(0, 4))
        : null;

    final elenco =
        id != null ? await _elenco(id, ehTv, idioma) : const <AtorTmdb>[];

    final notaRaw = (item['vote_average'] as num?)?.toDouble();
    final nota = (notaRaw != null && notaRaw > 0) ? notaRaw : null;

    final genreIds = (item['genre_ids'] as List?)
            ?.map((g) => g is int ? g : int.tryParse('$g'))
            .whereType<int>()
            .toList() ??
        const <int>[];
    final mapaG = genreIds.isEmpty ? const <int, String>{} : await _mapaGeneros(ehTv, idioma);
    final generos =
        genreIds.map((g) => mapaG[g]).whereType<String>().take(3).toList();

    final info = TmdbInfo(
      sinopse: (sinopse != null && sinopse.isNotEmpty) ? sinopse : null,
      ano: ano,
      elenco: elenco,
      nota: nota,
      generos: generos,
    );
    _cacheInfo[chave] = info;
    return info;
  }

  // ─── Mapa id->nome dos generos (cacheado por tipo+idioma) ────────────────
  final _cacheGeneros = <String, Map<int, String>>{};

  Future<Map<int, String>> _mapaGeneros(bool ehTv, String idioma) async {
    if (!configurado) return const {};
    final chave = '${ehTv ? 'tv' : 'movie'}|$idioma';
    final cache = _cacheGeneros[chave];
    if (cache != null) return cache;
    try {
      final uri = Uri.parse('${proxyBaseUrl.trim()}/api/tmdb').replace(
        queryParameters: {
          'p': ehTv ? '/3/genre/tv/list' : '/3/genre/movie/list',
          'language': idioma,
        },
      );
      final resp = await http.get(uri).timeout(const Duration(seconds: 6));
      if (resp.statusCode != 200) return const {};
      final body = jsonDecode(resp.body) as Map<String, dynamic>;
      final list = (body['genres'] as List?) ?? const [];
      final mapa = <int, String>{};
      for (final g in list) {
        final m = g as Map<String, dynamic>;
        final id = m['id'] as int?;
        final nome = (m['name'] as String?)?.trim();
        if (id != null && nome != null && nome.isNotEmpty) mapa[id] = nome;
      }
      _cacheGeneros[chave] = mapa;
      return mapa;
    } catch (_) {
      return const {};
    }
  }

  /// Top 10 atores do elenco (nome + foto). Lista vazia em caso de erro.
  Future<List<AtorTmdb>> _elenco(int id, bool ehTv, String idioma) async {
    try {
      final endpoint = ehTv ? '/3/tv/$id/credits' : '/3/movie/$id/credits';
      final uri = Uri.parse(
        '${proxyBaseUrl.trim()}/api/tmdb',
      ).replace(queryParameters: {'p': endpoint, 'language': idioma});
      final resp = await http.get(uri).timeout(const Duration(seconds: 6));
      if (resp.statusCode != 200) return const [];

      final body = jsonDecode(resp.body) as Map<String, dynamic>;
      final cast = (body['cast'] as List<dynamic>?) ?? const [];
      final atores = <AtorTmdb>[];
      for (final c in cast.take(10)) {
        final m = c as Map<String, dynamic>;
        final nome = (m['name'] as String?)?.trim();
        if (nome == null || nome.isEmpty) continue;
        final foto = m['profile_path'] as String?;
        atores.add(AtorTmdb(
          nome: nome,
          fotoUrl: (foto != null && foto.isNotEmpty) ? '$_perfilBase$foto' : null,
        ));
      }
      return atores;
    } catch (_) {
      return const [];
    }
  }

  // ─── Busca + ranking de match ────────────────────────────────────────────

  /// Procura no [endpoint] e devolve o melhor resultado (o Map cru do TMDB),
  /// ou null. [ehTv] define quais campos de nome conferir.
  Future<Map<String, dynamic>?> _buscarItem(
    String endpoint,
    String query,
    String idioma,
    bool ehTv,
  ) async {
    try {
      final uri = Uri.parse(
        '${proxyBaseUrl.trim()}/api/tmdb',
      ).replace(queryParameters: {
        'p': endpoint,
        'query': query,
        'language': idioma,
        'include_adult': 'false',
      });
      final resp = await http.get(uri).timeout(const Duration(seconds: 6));
      if (resp.statusCode != 200) return null;

      final body = jsonDecode(resp.body) as Map<String, dynamic>;
      final results = (body['results'] as List<dynamic>?) ?? const [];
      if (results.isEmpty) return null;

      final campoNome = ehTv ? 'name' : 'title';
      final campoOriginal = ehTv ? 'original_name' : 'original_title';

      final queryNorm = _norm(query);
      final queryWords =
          queryNorm.split(' ').where((w) => w.isNotEmpty).toList();

      bool nomeMatch(Map<String, dynamic> item, bool Function(String) test) {
        final n = _norm(item[campoNome] as String? ?? '');
        final o = _norm(item[campoOriginal] as String? ?? '');
        return test(n) || test(o);
      }

      Map<String, dynamic>? melhor;

      // 1. Match exato
      for (final r in results.take(10)) {
        final item = r as Map<String, dynamic>;
        if (nomeMatch(item, (s) => s == queryNorm)) {
          melhor = item;
          break;
        }
      }
      // 2. Comeca com
      if (melhor == null) {
        for (final r in results.take(10)) {
          final item = r as Map<String, dynamic>;
          if (nomeMatch(item, (s) => s.startsWith(queryNorm))) {
            melhor = item;
            break;
          }
        }
      }
      // 3. Contem
      if (melhor == null) {
        for (final r in results.take(10)) {
          final item = r as Map<String, dynamic>;
          if (nomeMatch(item, (s) => s.contains(queryNorm))) {
            melhor = item;
            break;
          }
        }
      }
      // 4. Todas as palavras da query aparecem no resultado
      if (melhor == null && queryWords.length > 1) {
        for (final r in results.take(10)) {
          final item = r as Map<String, dynamic>;
          if (nomeMatch(item, (s) => queryWords.every(s.contains))) {
            melhor = item;
            break;
          }
        }
      }
      // 5. Fallback: primeiro resultado (mais popular)
      melhor ??= results.first as Map<String, dynamic>;
      return melhor;
    } catch (_) {
      return null;
    }
  }

  /// Limpa residuos tipicos de nomes IPTV antes de consultar o TMDB.
  ///
  /// Usado SO para montar a query — o nome exibido ao usuario nunca passa
  /// por aqui. Tags de qualidade ("4K", "1080p"...) quebram a busca.
  static String _prepararQuery(String nome) => nome
      // Tags de idioma entre colchetes/parenteses: [EN], (PT-BR), [ESP]...
      .replaceAll(
          RegExp(r'[\[\(][A-Za-z]{2,5}(?:[\-\s][A-Za-z]{2,3})?[\]\)]'), ' ')
      // Ano entre colchetes/parenteses: (1989), [2019]
      .replaceAll(RegExp(r'[\[\(]\d{4}[\]\)]'), ' ')
      // Qualidade / resolucao / fonte (com ou sem colchetes): 4K, UHD,
      // 1080p, HD, HDR, WEB-DL, BluRay... — quebram a busca no TMDB.
      .replaceAll(
          RegExp(
              r'\b(?:4K|UHD|FHD|QHD|HDR|HD|SD|2160P|1080P|720P|480P|'
              r'WEB[\s\-]?DL|BLURAY|BRRIP|DVDRIP|HDCAM|CAM)\b',
              caseSensitive: false),
          ' ')
      // Idioma / versao soltos: LEG, DUB, VOST, DUAL, LEGENDADO, DUBLADO
      .replaceAll(
          RegExp(r'\b(?:LEG|DUB|VOST|DUAL|LEGENDADO|DUBLADO)\b',
              caseSensitive: false),
          ' ')
      // Pontos e underscores como separadores viram espacos
      .replaceAll(RegExp(r'[._]'), ' ')
      // Colchetes/parenteses restantes (agora vazios ou orfaos)
      .replaceAll(RegExp(r'[\[\]\(\)]'), ' ')
      // Espacos multiplos
      .replaceAll(RegExp(r'\s+'), ' ')
      .trim();

  /// Normaliza para comparacao: minusculo, sem pontuacao, espacos simples.
  static String _norm(String s) => s
      .toLowerCase()
      .replaceAll(RegExp(r'[._]'), ' ')
      .replaceAll(RegExp(r"[^\w\s]"), '')
      .replaceAll(RegExp(r'\s+'), ' ')
      .trim();
}
