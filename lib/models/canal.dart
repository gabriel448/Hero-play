/// Tipo de conteudo do canal IPTV.
///
/// Listas IPTV costumam misturar 3 tipos: transmissoes ao vivo, filmes
/// (VOD - video sob demanda) e series. Aqui simplificamos em duas categorias
/// porque series podem ser tratadas como variantes de filme/vod.
enum TipoCanal {
  /// Stream continuo - canal de TV, radio, evento ao vivo.
  /// URL geralmente termina em .m3u8 ou .ts, ou nao tem extensao.
  aoVivo,

  /// Video sob demanda - filme ou episodio. URL geralmente termina em
  /// .mp4, .mkv, .avi.
  filme,
}

/// Extensoes tipicas de arquivo de VIDEO sob demanda (filme/episodio).
const _extensoesVod = [
  '.mp4',
  '.mkv',
  '.avi',
  '.mov',
  '.flv',
  '.wmv',
  '.webm',
  '.m4v',
];

/// Classifica ao vivo x VOD **so pela URL** — fonte unica da verdade, usada
/// tanto pelo parser quanto ao recarregar do cache ([Canal.fromMap]).
///
/// No Xtream o caminho diz tudo: VOD tem `/movie/` ou `/series/`, ou termina em
/// extensao de video. O resto e AO VIVO.
///
/// NAO usar palavra do `group-title` aqui (era o que fazia canais aparecerem em
/// Filmes): "GLOBOSAT FILMES", "TELECINE" e "CINEMA" sao categorias de CANAIS,
/// nao de VOD. Mesma regra ja aplicada no app de TV (`tv-app/lista.js`).
TipoCanal tipoCanalPorUrl(String url) {
  final q = url.indexOf('?');
  final u = (q == -1 ? url : url.substring(0, q)).toLowerCase();
  // `/vod/` nao existe na regra do app de TV; incluido aqui porque parte dos
  // provedores serve VOD por esse caminho SEM extensao no fim.
  if (u.contains('/movie/') || u.contains('/series/') || u.contains('/vod/')) {
    return TipoCanal.filme;
  }
  for (final ext in _extensoesVod) {
    if (u.endsWith(ext)) return TipoCanal.filme;
  }
  return TipoCanal.aoVivo;
}

/// Representa um canal de IPTV extraido de uma lista M3U.
class Canal {
  /// Nome de exibicao (ex: "Globo HD" ou "Avatar (2009)").
  final String nome;

  /// URL do stream que o player ira reproduzir.
  final String url;

  /// URL do logo/icone do canal (opcional).
  final String? logoUrl;

  /// Grupo/categoria a que o canal pertence.
  final String grupo;

  /// Identificador EPG, util para grade de programacao futura.
  final String? tvgId;

  /// Tipo do conteudo: ao vivo ou filme/VOD.
  final TipoCanal tipo;

  /// Variantes de qualidade do mesmo canal, ordenadas da melhor a pior.
  /// Vazio para canais comuns; com 2+ itens quando o canal foi agrupado.
  /// Cada variante e um [Canal] simples (sem variantes aninhadas).
  final List<Canal> variantes;

  /// Id estavel de um canal agrupado — nao muda ao trocar de qualidade.
  /// null para canais comuns, que usam a [url] como id.
  final String? idGrupo;

  /// Fontes alternativas do mesmo canal (streams de backup com URLs
  /// diferentes). Vazio quando o canal tem apenas uma fonte. Cada entrada
  /// pode ter suas proprias variantes de qualidade.
  final List<Canal> fontes;

  /// Duracao do conteudo em segundos, extraida da linha EXTINF do M3U.
  /// null ou -1 quando o provedor nao informou a duracao real.
  final int? duracaoSegundos;

  const Canal({
    required this.nome,
    required this.url,
    this.logoUrl,
    this.grupo = 'Sem categoria',
    this.tvgId,
    this.tipo = TipoCanal.aoVivo,
    this.variantes = const [],
    this.idGrupo,
    this.fontes = const [],
    this.duracaoSegundos,
  });

  /// Identificador do canal. Para canais agrupados e um id estavel; para
  /// canais comuns e a propria url.
  String get id => idGrupo ?? url;

  /// `true` quando este canal reune 2+ variantes de qualidade.
  bool get agrupado => variantes.length > 1;

  /// `true` quando ha fontes alternativas alem da principal.
  bool get temFontes => fontes.isNotEmpty;

  Map<String, dynamic> toMap() => {
        'nome': nome,
        'url': url,
        'logoUrl': logoUrl,
        'grupo': grupo,
        'tvgId': tvgId,
        'tipo': tipo.name,
        if (variantes.isNotEmpty)
          'variantes': variantes.map((v) => v.toMap()).toList(),
        if (idGrupo != null) 'idGrupo': idGrupo,
        if (fontes.isNotEmpty)
          'fontes': fontes.map((f) => f.toMap()).toList(),
        if (duracaoSegundos != null) 'duracaoSegundos': duracaoSegundos,
      };

  factory Canal.fromMap(Map map) => Canal(
        nome: map['nome'] as String? ?? 'Sem nome',
        url: map['url'] as String,
        logoUrl: map['logoUrl'] as String?,
        grupo: map['grupo'] as String? ?? 'Sem categoria',
        tvgId: map['tvgId'] as String?,
        // Recalcula pela URL em vez de ler o valor salvo: listas que ja estao
        // no cache foram classificadas pela regra ANTIGA (palavra no grupo) e
        // trouxeram canais ao vivo para Filmes. Assim elas se corrigem ao
        // carregar, sem precisar reimportar a lista.
        tipo: tipoCanalPorUrl(map['url'] as String),
        variantes: (map['variantes'] as List?)
                ?.map((m) => Canal.fromMap(m as Map))
                .toList() ??
            const [],
        idGrupo: map['idGrupo'] as String?,
        fontes: (map['fontes'] as List?)
                ?.map((m) => Canal.fromMap(m as Map))
                .toList() ??
            const [],
        duracaoSegundos: map['duracaoSegundos'] as int?,
      );

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is Canal && runtimeType == other.runtimeType && id == other.id;

  @override
  int get hashCode => id.hashCode;
}
