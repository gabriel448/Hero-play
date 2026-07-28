import 'dart:async';
import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;

import 'armazenamento.dart';

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

  /// Nome no idioma do app e nome ORIGINAL, como o TMDB devolveu. Servem para
  /// a BUSCA achar por referencia/traducao: a lista traz "Kimetsu no Yaiba" e o
  /// usuario digita "Demon Slayer" (ou o contrario).
  final String? nome;
  final String? original;

  /// Ids canonicos de genero do TMDB — usados como tags de recomendacao.
  final List<int> generoIds;

  const TmdbInfo({
    this.sinopse,
    this.ano,
    this.elenco = const [],
    this.nota,
    this.generos = const [],
    this.nome,
    this.original,
    this.generoIds = const [],
  });

  Map<String, dynamic> toMap() => {
        if (sinopse != null) 'sinopse': sinopse,
        if (ano != null) 'ano': ano,
        if (nota != null) 'nota': nota,
        if (generos.isNotEmpty) 'generos': generos,
        if (generoIds.isNotEmpty) 'generoIds': generoIds,
        if (nome != null) 'nome': nome,
        if (original != null) 'original': original,
        if (elenco.isNotEmpty)
          'elenco': [
            for (final a in elenco)
              {'nome': a.nome, if (a.fotoUrl != null) 'foto': a.fotoUrl},
          ],
      };

  factory TmdbInfo.fromMap(Map map) => TmdbInfo(
        sinopse: map['sinopse'] as String?,
        ano: (map['ano'] as num?)?.toInt(),
        nota: (map['nota'] as num?)?.toDouble(),
        generos: [...?(map['generos'] as List?)?.whereType<String>()],
        generoIds: [
          ...?(map['generoIds'] as List?)?.map((e) => (e as num).toInt()),
        ],
        nome: map['nome'] as String?,
        original: map['original'] as String?,
        elenco: [
          ...?(map['elenco'] as List?)?.whereType<Map>().map(
                (m) => AtorTmdb(
                  nome: m['nome'] as String? ?? '',
                  fotoUrl: m['foto'] as String?,
                ),
              ),
        ],
      );

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

  /// Persistencia opcional do cache. Sem ela o servico funciona igual, mas os
  /// caches morrem ao fechar o app.
  final Armazenamento? _armazenamento;

  final _cachePoster = <String, String?>{};
  final _cacheInfo = <String, TmdbInfo>{};

  // Tetos do que vai pro disco (as chaves de um Map em Dart preservam ordem de
  // insercao, entao guardamos os mais RECENTES).
  static const _limitePoster = 40000;
  static const _limiteInfo = 4000;

  Timer? _debouncePersistencia;

  TmdbService(this.proxyBaseUrl, {Armazenamento? armazenamento})
      // ignore: prefer_initializing_formals
      : _armazenamento = armazenamento {
    _restaurarCache();
  }

  // ─── Cache em disco ──────────────────────────────────────────────────────

  void _restaurarCache() {
    final a = _armazenamento;
    if (a == null) return;
    try {
      final dump = a.carregarCacheTmdb();
      if (dump == null || dump['v'] != 1) return;
      for (final e in ((dump['poster'] as Map?) ?? const {}).entries) {
        // So o formato novo ("tv|nome"/"mv|nome"). As chaves antigas (so o
        // nome) vinham de quando o poster era procurado em /search/tv para
        // tudo — podem estar TROCADAS.
        final k = e.key as String;
        if (k.startsWith('tv|') || k.startsWith('mv|')) {
          _cachePoster[k] = e.value as String?;
        }
      }
      for (final e in ((dump['info'] as Map?) ?? const {}).entries) {
        _cacheInfo[e.key as String] = TmdbInfo.fromMap(e.value as Map);
      }
    } catch (e) {
      debugPrint('[TMDB] cache local invalido: $e');
    }
  }

  /// Grava o cache em disco com debounce — um titulo novo nao dispara uma
  /// escrita imediata, senao gravariamos o dump inteiro dezenas de vezes
  /// enquanto o usuario rola um carrossel.
  void _agendarPersistencia() {
    final a = _armazenamento;
    if (a == null) return;
    _debouncePersistencia?.cancel();
    _debouncePersistencia = Timer(const Duration(seconds: 5), () {
      try {
        a.salvarCacheTmdb({
          'v': 1,
          'poster': _ultimos(_cachePoster, _limitePoster),
          'info': {
            for (final e in _ultimos(_cacheInfo, _limiteInfo).entries)
              e.key: e.value.toMap(),
          },
        });
      } catch (e) {
        debugPrint('[TMDB] falha ao gravar cache: $e');
      }
    });
  }

  static Map<String, T> _ultimos<T>(Map<String, T> m, int n) {
    if (m.length <= n) return m;
    final chaves = m.keys.toList();
    return {
      for (final k in chaves.sublist(chaves.length - n)) k: m[k] as T,
    };
  }

  void dispose() => _debouncePersistencia?.cancel();

  bool get configurado => proxyBaseUrl.trim().isNotEmpty;

  /// Nomes alternativos ja conhecidos deste titulo (traduzido + original), SEM
  /// tocar na rede. Usado pela busca para achar por referencia: a lista traz
  /// "Kimetsu no Yaiba" e o usuario digita "Demon Slayer".
  ///
  /// Vem do cache de [info], que agora e persistido em disco — entao vale para
  /// tudo que o usuario ja abriu alguma vez, mesmo em outra sessao.
  List<String> apelidosEmCache(String nome, {required bool ehSerie}) {
    final sufixo = '|${ehSerie ? 'tv' : 'movie'}|$nome';
    final out = <String>[];
    for (final e in _cacheInfo.entries) {
      if (!e.key.endsWith(sufixo)) continue;
      final i = e.value;
      if (i.nome != null && i.nome!.isNotEmpty) out.add(i.nome!);
      if (i.original != null && i.original!.isNotEmpty) out.add(i.original!);
    }
    return out;
  }

  // ─── Poster ──────────────────────────────────────────────────────────────

  /// Retorna a URL do poster do titulo, ou null se o TMDB nao tiver.
  ///
  /// Regras (as mesmas do app de TV, depois do bug de "capa de outro filme"):
  ///  - procura SEMPRE no endpoint do tipo certo primeiro (serie -> tv,
  ///    filme -> movie). Procurar filme em /search/tv trazia programas de TV
  ///    homonimos e o poster saia trocado;
  ///  - pt-BR antes de en-US: o titulo da lista costuma ser o traduzido
  ///    ("Interestelar" so casa com language=pt-BR);
  ///  - match ESTRITO: sem casar por titulo, devolve null (fica o fallback da
  ///    UI) em vez de pegar "o primeiro que veio".
  Future<String?> poster(String nome, {bool ehSerie = true}) async {
    if (!configurado) return null;
    final chave = '${ehSerie ? 'tv' : 'mv'}|$nome';
    if (_cachePoster.containsKey(chave)) return _cachePoster[chave];

    final query = _prepararQuery(nome);
    final principal = ehSerie ? '/3/search/tv' : '/3/search/movie';
    final outro = ehSerie ? '/3/search/movie' : '/3/search/tv';
    final item =
        await _buscarItem(principal, query, 'pt-BR', ehSerie, estrito: true) ??
            await _buscarItem(principal, query, 'en-US', ehSerie,
                estrito: true) ??
            await _buscarItem(outro, query, 'pt-BR', !ehSerie, estrito: true);

    final caminho = item?['poster_path'] as String?;
    final url = caminho != null ? '$_imgBase$caminho' : null;

    _cachePoster[chave] = url;
    _agendarPersistencia();
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
      _agendarPersistencia();
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
      generoIds: genreIds,
      nome: (item[ehTv ? 'name' : 'title'] as String?)?.trim(),
      original: (item[ehTv ? 'original_name' : 'original_title'] as String?)
          ?.trim(),
    );
    _cacheInfo[chave] = info;
    _agendarPersistencia();
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
  /// [estrito]: nao cai no "primeiro resultado" quando nada casa por titulo —
  /// e esse fallback que produz capa de outro filme.
  Future<Map<String, dynamic>?> _buscarItem(
    String endpoint,
    String query,
    String idioma,
    bool ehTv, {
    bool estrito = false,
  }) async {
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
      // 5. Fallback: primeiro resultado (mais popular) — desligado no modo
      //    estrito, onde preferimos NAO ter poster a ter o poster errado.
      if (melhor == null && estrito) return null;
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
      // Pontuacao separadora QUEBRA a busca do TMDB: ':' faz
      // "Titulo: Subtitulo" voltar 0 resultados. Vira espaco. Apostrofo, hifen
      // e '&' ficam (funcionam: "Grey's Anatomy", "Spider-Man").
      .replaceAll(RegExp(r'[:;!?,|/\\*"“”]'), ' ')
      // Pontos e underscores como separadores viram espacos
      .replaceAll(RegExp(r'[._]'), ' ')
      // Colchetes/parenteses restantes (agora vazios ou orfaos)
      .replaceAll(RegExp(r'[\[\]\(\)]'), ' ')
      // Espacos multiplos
      .replaceAll(RegExp(r'\s+'), ' ')
      .trim();

  /// Acentos -> letra base. Dart nao tem normalizacao Unicode no core e o
  /// `[^\w\s]` do _norm APAGAVA a letra acentuada ("Pokémon" -> "pokmon"),
  /// entao ela nunca casava com "Pokemon". Transliterar resolve os dois lados.
  static const _comAcento = 'áàâãäåÁÀÂÃÄÅéèêëÉÈÊËíìîïÍÌÎÏóòôõöÓÒÔÕÖúùûüÚÙÛÜçÇñÑýÿÝ';
  static const _semAcento = 'aaaaaaAAAAAAeeeeEEEEiiiiIIIIoooooOOOOOuuuuUUUUcCnNyyY';
  static String _tirarAcento(String s) {
    final b = StringBuffer();
    for (final ch in s.split('')) {
      final i = _comAcento.indexOf(ch);
      b.write(i == -1 ? ch : _semAcento[i]);
    }
    return b.toString();
  }

  /// Normaliza para comparacao: sem acento, minusculo, sem pontuacao, espacos
  /// simples.
  static String _norm(String s) => _tirarAcento(s)
      .toLowerCase()
      .replaceAll(RegExp(r'[._]'), ' ')
      .replaceAll(RegExp(r"[^\w\s]"), '')
      .replaceAll(RegExp(r'\s+'), ' ')
      .trim();
}
