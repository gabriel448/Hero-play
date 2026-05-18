import '../models/canal.dart';

class M3UInvalidoException implements Exception {
  final String mensagem;
  M3UInvalidoException(this.mensagem);

  @override
  String toString() => 'M3U invalido: $mensagem';
}

/// Parser de listas M3U estendidas (formato IPTV).
class ParserM3U {
  /// Regex para extrair atributos no formato chave="valor".
  static final RegExp _regexAtributos = RegExp(r'([\w-]+)="([^"]*)"');

  /// Extensoes tipicas de arquivos de VIDEO sob demanda (filmes/series).
  /// Se a URL termina com uma destas, classificamos como filme.
  static const _extensoesFilme = {
    '.mp4',
    '.mkv',
    '.avi',
    '.mov',
    '.flv',
    '.wmv',
    '.webm',
    '.m4v',
  };

  /// Palavras-chave em group-title que indicam conteudo VOD.
  /// Comparacao e case-insensitive.
  static const _palavrasFilme = [
    'filme',
    'movie',
    'cinema',
    'serie',
    'series',
    'temporada',
    'season',
    'episodio',
    'vod',
  ];

  /// Faz parsing do texto bruto e devolve a lista de canais.
  /// Linhas malformadas individuais sao ignoradas (resilient parsing).
  List<Canal> parse(String conteudo) {
    if (conteudo.trim().isEmpty) {
      throw M3UInvalidoException('Conteudo vazio.');
    }

    final linhas = conteudo.split(RegExp(r'\r?\n'));
    final canais = <Canal>[];

    String? nomeAtual;
    String? logoAtual;
    String? grupoAtual;
    String? tvgIdAtual;
    bool aguardandoUrl = false;

    for (final linhaRaw in linhas) {
      final linha = linhaRaw.trim();
      if (linha.isEmpty) continue;
      if (linha.startsWith('#EXTM3U')) continue;

      if (linha.startsWith('#EXTINF:')) {
        final dados = _parseExtinf(linha);
        nomeAtual = dados.nome;
        logoAtual = dados.logoUrl;
        grupoAtual = dados.grupo;
        tvgIdAtual = dados.tvgId;
        aguardandoUrl = true;
        continue;
      }

      if (linha.startsWith('#')) continue;

      if (aguardandoUrl && nomeAtual != null) {
        final grupo = (grupoAtual?.isEmpty ?? true) ? 'Sem categoria' : grupoAtual!;
        canais.add(Canal(
          nome: nomeAtual,
          url: linha,
          logoUrl: logoAtual,
          grupo: grupo,
          tvgId: tvgIdAtual,
          tipo: _classificarTipo(url: linha, grupo: grupo),
        ));
        nomeAtual = null;
        logoAtual = null;
        grupoAtual = null;
        tvgIdAtual = null;
        aguardandoUrl = false;
      }
    }

    if (canais.isEmpty) {
      throw M3UInvalidoException(
        'Nenhum canal valido encontrado. Verifique se o arquivo e uma lista M3U.',
      );
    }

    return canais;
  }

  /// Determina se um canal e VOD (filme) ou stream ao vivo.
  /// Heuristica:
  ///  1. Se a URL termina com extensao de arquivo de video -> filme.
  ///  2. Se o group-title contem palavras-chave de VOD -> filme.
  ///  3. Caso contrario -> ao vivo (padrao para IPTV).
  TipoCanal _classificarTipo({required String url, required String grupo}) {
    final urlLower = url.toLowerCase();

    // 1) Detecta pela extensao da URL. Removemos querystring antes.
    final urlSemQuery = urlLower.split('?').first;
    for (final ext in _extensoesFilme) {
      if (urlSemQuery.endsWith(ext)) return TipoCanal.filme;
    }

    // 2) Detecta por palavras-chave no nome do grupo.
    final grupoLower = grupo.toLowerCase();
    for (final palavra in _palavrasFilme) {
      if (grupoLower.contains(palavra)) return TipoCanal.filme;
    }

    return TipoCanal.aoVivo;
  }

  _DadosExtinf _parseExtinf(String linha) {
    final indexVirgula = linha.indexOf(',');
    String nome = 'Sem nome';
    String antesVirgula = linha;

    if (indexVirgula != -1) {
      nome = linha.substring(indexVirgula + 1).trim();
      antesVirgula = linha.substring(0, indexVirgula);
    }

    final atributos = <String, String>{};
    for (final match in _regexAtributos.allMatches(antesVirgula)) {
      final chave = match.group(1)!.toLowerCase();
      final valor = match.group(2) ?? '';
      atributos[chave] = valor;
    }

    return _DadosExtinf(
      nome: nome,
      logoUrl: atributos['tvg-logo'],
      grupo: atributos['group-title'],
      tvgId: atributos['tvg-id'],
    );
  }
}

class _DadosExtinf {
  final String nome;
  final String? logoUrl;
  final String? grupo;
  final String? tvgId;

  _DadosExtinf({
    required this.nome,
    this.logoUrl,
    this.grupo,
    this.tvgId,
  });
}
