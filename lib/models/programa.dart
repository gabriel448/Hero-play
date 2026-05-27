/// Um programa da grade de TV (EPG/XMLTV).
///
/// Vem do XMLTV: `<programme start="..." stop="..." channel="...">`.
/// O `tvgId` corresponde ao atributo `tvg-id` do canal na lista M3U.
class Programa {
  /// Id do canal (igual ao tvg-id do EXTINF). Usado para juntar com [Canal].
  final String tvgId;

  /// Inicio e fim do programa, em UTC apos parsing.
  final DateTime inicio;
  final DateTime fim;

  /// Titulo / nome do programa.
  final String titulo;

  /// Descricao / sinopse, opcional.
  final String? descricao;

  const Programa({
    required this.tvgId,
    required this.inicio,
    required this.fim,
    required this.titulo,
    this.descricao,
  });

  /// `true` se o programa esta em exibicao agora (entre inicio e fim).
  bool ehAtual([DateTime? agora]) {
    final ref = agora ?? DateTime.now();
    return !ref.isBefore(inicio) && ref.isBefore(fim);
  }

  /// `true` se o programa ainda nao começou.
  bool ehFuturo([DateTime? agora]) {
    final ref = agora ?? DateTime.now();
    return inicio.isAfter(ref);
  }

  /// Duracao do programa.
  Duration get duracao => fim.difference(inicio);

  Map<String, dynamic> toMap() => {
        'tvgId': tvgId,
        'inicio': inicio.toIso8601String(),
        'fim': fim.toIso8601String(),
        'titulo': titulo,
        if (descricao != null) 'descricao': descricao,
      };

  factory Programa.fromMap(Map map) => Programa(
        tvgId: map['tvgId'] as String,
        inicio: DateTime.parse(map['inicio'] as String),
        fim: DateTime.parse(map['fim'] as String),
        titulo: map['titulo'] as String? ?? 'Sem titulo',
        descricao: map['descricao'] as String?,
      );
}
