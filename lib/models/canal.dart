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

  const Canal({
    required this.nome,
    required this.url,
    this.logoUrl,
    this.grupo = 'Sem categoria',
    this.tvgId,
    this.tipo = TipoCanal.aoVivo,
  });

  String get id => url;

  Map<String, dynamic> toMap() => {
        'nome': nome,
        'url': url,
        'logoUrl': logoUrl,
        'grupo': grupo,
        'tvgId': tvgId,
        'tipo': tipo.name,
      };

  factory Canal.fromMap(Map map) => Canal(
        nome: map['nome'] as String? ?? 'Sem nome',
        url: map['url'] as String,
        logoUrl: map['logoUrl'] as String?,
        grupo: map['grupo'] as String? ?? 'Sem categoria',
        tvgId: map['tvgId'] as String?,
        tipo: TipoCanal.values.firstWhere(
          (t) => t.name == map['tipo'],
          orElse: () => TipoCanal.aoVivo,
        ),
      );

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is Canal && runtimeType == other.runtimeType && url == other.url;

  @override
  int get hashCode => url.hashCode;
}
