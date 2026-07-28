import 'canal.dart';

/// Origem da lista M3U: foi importada por URL ou por arquivo local?
/// Util para sabermos se podemos "atualizar" a lista (so para URLs).
enum OrigemLista { url, arquivo }

/// Representa uma lista M3U inteira que o usuario importou e salvou.
///
/// Mantemos os canais aqui (depois de parseados) para evitar reparsear
/// o arquivo M3U toda vez que o usuario abre a lista.
class ListaM3U {
  /// Nome amigavel da lista, escolhido pelo usuario.
  final String nome;

  /// Origem da fonte: URL ou caminho de arquivo local.
  final String fonte;

  /// Tipo da origem (url ou arquivo).
  final OrigemLista origem;

  /// Canais ja parseados, prontos para exibicao.
  final List<Canal> canais;

  /// Quando a lista foi importada/atualizada pela ultima vez.
  final DateTime atualizadaEm;

  /// URL do guia de programacao eletronico (EPG/XMLTV) associado, opcional.
  /// Quando definida, o EpgService usa para baixar a grade dos canais ao vivo.
  final String? epgUrl;

  /// `true` quando a lista veio da ATIVACAO do aparelho (painel/nuvem) em vez
  /// de ter sido adicionada a mao pelo usuario. Listas do dispositivo sao
  /// trocadas/removidas automaticamente quando o painel muda a playlist ativa;
  /// as manuais, nunca.
  final bool doDispositivo;

  const ListaM3U({
    required this.nome,
    required this.fonte,
    required this.origem,
    required this.canais,
    required this.atualizadaEm,
    this.epgUrl,
    this.doDispositivo = false,
  });

  /// Total de canais nesta lista.
  int get totalCanais => canais.length;

  /// Apenas canais ao vivo (TV / radio / live).
  List<Canal> get canaisAoVivo =>
      canais.where((c) => c.tipo == TipoCanal.aoVivo).toList();

  /// Apenas filmes / VOD / series.
  List<Canal> get filmes =>
      canais.where((c) => c.tipo == TipoCanal.filme).toList();

  /// Mapa de categoria -> lista de canais, filtrado por tipo.
  /// Pre-calculado uma vez para uso eficiente na UI (evita rerun em build).
  Map<String, List<Canal>> agruparPorCategoria(TipoCanal tipo) {
    final mapa = <String, List<Canal>>{};
    for (final c in canais) {
      if (c.tipo != tipo) continue;
      mapa.putIfAbsent(c.grupo, () => []).add(c);
    }
    return mapa;
  }

  /// Lista distinta de grupos/categorias encontrados nos canais.
  /// Ordenada alfabeticamente para exibicao consistente.
  List<String> get grupos {
    final set = <String>{for (final c in canais) c.grupo};
    final lista = set.toList()..sort();
    return lista;
  }

  /// Identificador estavel: a fonte (URL ou caminho) e unica por lista.
  String get id => fonte;

  Map<String, dynamic> toMap() => {
        'nome': nome,
        'fonte': fonte,
        'origem': origem.name,
        'canais': canais.map((c) => c.toMap()).toList(),
        'atualizadaEm': atualizadaEm.toIso8601String(),
        if (epgUrl != null) 'epgUrl': epgUrl,
        // Omitido quando falso -> schema retrocompativel (listas antigas leem
        // como manuais, que e o que elas sao).
        if (doDispositivo) 'doDispositivo': true,
      };

  factory ListaM3U.fromMap(Map map) => ListaM3U(
        nome: map['nome'] as String? ?? 'Lista sem nome',
        fonte: map['fonte'] as String,
        origem: OrigemLista.values.firstWhere(
          (o) => o.name == map['origem'],
          orElse: () => OrigemLista.url,
        ),
        canais: (map['canais'] as List)
            .map((m) => Canal.fromMap(m as Map))
            .toList(),
        atualizadaEm: DateTime.tryParse(map['atualizadaEm'] as String? ?? '') ??
            DateTime.now(),
        epgUrl: map['epgUrl'] as String?,
        doDispositivo: map['doDispositivo'] as bool? ?? false,
      );

  /// Cria uma copia modificando alguns campos. Util para "atualizar" a lista
  /// mantendo o nome escolhido pelo usuario mas trocando canais e data.
  ListaM3U copyWith({
    String? nome,
    List<Canal>? canais,
    DateTime? atualizadaEm,
    String? epgUrl,
    bool? doDispositivo,
  }) =>
      ListaM3U(
        nome: nome ?? this.nome,
        fonte: fonte,
        origem: origem,
        canais: canais ?? this.canais,
        atualizadaEm: atualizadaEm ?? this.atualizadaEm,
        epgUrl: epgUrl ?? this.epgUrl,
        doDispositivo: doDispositivo ?? this.doDispositivo,
      );
}