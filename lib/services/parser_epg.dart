import '../models/programa.dart';

class EpgInvalidoException implements Exception {
  final String mensagem;
  EpgInvalidoException(this.mensagem);

  @override
  String toString() => 'EPG invalido: $mensagem';
}

/// Parser de guia de programacao XMLTV.
///
/// Formato esperado:
/// ```xml
/// <?xml version="1.0" encoding="UTF-8"?>
/// <tv>
///   <programme start="20260525150000 -0300" stop="20260525160000 -0300"
///              channel="cnnbrasil.br">
///     <title lang="pt">Jornal CNN</title>
///     <desc lang="pt">Resumo das principais noticias.</desc>
///   </programme>
/// </tv>
/// ```
///
/// Evitamos a dependencia de uma lib de XML porque XMLTV tem estrutura
/// bem definida e plana; regex e suficiente e e ate ordem de magnitude
/// mais rapido para arquivos de 30MB+.
class ParserEpg {
  // Captura `<programme ... >...</programme>` (com flag dotAll/multiline).
  static final RegExp _regProgramme = RegExp(
    r'<programme\s+([^>]*?)>([\s\S]*?)</programme>',
    multiLine: true,
  );

  // Captura atributos no formato chave="valor".
  static final RegExp _regAtributos = RegExp(r'([\w-]+)="([^"]*)"');

  // Captura `<title>...</title>` (e variantes com atributos).
  static final RegExp _regTitulo = RegExp(
    r'<title(?:\s[^>]*)?>([\s\S]*?)</title>',
  );

  // Captura `<desc>...</desc>`.
  static final RegExp _regDesc = RegExp(
    r'<desc(?:\s[^>]*)?>([\s\S]*?)</desc>',
  );

  /// Parseia uma string XMLTV e devolve um mapa `tvgId -> List<Programa>`,
  /// com os programas ja ordenados por inicio (mais antigo primeiro).
  ///
  /// Lanca [EpgInvalidoException] se o conteudo nao parece ser XMLTV.
  Map<String, List<Programa>> parse(String conteudo) {
    if (conteudo.trim().isEmpty) {
      throw EpgInvalidoException('Conteudo vazio.');
    }
    final cabecalho = conteudo.trimLeft();
    final ehXmltv = cabecalho.startsWith('<?xml') ||
        cabecalho.startsWith('<tv') ||
        cabecalho.contains('<programme');
    if (!ehXmltv) {
      throw EpgInvalidoException(
        'Arquivo nao parece ser XMLTV (esperado <tv> ou <programme>).',
      );
    }

    final mapa = <String, List<Programa>>{};

    for (final m in _regProgramme.allMatches(conteudo)) {
      final atributosTexto = m.group(1) ?? '';
      final corpo = m.group(2) ?? '';

      String? start;
      String? stop;
      String? channel;
      for (final a in _regAtributos.allMatches(atributosTexto)) {
        final chave = a.group(1)!.toLowerCase();
        final valor = a.group(2) ?? '';
        switch (chave) {
          case 'start':
            start = valor;
            break;
          case 'stop':
            stop = valor;
            break;
          case 'channel':
            channel = valor;
            break;
        }
      }
      if (start == null || stop == null || channel == null) continue;
      if (channel.isEmpty) continue;

      final inicio = _parseDataXmltv(start);
      final fim = _parseDataXmltv(stop);
      if (inicio == null || fim == null) continue;
      if (!fim.isAfter(inicio)) continue;

      final tituloRaw = _regTitulo.firstMatch(corpo)?.group(1);
      final titulo = _limparTexto(tituloRaw ?? '');
      if (titulo.isEmpty) continue;

      final descRaw = _regDesc.firstMatch(corpo)?.group(1);
      final descricao = descRaw != null ? _limparTexto(descRaw) : null;

      final p = Programa(
        tvgId: channel,
        inicio: inicio,
        fim: fim,
        titulo: titulo,
        descricao: (descricao?.isEmpty ?? true) ? null : descricao,
      );

      mapa.putIfAbsent(channel, () => []).add(p);
    }

    // Ordena cada canal por inicio. Necessario porque alguns provedores
    // emitem programas fora de ordem.
    for (final lista in mapa.values) {
      lista.sort((a, b) => a.inicio.compareTo(b.inicio));
    }

    return mapa;
  }

  /// Parseia uma data no formato XMLTV: `YYYYMMDDhhmmss [+/-ZZZZ]`.
  /// O timezone e opcional; quando ausente, assume UTC (recomendacao XMLTV).
  static DateTime? _parseDataXmltv(String raw) {
    final texto = raw.trim();
    if (texto.length < 14) return null;
    final ano = int.tryParse(texto.substring(0, 4));
    final mes = int.tryParse(texto.substring(4, 6));
    final dia = int.tryParse(texto.substring(6, 8));
    final hora = int.tryParse(texto.substring(8, 10));
    final minuto = int.tryParse(texto.substring(10, 12));
    final segundo = int.tryParse(texto.substring(12, 14));
    if ([ano, mes, dia, hora, minuto, segundo].any((v) => v == null)) {
      return null;
    }

    // Constroi DateTime em UTC primeiro e depois aplica o offset.
    final base = DateTime.utc(ano!, mes!, dia!, hora!, minuto!, segundo!);
    if (texto.length < 19) return base; // sem timezone -> UTC

    final tz = texto.substring(14).trim();
    final sinal = tz.startsWith('-') ? -1 : 1;
    final corpo = tz.replaceFirst(RegExp(r'^[+-]'), '');
    if (corpo.length < 4) return base;
    final horaTz = int.tryParse(corpo.substring(0, 2));
    final minTz = int.tryParse(corpo.substring(2, 4));
    if (horaTz == null || minTz == null) return base;

    // O offset informado e "este horario local = UTC + offset".
    // Logo, para converter para UTC subtraimos o offset.
    final offset = Duration(hours: horaTz, minutes: minTz) * sinal;
    return base.subtract(offset);
  }

  /// Remove tags internas, CDATA, e desfaz entidades comuns.
  static String _limparTexto(String texto) {
    var t = texto;
    // CDATA
    t = t.replaceAll(RegExp(r'<!\[CDATA\['), '');
    t = t.replaceAll(']]>', '');
    // Tags internas (por exemplo <em>) — para EPG sao raros, removemos.
    t = t.replaceAll(RegExp(r'<[^>]+>'), '');
    // Entidades XML
    t = t
        .replaceAll('&amp;', '&')
        .replaceAll('&lt;', '<')
        .replaceAll('&gt;', '>')
        .replaceAll('&quot;', '"')
        .replaceAll('&apos;', "'")
        .replaceAll('&#39;', "'");
    return t.trim();
  }
}
