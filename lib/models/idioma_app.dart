/// Idiomas suportados pelo app.
///
/// O [codigo] segue o formato BCP-47 que o TMDB espera no parametro
/// `language` — e tambem serve de locale interno do app.
enum IdiomaApp {
  portugues('pt-BR', 'Português', 'Brasil'),
  ingles('en-US', 'English', 'United States'),
  espanhol('es-ES', 'Español', 'España');

  final String codigo;
  final String nome;
  final String regiao;

  const IdiomaApp(this.codigo, this.nome, this.regiao);

  /// Resolve um [IdiomaApp] a partir do codigo salvo. Retorna null se o
  /// codigo for desconhecido ou nulo (ex.: usuario ainda nao escolheu).
  static IdiomaApp? porCodigo(String? codigo) {
    for (final idioma in IdiomaApp.values) {
      if (idioma.codigo == codigo) return idioma;
    }
    return null;
  }

  /// Tokens usados para casar a FAIXA DE AUDIO deste idioma. Os players IPTV
  /// rotulam as faixas de varias formas no `language`/`title` do media_kit
  /// (ex.: "por", "POR", "Portuguese", "POB", "Dual"...). Comparacao em minusculo:
  /// codigo curto (2-3 letras) e comparado por igualdade ao `language`; tokens
  /// maiores sao buscados por "contem" no `language`+`title`.
  List<String> get tokensAudio {
    switch (this) {
      case IdiomaApp.portugues:
        return [
          'pt',
          'por',
          'pob',
          'pt-br',
          'ptb',
          'portugues',
          'portuguese',
          'brasil',
          'brazil',
        ];
      case IdiomaApp.ingles:
        return ['en', 'eng', 'english', 'ingles'];
      case IdiomaApp.espanhol:
        return [
          'es',
          'spa',
          'esp',
          'spanish',
          'espanol',
          'castellano',
          'latino',
          'lat',
        ];
    }
  }
}
