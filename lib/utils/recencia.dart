import '../models/canal.dart';
import '../models/serie.dart';

/// "O que acabou de entrar no catálogo".
///
/// A lista M3U não traz data de inclusão, e o ANO do título é o ano de
/// lançamento do FILME — não serve para saber o que chegou por último. O sinal
/// que existe é o **id numérico do stream** na URL Xtream
/// (`.../movie/user/pass/123456.mp4`): o painel do provedor gera ids
/// crescentes, então id maior = entrou depois.
///
/// A mesma regra vale no app de TV (`tv-app/lista.js`) — se mudar aqui, mude lá.

/// Id numérico do stream na URL, ou null quando a URL não tem id (M3U avulsa).
int? idStream(String url) {
  final semQuery = url.split('?').first;
  final ultimo = semQuery.split('/').last;
  final semExt = ultimo.contains('.')
      ? ultimo.substring(0, ultimo.lastIndexOf('.'))
      : ultimo;
  return int.tryParse(semExt);
}

/// Peso de recência de um item do catálogo. Série usa o MAIOR id entre os
/// episódios — o episódio mais novo é o que diz se ela teve movimento recente.
int? pesoRecencia(Object item) {
  if (item is Canal) return idStream(item.url);
  if (item is! Serie) return null;
  int? maior;
  for (final ep in item.episodios) {
    final id = idStream(ep.url);
    if (id != null && (maior == null || id > maior)) maior = id;
  }
  return maior;
}

/// Ordena do mais NOVO para o mais antigo.
///
/// Quem tem id Xtream vem primeiro, do maior para o menor. Quem não tem fica
/// depois, na ordem INVERSA em que aparecia na lista — provedores acrescentam
/// no fim do arquivo, então o fim da lista é o que chegou por último.
List<Object> ordenarPorRecencia(List<Object> itens) {
  final decorado = [
    for (var i = 0; i < itens.length; i++)
      (item: itens[i], id: pesoRecencia(itens[i]), pos: i),
  ];
  decorado.sort((a, b) {
    if (a.id != null && b.id != null) return b.id!.compareTo(a.id!);
    if (a.id != null) return -1;
    if (b.id != null) return 1;
    return b.pos.compareTo(a.pos);
  });
  return [for (final d in decorado) d.item];
}
