import 'dart:convert';
import 'package:http/http.dart' as http;

/// Busca posters de series/animes na API publica do TMDB.
///
/// Cache em memoria: cada busca e feita apenas uma vez por sessao.
///
/// Estrategia de match (por ordem de prioridade):
///   1. Correspondencia exata com name ou original_name (top 5 resultados)
///   2. Correspondencia "comeca com" (top 5 resultados)
///   3. Primeiro resultado (mais popular segundo o TMDB)
class TmdbService {
  static const _imgBase = 'https://image.tmdb.org/t/p/w500';

  final String apiKey;
  final _cache = <String, String?>{};

  TmdbService(this.apiKey);

  bool get configurado => apiKey.trim().isNotEmpty;

  /// Retorna URL do poster para o nome da serie, ou null se nao encontrar.
  /// Tenta TV shows primeiro, depois movies (cobre animes e OVAs).
  Future<String?> posterSerie(String nome) async {
    if (!configurado) return null;
    if (_cache.containsKey(nome)) return _cache[nome];

    // Limpeza extra na query: remove residuos que Serie._limparNome pode nao
    // ter visto (ex: nome vem de outro caminho sem passar pelo modelo).
    final query = _prepararQuery(nome);

    final resultado =
        await _buscarMelhor('/3/search/tv', query, 'name', 'original_name') ??
        await _buscarMelhor(
            '/3/search/movie', query, 'title', 'original_title');

    _cache[nome] = resultado;
    return resultado;
  }

  Future<String?> _buscarMelhor(
    String endpoint,
    String query,
    String campoNome,
    String campoOriginal,
  ) async {
    try {
      final uri = Uri.https('api.themoviedb.org', endpoint, {
        'query': query,
        'api_key': apiKey.trim(),
        'language': 'en-US',
        'include_adult': 'false',
      });
      final resp = await http.get(uri).timeout(const Duration(seconds: 6));
      if (resp.statusCode != 200) return null;

      final body = jsonDecode(resp.body) as Map<String, dynamic>;
      final results = (body['results'] as List<dynamic>?) ?? [];
      if (results.isEmpty) return null;

      final queryNorm = _norm(query);
      final queryWords = queryNorm.split(' ').where((w) => w.isNotEmpty).toList();
      Map<String, dynamic>? melhor;

      bool _nomeMatch(Map<String, dynamic> item, bool Function(String) test) {
        final n = _norm(item[campoNome] as String? ?? '');
        final o = _norm(item[campoOriginal] as String? ?? '');
        return test(n) || test(o);
      }

      // 1. Match exato
      for (final r in results.take(10)) {
        final item = r as Map<String, dynamic>;
        if (_nomeMatch(item, (s) => s == queryNorm)) { melhor = item; break; }
      }

      // 2. Match "comeca com"
      if (melhor == null) {
        for (final r in results.take(10)) {
          final item = r as Map<String, dynamic>;
          if (_nomeMatch(item, (s) => s.startsWith(queryNorm))) { melhor = item; break; }
        }
      }

      // 3. Match "contem" — resultado inclui a query como subsequencia de palavras
      if (melhor == null) {
        for (final r in results.take(10)) {
          final item = r as Map<String, dynamic>;
          if (_nomeMatch(item, (s) => s.contains(queryNorm))) { melhor = item; break; }
        }
      }

      // 4. Match por palavras — todas as palavras da query aparecem no resultado
      if (melhor == null && queryWords.length > 1) {
        for (final r in results.take(10)) {
          final item = r as Map<String, dynamic>;
          if (_nomeMatch(item, (s) => queryWords.every(s.contains))) {
            melhor = item;
            break;
          }
        }
      }

      // 5. Fallback: primeiro resultado (mais popular)
      melhor ??= results.first as Map<String, dynamic>;

      final poster = melhor['poster_path'] as String?;
      return poster != null ? '$_imgBase$poster' : null;
    } catch (_) {
      return null;
    }
  }

  /// Garante que a query chegue limpa ao TMDB, mesmo que venha de fora do
  /// pipeline normal de Serie._limparNome.
  static String _prepararQuery(String nome) => nome
      .replaceAll(RegExp(r'[\[\(][A-Za-z]{2,5}(?:[\-\s][A-Za-z]{2,3})?[\]\)]'), '')
      .replaceAll(RegExp(r'[\[\(]\d{4}[\]\)]'), '')
      .replaceAll(RegExp(r'\b(LEG|DUB|VOST|DUAL)\b', caseSensitive: false), '')
      .replaceAll(RegExp(r'[._]'), ' ')
      .replaceAll(RegExp(r'\s+'), ' ')
      .trim();

  /// Normaliza para comparacao:
  /// - minusculo
  /// - pontos e underscores -> espaco (ANTES de remover outros especiais)
  /// - sem pontuacao restante
  /// - espacos simples
  static String _norm(String s) => s
      .toLowerCase()
      .replaceAll(RegExp(r'[._]'), ' ')
      .replaceAll(RegExp(r"[^\w\s]"), '')
      .replaceAll(RegExp(r'\s+'), ' ')
      .trim();
}
