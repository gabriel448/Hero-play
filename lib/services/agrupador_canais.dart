import '../models/canal.dart';
import '../utils/qualidade.dart';

/// Categorias virtuais de qualidade. Mapa qualidade -> lista de canais que
/// existem naquela resolucao, com a URL apontando para a variante daquela
/// qualidade especifica. Util para o usuario abrir um canal direto em SD/HD/
/// FHD a partir do menu MINHAS CATEGORIAS, sem precisar trocar a qualidade
/// dentro do player.
///
/// Para canais nao agrupados (sem variantes), classifica pelo nome (ex.:
/// "Globo HD" -> HD). Para canais agrupados, gera uma entrada por variante
/// daquela qualidade, com a URL da variante correta.
///
/// O retorno preserva apenas qualidades com canais (categorias vazias sao
/// omitidas) e segue a ordem FHD -> HD -> SD.
Map<String, List<Canal>> agruparPorQualidade(
  Map<String, List<Canal>> categoriasAoVivo,
) {
  final buckets = <Qualidade, List<Canal>>{
    Qualidade.fhd: [],
    Qualidade.hd: [],
    Qualidade.sd: [],
  };

  for (final canais in categoriasAoVivo.values) {
    for (final c in canais) {
      if (c.variantes.isEmpty) {
        final q = detectarQualidade(c.nome);
        final balde = buckets[q];
        if (balde == null) continue;
        // Reaproveita o canal — toca direto na URL principal.
        balde.add(c);
      } else {
        for (final v in c.variantes) {
          final q = detectarQualidade(v.nome);
          final balde = buckets[q];
          if (balde == null) continue;
          // Cria uma "vista" do canal apontando para a variante exata, sem
          // o array variantes — assim o player toca direto a qualidade alvo
          // sem oferecer troca.
          balde.add(Canal(
            nome: c.nome,
            url: v.url,
            logoUrl: c.logoUrl,
            grupo: q.rotulo,
            tvgId: c.tvgId,
            tipo: TipoCanal.aoVivo,
            idGrupo: '${c.idGrupo ?? c.id}|${q.name}',
          ));
        }
      }
    }
  }

  final resultado = <String, List<Canal>>{};
  for (final q in [Qualidade.fhd, Qualidade.hd, Qualidade.sd]) {
    final lista = buckets[q]!;
    if (lista.isEmpty) continue;
    // Ordena alfabeticamente dentro de cada qualidade — melhora descoberta
    // ja que essa pseudo-categoria mistura canais de varios grupos originais.
    lista.sort((a, b) => a.nome.toLowerCase().compareTo(b.nome.toLowerCase()));
    resultado[q.rotulo] = lista;
  }
  return resultado;
}

/// Agrupa canais ao vivo que representam o mesmo canal em qualidades
/// diferentes, e funde categorias que so diferem por tag de qualidade.
///
/// Retorna o mapa `categoria normalizada -> canais`, onde cada canal pode ser:
///  - um canal agrupado (com [Canal.variantes] preenchido), quando havia 2+
///    variantes do mesmo canal;
///  - um canal comum, quando nao havia duplicata.
///
/// A ordem de aparicao das categorias e dos canais e preservada.
Map<String, List<Canal>> agruparCanaisAoVivo(List<Canal> canais) {
  // categoria normalizada -> (chave do canal -> variantes)
  final mapa = <String, Map<String, List<Canal>>>{};
  final ordemCategorias = <String>[];
  final ordemCanais = <String, List<String>>{};

  for (final c in canais) {
    final categoria = categoriaBase(c.grupo);
    final chave = nomeBase(c.nome).toLowerCase();

    final canaisDaCategoria = mapa.putIfAbsent(categoria, () {
      ordemCategorias.add(categoria);
      ordemCanais[categoria] = [];
      return {};
    });
    final variantes = canaisDaCategoria.putIfAbsent(chave, () {
      ordemCanais[categoria]!.add(chave);
      return [];
    });
    variantes.add(c);
  }

  final resultado = <String, List<Canal>>{};
  for (final categoria in ordemCategorias) {
    resultado[categoria] = [
      for (final chave in ordemCanais[categoria]!)
        _montarCanal(categoria, mapa[categoria]![chave]!),
    ];
  }
  return resultado;
}

/// Monta o [Canal] final a partir das variantes de um mesmo canal.
/// Uma variante -> canal comum (so com a categoria normalizada).
/// Duas ou mais -> canal agrupado.
Canal _montarCanal(String categoria, List<Canal> variantes) {
  if (variantes.length == 1) {
    final unico = variantes.first;
    if (unico.grupo == categoria) return unico;
    // Categoria mudou na normalizacao — recria com a categoria fundida.
    return Canal(
      nome: unico.nome,
      url: unico.url,
      logoUrl: unico.logoUrl,
      grupo: categoria,
      tvgId: unico.tvgId,
      tipo: unico.tipo,
    );
  }

  // Ordena da melhor qualidade para a pior.
  final ordenadas = [...variantes]
    ..sort((a, b) =>
        detectarQualidade(b.nome).rank - detectarQualidade(a.nome).rank);

  final melhor = ordenadas.first;
  final base = nomeBase(melhor.nome);
  final comLogo = ordenadas.firstWhere(
    (v) => v.logoUrl != null && v.logoUrl!.isNotEmpty,
    orElse: () => melhor,
  );

  return Canal(
    nome: base,
    url: melhor.url,
    logoUrl: comLogo.logoUrl,
    grupo: categoria,
    tvgId: melhor.tvgId,
    tipo: TipoCanal.aoVivo,
    variantes: ordenadas,
    idGrupo: 'g:${categoria.toLowerCase()}|${base.toLowerCase()}',
  );
}
