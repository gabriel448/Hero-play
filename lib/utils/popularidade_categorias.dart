/// Ranking de popularidade de categorias de canais ao vivo.
///
/// Listas IPTV vem com categorias de nomes variaveis ("GLOBOS | CAPITAIS",
/// "Globo Capitais", "REDE GLOBO CAPITAIS"). Para ordenar por popularidade
/// independente da grafia, normalizamos o nome (sem acento, maiusculo, sem
/// pontuacao) e checamos por substrings (tokens) caracteristicos.
///
/// Cada regra tem uma posicao (menor = mais popular) e uma lista de tokens
/// que TODOS devem aparecer no nome normalizado para casar. As regras com
/// mais tokens sao checadas primeiro (mais especificas vencem).
library;

class _RegraPopularidade {
  final int posicao;
  final List<String> tokens;
  const _RegraPopularidade(this.posicao, this.tokens);
}

const _regras = <_RegraPopularidade>[
  // 🔥 Muito populares
  _RegraPopularidade(1, ['ESPORTE']),
  _RegraPopularidade(2, ['ESPORTE', 'PAYPERVIEW']),
  _RegraPopularidade(2, ['ESPORTE', 'PPV']),
  _RegraPopularidade(3, ['PREMIERE', 'ESPORTE']),
  _RegraPopularidade(4, ['ABERTO']),
  _RegraPopularidade(5, ['SPORTS', 'WORLD']),
  _RegraPopularidade(6, ['UFC']),
  _RegraPopularidade(6, ['BJJ']),
  // 📺 Populares
  _RegraPopularidade(10, ['GLOBO', 'CAPITAI']),
  _RegraPopularidade(11, ['GLOBO', 'SUDESTE']),
  _RegraPopularidade(12, ['GLOBO', 'SUL']),
  _RegraPopularidade(13, ['GLOBO', 'NORDESTE']),
  _RegraPopularidade(14, ['GLOBO', 'NORTE']),
  _RegraPopularidade(15, ['GLOBO', 'CENTRO']),
  _RegraPopularidade(16, ['GLOBO']),
  _RegraPopularidade(17, ['HBO', 'MAX', 'PPV']),
  _RegraPopularidade(18, ['HBO']),
  _RegraPopularidade(19, ['RECORD']),
  _RegraPopularidade(20, ['SBT']),
  _RegraPopularidade(21, ['BAND']),
  // 🎬 Moderadamente populares
  _RegraPopularidade(30, ['ESTADOS', 'UNIDOS']),
  _RegraPopularidade(30, ['EUA']),
  _RegraPopularidade(31, ['ESPECIAI', '24']),
  _RegraPopularidade(32, ['NOTICIA']),
  _RegraPopularidade(33, ['VARIEDADE']),
  _RegraPopularidade(34, ['PARAMOUNT']),
  _RegraPopularidade(35, ['PRIME', 'VIDEO']),
  _RegraPopularidade(36, ['DISNEY']),
  _RegraPopularidade(37, ['DESENHO']),
  _RegraPopularidade(38, ['INFANTI']),
  _RegraPopularidade(38, ['KIDS']),
  _RegraPopularidade(39, ['DOCUMENT']),
  _RegraPopularidade(40, ['PORTUGAL']),
  _RegraPopularidade(41, ['CANADA']),
  _RegraPopularidade(42, ['ANIME']),
  _RegraPopularidade(43, ['LEGENDADO']),
  _RegraPopularidade(44, ['CLIP', 'MUSICA']),
  _RegraPopularidade(45, ['MUSICA']),
  _RegraPopularidade(45, ['MUSIC']),
  _RegraPopularidade(46, ['RELIGIO']),
  _RegraPopularidade(46, ['GOSPEL']),
  // 📉 Menos populares
  _RegraPopularidade(60, ['YOUTUBER']),
  _RegraPopularidade(61, ['CASA', 'PATRAO']),
  _RegraPopularidade(62, ['LATINO']),
  _RegraPopularidade(63, ['ESTADUA']),
  _RegraPopularidade(64, ['EUROPA']),
];

/// Lista de regras ordenadas por especificidade (mais tokens primeiro) para
/// que matches mais especificos vencam matches genericos. Calculada uma vez
/// na primeira chamada.
List<_RegraPopularidade>? _regrasOrdenadas;

List<_RegraPopularidade> _obterRegrasOrdenadas() {
  return _regrasOrdenadas ??= ([..._regras]
    ..sort((a, b) => b.tokens.length.compareTo(a.tokens.length)));
}

/// Remove acentos, deixa em maiusculo e tira pontuacao/espacos.
/// "GLOBOS | CAPITAIS" -> "GLOBOSCAPITAIS".
String _normalizar(String s) {
  // Mapa simples de transliteracao — suficiente para nomes em portugues.
  const acentos = {
    'á': 'a', 'à': 'a', 'â': 'a', 'ã': 'a', 'ä': 'a',
    'é': 'e', 'è': 'e', 'ê': 'e', 'ë': 'e',
    'í': 'i', 'ì': 'i', 'î': 'i', 'ï': 'i',
    'ó': 'o', 'ò': 'o', 'ô': 'o', 'õ': 'o', 'ö': 'o',
    'ú': 'u', 'ù': 'u', 'û': 'u', 'ü': 'u',
    'ç': 'c', 'ñ': 'n',
    'Á': 'A', 'À': 'A', 'Â': 'A', 'Ã': 'A', 'Ä': 'A',
    'É': 'E', 'È': 'E', 'Ê': 'E', 'Ë': 'E',
    'Í': 'I', 'Ì': 'I', 'Î': 'I', 'Ï': 'I',
    'Ó': 'O', 'Ò': 'O', 'Ô': 'O', 'Õ': 'O', 'Ö': 'O',
    'Ú': 'U', 'Ù': 'U', 'Û': 'U', 'Ü': 'U',
    'Ç': 'C', 'Ñ': 'N',
  };
  final buffer = StringBuffer();
  for (final ch in s.split('')) {
    final mapped = acentos[ch] ?? ch;
    final code = mapped.codeUnitAt(0);
    final isLetter = (code >= 65 && code <= 90) || (code >= 97 && code <= 122);
    final isDigit = code >= 48 && code <= 57;
    if (isLetter || isDigit) buffer.write(mapped.toUpperCase());
  }
  return buffer.toString();
}

/// Posicao da categoria no ranking de popularidade. Categorias sem regra
/// casando recebem [naoRankeada] (ficam por ultimo entre as populares mas
/// ANTES de qualquer outra categoria desconhecida ordenada por nome).
const int naoRankeada = 9999;

int rankPopularidade(String nomeCategoria) {
  final n = _normalizar(nomeCategoria);
  for (final r in _obterRegrasOrdenadas()) {
    if (r.tokens.every((t) => n.contains(_normalizar(t)))) return r.posicao;
  }
  return naoRankeada;
}

/// Ordena uma lista de nomes de categoria por popularidade, depois por nome
/// quando o rank empata (caso comum: varias categorias sem match).
List<String> ordenarPorPopularidade(Iterable<String> nomes) {
  final lista = nomes.toList();
  lista.sort((a, b) {
    final ra = rankPopularidade(a);
    final rb = rankPopularidade(b);
    if (ra != rb) return ra.compareTo(rb);
    return a.toLowerCase().compareTo(b.toLowerCase());
  });
  return lista;
}