import '../models/canal.dart';
import '../utils/qualidade.dart';

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
