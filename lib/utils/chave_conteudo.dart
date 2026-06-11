import '../models/canal.dart';
import '../models/serie.dart';

/// Deriva uma chave ESTAVEL de conteudo a partir da URL do stream, ignorando as
/// partes volateis (host, porta e credenciais Xtream no path). Sobrevive a
/// troca de IP/dominio/credenciais do MESMO provedor — o id do conteudo (ultimo
/// segmento do path) e estavel no catalogo daquele servidor.
///
/// Exemplos:
///   http://ip:porta/movie/USER/PASS/123456.mp4  -> "movie/123456"
///   http://ip:porta/series/USER/PASS/789.mkv     -> "series/789"
///   http://ip:porta/USER/PASS/555.ts             -> "555"
///   http://host/caminho/filme.mp4                -> "filme"
String chaveConteudo(String url) {
  try {
    final u = Uri.parse(url);
    final segs = u.pathSegments.where((s) => s.isNotEmpty).toList();
    if (segs.isEmpty) return url.toLowerCase();
    // Id = ultimo segmento, sem extensao.
    var id = segs.last;
    final ponto = id.lastIndexOf('.');
    if (ponto > 0) id = id.substring(0, ponto);
    // Prefixa com o tipo (movie/series/live) quando presente — reduz colisao
    // entre ids iguais de conteudos diferentes.
    String? tipo;
    for (final s in segs) {
      final l = s.toLowerCase();
      if (l == 'movie' || l == 'series' || l == 'live') {
        tipo = l;
        break;
      }
    }
    final chave = (tipo != null ? '$tipo/$id' : id).toLowerCase().trim();
    return chave.isEmpty ? url.toLowerCase() : chave;
  } catch (_) {
    return url.toLowerCase();
  }
}

/// Chave estavel para a BIBLIOTECA pessoal (favoritos/historico). Prioriza o
/// que e mais estavel: o `tvgId` (id de EPG, para canais ao vivo), depois o
/// `idGrupo` (canais agrupados, baseado em nome+categoria) e, por fim, a chave
/// de conteudo da URL.
String chaveBiblioteca(Canal c) {
  final tvg = c.tvgId?.trim();
  if (tvg != null && tvg.isNotEmpty) return 'tvg:${tvg.toLowerCase()}';
  final idg = c.idGrupo;
  if (idg != null && idg.isNotEmpty) return idg;
  return chaveConteudo(c.url);
}

/// Chave estavel para a "minha lista". Canal -> chave de conteudo; Serie ->
/// nome (ja estavel).
String chaveItemMinhaLista(Object item) {
  if (item is Canal) return 'c:${chaveConteudo(item.url)}';
  if (item is Serie) return 's:${item.nome}';
  return item.toString();
}
