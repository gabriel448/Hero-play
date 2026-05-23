/// Deteccao e normalizacao de qualidade de canais IPTV.
///
/// Listas IPTV costumam repetir o mesmo canal em varias resolucoes, marcando
/// a qualidade no nome ("Globo Minas HD", "Globo Minas FHD"). Este modulo
/// detecta essa qualidade e remove as tags para obter o nome-base do canal,
/// permitindo agrupar as variantes.
library;

/// Qualidade de video de um canal, da melhor para a pior.
enum Qualidade { uhd, fhd, hd, sd, desconhecida }

extension QualidadeX on Qualidade {
  /// Rank numerico — maior e melhor. Usado para ordenar variantes.
  int get rank {
    switch (this) {
      case Qualidade.uhd:
        return 4;
      case Qualidade.fhd:
        return 3;
      case Qualidade.hd:
        return 2;
      case Qualidade.sd:
        return 1;
      case Qualidade.desconhecida:
        return 0;
    }
  }

  /// Rotulo curto para exibicao na UI.
  String get rotulo {
    switch (this) {
      case Qualidade.uhd:
        return '4K';
      case Qualidade.fhd:
        return 'FHD';
      case Qualidade.hd:
        return 'HD';
      case Qualidade.sd:
        return 'SD';
      case Qualidade.desconhecida:
        return 'Padrao';
    }
  }
}

// Regexes de deteccao — uma por faixa de qualidade, da melhor para a pior.
// \b garante limite de palavra: "HD" nao casa dentro de "FHD"/"UHD".
final _regexUhd = RegExp(r'\b(4K|UHD|2160P?|ULTRA\s?HD)\b', caseSensitive: false);
final _regexFhd = RegExp(r'\b(FHD|FULL\s?HD|1080P?)\b', caseSensitive: false);
final _regexHd = RegExp(r'\b(HD|HDTV|720P?)\b', caseSensitive: false);
final _regexSd = RegExp(r'\b(SD|480P?|360P?)\b', caseSensitive: false);

/// Todas as tags removidas do nome para obter o nome-base. Inclui tags de
/// resolucao e de codec (H265/HEVC...), que aparecem como variantes mas nao
/// indicam resolucao.
final _regexTags = RegExp(
  r'\b(4K|UHD|2160P?|ULTRA\s?HD|FHD|FULL\s?HD|1080P?|HDTV|HD|720P?|'
  r'SD|480P?|360P?|H\.?265|HEVC|H\.?264|AVC)\b',
  caseSensitive: false,
);

final _regexParenteses = RegExp(r'[\[\]\(\)]');
final _regexEspacos = RegExp(r'\s+');
// Separadores soltos nas pontas, junto de espacos: "Globo - ", "| Globo".
final _regexBordas = RegExp(r'^[\s\-|•·:]+|[\s\-|•·:]+$');

/// Detecta a qualidade a partir do nome do canal.
Qualidade detectarQualidade(String texto) {
  if (_regexUhd.hasMatch(texto)) return Qualidade.uhd;
  if (_regexFhd.hasMatch(texto)) return Qualidade.fhd;
  if (_regexHd.hasMatch(texto)) return Qualidade.hd;
  if (_regexSd.hasMatch(texto)) return Qualidade.sd;
  return Qualidade.desconhecida;
}

/// Nome do canal sem as tags de qualidade. "Globo Minas HD" -> "Globo Minas".
/// Numeros (ex.: "ESPN 2") sao preservados — sao canais distintos.
String nomeBase(String nome) => _semTags(nome);

/// Categoria sem tags de qualidade. "CANAIS FHD" -> "CANAIS".
/// Funde categorias que so diferem pela qualidade.
String categoriaBase(String grupo) => _semTags(grupo);

String _semTags(String texto) {
  var s = texto.replaceAll(_regexTags, ' ');
  s = s.replaceAll(_regexParenteses, ' ');
  s = s.replaceAll(_regexEspacos, ' ');
  s = s.replaceAll(_regexBordas, '');
  return s.isEmpty ? texto.trim() : s;
}
