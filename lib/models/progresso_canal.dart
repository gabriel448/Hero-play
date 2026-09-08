class ProgressoCanal {
  final String url;
  final int posicaoSeg;
  final int? duracaoSeg;
  final DateTime atualizadoEm;

  /// `true` quando o episodio foi assistido ate o fim (>=90%). Serve para a
  /// serie CONTINUAR aparecendo em "Continuar assistindo" apontando para o
  /// proximo episodio — antes o progresso era simplesmente apagado e a serie
  /// sumia da fila. Filme concluido continua sendo apagado (nao ha "proximo").
  final bool concluido;

  const ProgressoCanal({
    required this.url,
    required this.posicaoSeg,
    this.duracaoSeg,
    required this.atualizadoEm,
    this.concluido = false,
  });

  /// Fração assistida (0.0–1.0). Zero quando duração desconhecida.
  double get fracao => (duracaoSeg != null && duracaoSeg! > 0)
      ? (posicaoSeg / duracaoSeg!).clamp(0.0, 1.0)
      : 0.0;

  Map<String, dynamic> toMap() => {
        'url': url,
        'posicaoSeg': posicaoSeg,
        if (duracaoSeg != null) 'duracaoSeg': duracaoSeg,
        'atualizadoEm': atualizadoEm.toIso8601String(),
        if (concluido) 'concluido': true,
      };

  factory ProgressoCanal.fromMap(Map map) => ProgressoCanal(
        url: map['url'] as String,
        posicaoSeg: (map['posicaoSeg'] as num).toInt(),
        duracaoSeg: map['duracaoSeg'] != null
            ? (map['duracaoSeg'] as num).toInt()
            : null,
        atualizadoEm: DateTime.parse(map['atualizadoEm'] as String),
        concluido: (map['concluido'] as bool?) ?? false,
      );
}
