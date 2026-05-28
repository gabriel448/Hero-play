import '../models/canal.dart';

class M3UInvalidoException implements Exception {
  final String mensagem;
  M3UInvalidoException(this.mensagem);

  @override
  String toString() => 'M3U invalido: $mensagem';
}

/// Lançada quando o conteúdo baixado é reconhecido como um formato diferente
/// de M3U Extended (ex.: manifesto HLS, EPG/XMLTV). Tratada pela UI para
/// exibir orientação específica ao usuário em vez de um erro genérico.
class FormatoNaoSuportadoException implements Exception {
  final String mensagem;
  const FormatoNaoSuportadoException(this.mensagem);

  @override
  String toString() => mensagem;
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

  /// Detecta manifesto HLS (streaming adaptativo) pelo cabeçalho.
  /// Manifesto HLS usa tags como #EXT-X-TARGETDURATION, #EXT-X-STREAM-INF,
  /// #EXT-X-MEDIA-SEQUENCE — completamente diferentes do #EXTINF do M3U IPTV.
  static bool _ehManifestoHls(String conteudo) {
    return conteudo.contains('#EXT-X-TARGETDURATION') ||
        conteudo.contains('#EXT-X-STREAM-INF') ||
        conteudo.contains('#EXT-X-MEDIA-SEQUENCE') ||
        conteudo.contains('#EXT-X-VERSION');
  }

  /// Detecta EPG/XMLTV pelo marcador de abertura XML.
  static bool _ehEpgXml(String conteudo) {
    final inicio = conteudo.trimLeft();
    return inicio.startsWith('<?xml') || inicio.startsWith('<tv');
  }

  /// Faz parsing do texto bruto e devolve a lista de canais.
  /// Linhas malformadas individuais sao ignoradas (resilient parsing).
  List<Canal> parse(String conteudo) {
    if (conteudo.trim().isEmpty) {
      throw M3UInvalidoException('Conteudo vazio.');
    }

    // Detecta formatos incompatíveis antes de tentar parsear como M3U.
    if (_ehManifestoHls(conteudo)) {
      throw const FormatoNaoSuportadoException('hls');
    }
    if (_ehEpgXml(conteudo)) {
      throw const FormatoNaoSuportadoException('epg');
    }

    final linhas = conteudo.split(RegExp(r'\r?\n'));
    final canais = <Canal>[];

    String? nomeAtual;
    String? logoAtual;
    String? grupoAtual;
    String? tvgIdAtual;
    int? duracaoAtual;
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
        duracaoAtual = dados.duracao;
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
          duracaoSegundos: (duracaoAtual != null && duracaoAtual > 0)
              ? duracaoAtual
              : null,
        ));
        nomeAtual = null;
        logoAtual = null;
        grupoAtual = null;
        tvgIdAtual = null;
        duracaoAtual = null;
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

    // Extrai o numero de duracao logo apos "#EXTINF:" (ex: "7200" ou "-1").
    final bodyExtinf = linha.substring('#EXTINF:'.length).trimLeft();
    final durStr = bodyExtinf.split(RegExp(r'[\s,]')).first;
    final duracao = int.tryParse(durStr);

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
      duracao: duracao,
    );
  }
}

class _DadosExtinf {
  final String nome;
  final String? logoUrl;
  final String? grupo;
  final String? tvgId;
  final int? duracao;

  _DadosExtinf({
    required this.nome,
    this.logoUrl,
    this.grupo,
    this.tvgId,
    this.duracao,
  });
}
