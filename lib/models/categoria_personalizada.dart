import 'canal.dart';

/// Categoria criada pelo usuario para organizar canais do seu jeito.
///
/// Diferente das categorias da lista M3U (que vem do arquivo importado),
/// estas sao montadas a mao e salvas localmente. Guardamos o [Canal]
/// completo — assim a categoria sobrevive mesmo que a lista de origem
/// seja removida.
class CategoriaPersonalizada {
  /// Identificador estavel, gerado na criacao.
  final String id;

  /// Nome escolhido pelo usuario.
  final String nome;

  /// Canais que o usuario adicionou a esta categoria.
  final List<Canal> canais;

  /// Quando a categoria foi criada.
  final DateTime criadaEm;

  const CategoriaPersonalizada({
    required this.id,
    required this.nome,
    required this.canais,
    required this.criadaEm,
  });

  /// Cria uma categoria nova e vazia, com id derivado do instante atual.
  factory CategoriaPersonalizada.nova(String nome) {
    final agora = DateTime.now();
    return CategoriaPersonalizada(
      id: 'cat_${agora.microsecondsSinceEpoch}',
      nome: nome,
      canais: const [],
      criadaEm: agora,
    );
  }

  /// `true` se o canal ja pertence a esta categoria.
  bool contem(Canal canal) => canais.any((c) => c.id == canal.id);

  CategoriaPersonalizada copyWith({String? nome, List<Canal>? canais}) =>
      CategoriaPersonalizada(
        id: id,
        nome: nome ?? this.nome,
        canais: canais ?? this.canais,
        criadaEm: criadaEm,
      );

  Map<String, dynamic> toMap() => {
        'id': id,
        'nome': nome,
        'canais': canais.map((c) => c.toMap()).toList(),
        'criadaEm': criadaEm.toIso8601String(),
      };

  factory CategoriaPersonalizada.fromMap(Map map) => CategoriaPersonalizada(
        id: map['id'] as String,
        nome: map['nome'] as String? ?? 'Categoria',
        canais: (map['canais'] as List?)
                ?.map((m) => Canal.fromMap(m as Map))
                .toList() ??
            const [],
        criadaEm: DateTime.tryParse(map['criadaEm'] as String? ?? '') ??
            DateTime.now(),
      );
}
