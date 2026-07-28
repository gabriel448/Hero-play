import 'dart:math';

/// Um perfil de uso dentro de uma conta (ou do modo local).
///
/// Cada perfil tem a sua propria configuracao (idioma, ajuste automatico de
/// qualidade, ordenacoes) e a sua propria biblioteca pessoal (favoritos,
/// historico, continuar assistindo, "minha lista", categorias) — esta ultima
/// fica isolada em boxes proprias do Hive por id de perfil, ver
/// [Armazenamento.ativarPerfil].
///
/// As LISTAS M3U sao sempre compartilhadas entre todos os perfis (decisao de
/// produto: evita acesso simultaneo multiplo a mesma fonte, que costuma ser
/// bloqueado pelos provedores). Por isso o limite de [maxPerfis] perfis.
///
/// As ordenacoes sao guardadas como String crua (a `key` dos enums em
/// `preferencias_provider.dart`) para o model nao depender da camada de estado.
class Perfil {
  /// Numero maximo de perfis por conta.
  static const int maxPerfis = 3;

  /// Identificador estavel (uuid v4). Compartilhado com a linha na nuvem.
  final String id;

  /// Nome escolhido pelo usuario.
  final String nome;

  /// Chave do avatar (placeholder). Casa com um arquivo em assets/avatars/.
  final String icone;

  /// Idioma BCP-47 (ex.: 'pt-BR'). `null` cai no padrao (portugues).
  final String? idioma;

  /// Ajuste automatico de qualidade ligado para este perfil.
  final bool autoQualidade;

  /// Ordenacao da lista de categorias ao vivo ('popularidade' | 'az').
  final String ordemCategorias;

  /// Ordenacao dos canais dentro de uma categoria ('padrao' | 'az').
  final String ordemCanais;

  /// PIN de 4 digitos do controle dos pais. `null` = controle desligado.
  /// Guardado em texto puro de proposito: e uma trava de conveniencia contra
  /// crianca, nao um segredo — igual ao app de TV. Nunca sai do aparelho.
  final String? pin;

  /// Categorias (group-title da lista) bloqueadas para este perfil.
  final List<String> categoriasBloqueadas;

  /// Quando o perfil foi criado.
  final DateTime criadoEm;

  const Perfil({
    required this.id,
    required this.nome,
    required this.icone,
    this.idioma,
    this.autoQualidade = false,
    this.ordemCategorias = 'popularidade',
    this.ordemCanais = 'padrao',
    this.pin,
    this.categoriasBloqueadas = const [],
    required this.criadoEm,
  });

  /// `true` quando o controle dos pais esta configurado neste perfil.
  bool get temControleParental => pin != null && pin!.isNotEmpty;

  /// Cria um perfil novo com id gerado. As preferencias herdam os valores
  /// passados (usado para o 1o perfil adotar as preferencias legadas do app).
  factory Perfil.novo({
    required String nome,
    required String icone,
    String? idioma,
    bool autoQualidade = false,
    String ordemCategorias = 'popularidade',
    String ordemCanais = 'padrao',
  }) {
    return Perfil(
      id: _gerarUuid(),
      nome: nome,
      icone: icone,
      idioma: idioma,
      autoQualidade: autoQualidade,
      ordemCategorias: ordemCategorias,
      ordemCanais: ordemCanais,
      criadoEm: DateTime.now(),
    );
  }

  Perfil copyWith({
    String? nome,
    String? icone,
    String? idioma,
    bool? autoQualidade,
    String? ordemCategorias,
    String? ordemCanais,
    List<String>? categoriasBloqueadas,
    // `pin` usa sentinela porque null aqui significa "APAGAR o pin" (desligar
    // o controle), e nao "nao mexer".
    Object? pin = naoMexer,
  }) {
    return Perfil(
      id: id,
      nome: nome ?? this.nome,
      icone: icone ?? this.icone,
      idioma: idioma ?? this.idioma,
      autoQualidade: autoQualidade ?? this.autoQualidade,
      ordemCategorias: ordemCategorias ?? this.ordemCategorias,
      ordemCanais: ordemCanais ?? this.ordemCanais,
      pin: identical(pin, naoMexer) ? this.pin : pin as String?,
      categoriasBloqueadas: categoriasBloqueadas ?? this.categoriasBloqueadas,
      criadoEm: criadoEm,
    );
  }

  /// Sentinela de copyWith para campos onde `null` tem significado proprio
  /// ("apagar") e nao pode ser confundido com "nao informado".
  static const naoMexer = Object();

  Map<String, dynamic> toMap() => {
        'id': id,
        'nome': nome,
        'icone': icone,
        if (idioma != null) 'idioma': idioma,
        'autoQualidade': autoQualidade,
        'ordemCategorias': ordemCategorias,
        'ordemCanais': ordemCanais,
        if (pin != null) 'pin': pin,
        if (categoriasBloqueadas.isNotEmpty)
          'categoriasBloqueadas': categoriasBloqueadas,
        'criadoEm': criadoEm.toIso8601String(),
      };

  factory Perfil.fromMap(Map map) => Perfil(
        id: map['id'] as String,
        nome: map['nome'] as String? ?? 'Perfil',
        icone: map['icone'] as String? ?? 'aurora',
        idioma: map['idioma'] as String?,
        autoQualidade: map['autoQualidade'] as bool? ?? false,
        ordemCategorias: map['ordemCategorias'] as String? ?? 'popularidade',
        ordemCanais: map['ordemCanais'] as String? ?? 'padrao',
        pin: map['pin'] as String?,
        categoriasBloqueadas: [
          ...?(map['categoriasBloqueadas'] as List?)?.whereType<String>(),
        ],
        criadoEm: DateTime.tryParse(map['criadoEm'] as String? ?? '') ??
            DateTime.now(),
      );

}

/// Gera um UUID v4 sem depender de pacote externo. Chaveia o perfil e as boxes
/// locais do Hive.
String _gerarUuid() {
  final rnd = Random();
  final bytes = List<int>.generate(16, (_) => rnd.nextInt(256));
  bytes[6] = (bytes[6] & 0x0f) | 0x40; // versao 4
  bytes[8] = (bytes[8] & 0x3f) | 0x80; // variante
  String hex(int b) => b.toRadixString(16).padLeft(2, '0');
  final h = bytes.map(hex).join();
  return '${h.substring(0, 8)}-${h.substring(8, 12)}-${h.substring(12, 16)}'
      '-${h.substring(16, 20)}-${h.substring(20)}';
}
