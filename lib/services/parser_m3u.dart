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
          tipo: tipoCanalPorUrl(linha),
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

  _DadosExtinf _parseExtinf(String linha) {
    // A virgula separadora e a 1a FORA de aspas. Valores de atributo podem ter
    // virgula (ex.: tvg-name="MEU FILHO, NOSSO MUNDO") — um indexOf(',') simples
    // cortava no meio do atributo e jogava o resto da linha no nome.
    var indexVirgula = -1;
    var dentroDeAspas = false;
    for (var i = 0; i < linha.length; i++) {
      final ch = linha[i];
      if (ch == '"') {
        dentroDeAspas = !dentroDeAspas;
      } else if (ch == ',' && !dentroDeAspas) {
        indexVirgula = i;
        break;
      }
    }
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
