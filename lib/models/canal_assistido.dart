import 'canal.dart';

/// Representa um item do historico de canais assistidos.
/// Guardamos o canal completo (e nao so a referencia) porque uma lista
/// pode ser apagada e ainda queremos mostrar o que o usuario assistiu.
class CanalAssistido {
  final Canal canal;

  /// Quando foi a ultima vez que o usuario abriu este canal.
  /// Se o mesmo canal for visto varias vezes, atualizamos esta data.
  final DateTime ultimaVistaEm;

  const CanalAssistido({
    required this.canal,
    required this.ultimaVistaEm,
  });

  Map<String, dynamic> toMap() => {
        'canal': canal.toMap(),
        'ultimaVistaEm': ultimaVistaEm.toIso8601String(),
      };

  factory CanalAssistido.fromMap(Map map) => CanalAssistido(
        canal: Canal.fromMap(map['canal'] as Map),
        ultimaVistaEm:
            DateTime.tryParse(map['ultimaVistaEm'] as String? ?? '') ??
                DateTime.now(),
      );
}