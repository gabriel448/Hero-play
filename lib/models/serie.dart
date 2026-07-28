import 'canal.dart';

/// Resultado de agrupar canais VOD em filmes puros e series.
class AgrupamentoConteudo {
  final List<Canal> filmes;
  final List<Serie> series;
  const AgrupamentoConteudo({required this.filmes, required this.series});
}

/// Representa uma serie agrupada com todos os seus episodios.
class Serie {
  final String nome;
  final String? logoUrl;
  final String grupo;
  final List<Canal> episodios;

  const Serie({
    required this.nome,
    required this.logoUrl,
    required this.grupo,
    required this.episodios,
  });

  // Detecta SxxExx (caso insensitivo) ou formato alternativo 1x01.
  static final _reEp =
      RegExp(r'\bS(\d{1,2})\s?E(\d{1,3})\b', caseSensitive: false);
  static final _reEp2 = RegExp(r'\b(\d{1,2})x(\d{2,3})\b');

  /// Extrai e limpa o nome da serie do nome de um episodio.
  /// Retorna null se o canal nao parece ser episodio de serie.
  static String? nomeSerie(String nomeCanal) {
    final m = _reEp.firstMatch(nomeCanal) ?? _reEp2.firstMatch(nomeCanal);
    if (m == null) return null;
    final raw = nomeCanal
        .substring(0, m.start)
        .trim()
        .replaceAll(RegExp(r'[-–:|\s]+$'), '')
        .trim();
    final nome = _limparNome(raw);
    return nome.isEmpty ? null : nome;
  }

  /// Limpa ruido tipico de nomes IPTV para exibicao e busca uniforme.
  /// Remove tags de idioma, qualidade, pontos/underscores como separadores.
  static String _limparNome(String nome) => nome
      // Tags de idioma: [EN], [PT], [PT-BR], (US), (ESP), etc.
      .replaceAll(
          RegExp(r'[\[\(][A-Za-z]{2,5}(?:[\-\s][A-Za-z]{2,3})?[\]\)]'), '')
      // Qualidade: [HD], [4K], [1080p], (720p), etc.
      .replaceAll(
          RegExp(r'[\[\(](?:\d{3,4}[pi]|4K|HD|FHD|UHD)[\]\)]',
              caseSensitive: false),
          '')
      // Ano isolado: (2019), [2019]
      .replaceAll(RegExp(r'[\[\(]\d{4}[\]\)]'), '')
      // Pontos e underscores viram espacos (The.Boys -> The Boys)
      .replaceAll(RegExp(r'[._]'), ' ')
      // Espacos multiplos
      .replaceAll(RegExp(r'\s+'), ' ')
      .trim();

  static int seasonOf(Canal c) {
    final m = _reEp.firstMatch(c.nome) ?? _reEp2.firstMatch(c.nome);
    return int.tryParse(m?.group(1) ?? '0') ?? 0;
  }

  static int episodeOf(Canal c) {
    final m = _reEp.firstMatch(c.nome) ?? _reEp2.firstMatch(c.nome);
    return int.tryParse(m?.group(2) ?? '0') ?? 0;
  }

  /// Formata o label do episodio: "E05 – Subtitulo" ou apenas "E05".
  static String episodeLabel(Canal c) {
    final m = _reEp.firstMatch(c.nome);
    if (m == null) return c.nome;
    final eNum =
        'E${(int.tryParse(m.group(2) ?? '0') ?? 0).toString().padLeft(2, '0')}';
    final rest = c.nome
        .substring(m.end)
        .trim()
        .replaceAll(RegExp(r'^[-–:|\s]+'), '');
    return rest.isEmpty ? eNum : '$eNum – $rest';
  }

  /// Chave de comparacao: minusculo e sem acento, para dedup e agrupamento
  /// ("Round 6" e "round 6" sao a MESMA serie; "Ação" e "Acao", o mesmo filme).
  static const _comAcento = 'áàâãäåÁÀÂÃÄÅéèêëÉÈÊËíìîïÍÌÎÏóòôõöÓÒÔÕÖúùûüÚÙÛÜçÇñÑ';
  static const _semAcento = 'aaaaaaAAAAAAeeeeEEEEiiiiIIIIoooooOOOOOuuuuUUUUcCnN';
  static String chaveNome(String s) {
    final b = StringBuffer();
    for (final ch in s.trim().toLowerCase().split('')) {
      final i = _comAcento.indexOf(ch);
      b.write(i == -1 ? ch : _semAcento[i].toLowerCase());
    }
    return b.toString().replaceAll(RegExp(r'\s+'), ' ');
  }

  /// Agrupa uma lista de canais VOD em filmes puros e series agrupadas.
  ///
  /// Faz DEDUP: a mesma lista costuma repetir o mesmo titulo em varias
  /// categorias (ou em "HD" e "4K") — sem isto aparecem posteres duplicados na
  /// grade. Fica o primeiro que aparece. Mesma regra do app de TV.
  static AgrupamentoConteudo agrupar(List<Canal> canais) {
    final filmes = <Canal>[];
    final filmesVistos = <String>{};
    final map = <String, _Builder>{};

    for (final c in canais) {
      final nome = nomeSerie(c.nome);
      if (nome == null) {
        if (!filmesVistos.add(chaveNome(c.nome))) continue;
        filmes.add(c);
      } else {
        final chave = chaveNome(nome);
        final b = map.putIfAbsent(
          chave,
          () => _Builder(nome: nome, grupo: c.grupo),
        );
        b.episodios.add(c);
        if (b.logoUrl == null && (c.logoUrl?.isNotEmpty ?? false)) {
          b.logoUrl = c.logoUrl;
        }
      }
    }

    final series = map.values.map((b) {
      b.episodios.sort((a, z) {
        final sa = seasonOf(a), sz = seasonOf(z);
        if (sa != sz) return sa.compareTo(sz);
        return episodeOf(a).compareTo(episodeOf(z));
      });
      return Serie(
        nome: b.nome,
        logoUrl: b.logoUrl,
        grupo: b.grupo,
        episodios: List.unmodifiable(b.episodios),
      );
    }).toList()
      ..sort((a, b) => a.nome.compareTo(b.nome));

    return AgrupamentoConteudo(filmes: filmes, series: series);
  }

  int get totalEpisodios => episodios.length;

  int get totalTemporadas =>
      episodios.map(Serie.seasonOf).toSet().length;
}

class _Builder {
  final String nome;
  final String grupo;
  String? logoUrl;
  final List<Canal> episodios = [];
  _Builder({required this.nome, required this.grupo});
}
