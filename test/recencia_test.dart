import 'package:flutter_test/flutter_test.dart';
import 'package:iptv_app/models/canal.dart';
import 'package:iptv_app/models/serie.dart';
import 'package:iptv_app/utils/recencia.dart';

/// A fila de "Lançamentos" tem que trazer o que ACABOU de entrar no catálogo —
/// era ordenada em A-Z, que escondia o item novo no meio da lista.
/// A mesma regra existe no app de TV (`tv-app/lista.js`).
void main() {
  const base = 'http://host:8080/movie/user/pass/';

  Canal filme(String nome, String url) =>
      Canal(nome: nome, url: url, grupo: 'Lançamentos', tipo: TipoCanal.filme);

  Serie serie(String nome, List<String> urls) => Serie(
        nome: nome,
        logoUrl: null,
        grupo: 'Lançamentos',
        episodios: [
          for (final u in urls)
            Canal(nome: nome, url: u, grupo: 'Lançamentos', tipo: TipoCanal.filme),
        ],
      );

  group('idStream', () {
    test('lê o id do caminho Xtream', () {
      expect(idStream('${base}123456.mp4'), 123456);
    });
    test('ignora querystring', () {
      expect(idStream('${base}999.mkv?token=abc'), 999);
    });
    test('funciona sem extensão', () {
      expect(idStream('http://host/live/u/p/777'), 777);
    });
    test('devolve null quando não há id numérico', () {
      expect(idStream('http://host/algum-filme.mp4'), isNull);
    });
  });

  group('ordenarPorRecencia', () {
    test('mais novo (id maior) primeiro, e não em A-Z', () {
      final itens = <Object>[
        filme('Avatar', '${base}100.mp4'),
        filme('Batman', '${base}950.mp4'),
        filme('Zorro', '${base}500.mp4'),
      ];
      expect(
        ordenarPorRecencia(itens).map((e) => (e as Canal).nome),
        ['Batman', 'Zorro', 'Avatar'],
      );
    });

    test('sem id vai depois, na ordem inversa do arquivo', () {
      final itens = <Object>[
        filme('SemId A', 'http://host/aa.mp4'),
        filme('ComId', '${base}42.mp4'),
        filme('SemId B', 'http://host/bb.mp4'),
      ];
      expect(
        ordenarPorRecencia(itens).map((e) => (e as Canal).nome),
        ['ComId', 'SemId B', 'SemId A'],
      );
    });

    test('série usa o MAIOR id entre os episódios', () {
      final itens = <Object>[
        serie('Série velha', ['${base}10.mkv', '${base}11.mkv']),
        serie('Série nova', ['${base}880.mkv', '${base}12.mkv']),
      ];
      expect(
        ordenarPorRecencia(itens).map((e) => (e as Serie).nome),
        ['Série nova', 'Série velha'],
      );
    });

    test('lista vazia não quebra', () {
      expect(ordenarPorRecencia(const []), isEmpty);
    });
  });
}
