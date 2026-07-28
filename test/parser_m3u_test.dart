import 'package:flutter_test/flutter_test.dart';
import 'package:iptv_app/models/canal.dart';
import 'package:iptv_app/models/serie.dart';
import 'package:iptv_app/services/parser_m3u.dart';

/// Guarda o bug que ja apareceu duas vezes: CANAL AO VIVO caindo na secao de
/// Filmes porque a categoria se chama "FILMES"/"CINEMA". A classificacao e so
/// pela URL — categoria nao decide nada.
void main() {
  final parser = ParserM3U();

  group('classificacao ao vivo x VOD', () {
    test('canal ao vivo em categoria de filme continua ao vivo', () {
      final canais = parser.parse('''
#EXTM3U
#EXTINF:-1 tvg-id="tc.br" group-title="GLOBOSAT FILMES",Telecine Premium HD
http://host:8080/user/pass/12345
#EXTINF:-1 group-title="CINEMA",TC Cult
http://host:8080/user/pass/12346
''');
      expect(canais, hasLength(2));
      expect(canais.every((c) => c.tipo == TipoCanal.aoVivo), isTrue);
    });

    test('VOD e reconhecido por /movie/, /series/ e extensao', () {
      final canais = parser.parse('''
#EXTM3U
#EXTINF:-1 group-title="LANCAMENTOS",Interestelar
http://host:8080/movie/user/pass/999.mp4
#EXTINF:-1 group-title="SERIES",Round 6 S01E01
http://host:8080/series/user/pass/1000.mkv
#EXTINF:-1 group-title="Sem categoria",Filme solto
http://host/arquivo.avi
#EXTINF:-1 group-title="ESPORTES",SporTV
http://host:8080/user/pass/777
''');
      expect(canais.map((c) => c.tipo).toList(), [
        TipoCanal.filme,
        TipoCanal.filme,
        TipoCanal.filme,
        TipoCanal.aoVivo,
      ]);
    });

    test('querystring nao atrapalha a extensao', () {
      expect(
        tipoCanalPorUrl('http://host/x/filme.mp4?token=abc'),
        TipoCanal.filme,
      );
    });

    test('lista antiga do cache e reclassificada ao carregar', () {
      // Registro gravado pela regra ANTIGA: tipo salvo como 'filme' para um
      // canal ao vivo. Ao ler, o tipo e recalculado pela URL.
      final canal = Canal.fromMap({
        'nome': 'Telecine Pipoca',
        'url': 'http://host:8080/user/pass/555',
        'grupo': 'FILMES',
        'tipo': 'filme',
      });
      expect(canal.tipo, TipoCanal.aoVivo);
    });
  });

  group('dedup de VOD', () {
    Canal filme(String nome, String url) =>
        Canal(nome: nome, url: url, grupo: 'VOD', tipo: TipoCanal.filme);

    test('mesmo filme repetido em categorias diferentes aparece uma vez', () {
      final r = Serie.agrupar([
        filme('Interestelar', 'http://h/1.mp4'),
        filme('interestelar', 'http://h/2.mp4'),
        filme('Interestelar', 'http://h/3.mp4'),
        filme('Duna', 'http://h/4.mp4'),
      ]);
      expect(r.filmes.map((c) => c.nome), ['Interestelar', 'Duna']);
    });

    test('acento nao cria titulo duplicado', () {
      final r = Serie.agrupar([
        filme('Coracao Valente', 'http://h/1.mp4'),
        filme('Coração Valente', 'http://h/2.mp4'),
      ]);
      expect(r.filmes, hasLength(1));
    });

    test('serie com caixa diferente vira UMA serie', () {
      final r = Serie.agrupar([
        filme('Round 6 S01E01', 'http://h/1.mp4'),
        filme('round 6 S01E02', 'http://h/2.mp4'),
      ]);
      expect(r.series, hasLength(1));
      expect(r.series.single.totalEpisodios, 2);
    });
  });

  group('EXTINF', () {
    test('virgula dentro de aspas nao quebra o titulo', () {
      final canais = parser.parse('''
#EXTM3U
#EXTINF:-1 tvg-name="MEU FILHO, NOSSO MUNDO" group-title="VOD",Meu Filho, Nosso Mundo
http://host/x.mp4
''');
      expect(canais.single.nome, 'Meu Filho, Nosso Mundo');
      expect(canais.single.grupo, 'VOD');
    });

    test('atributos e duracao continuam sendo lidos', () {
      final canais = parser.parse('''
#EXTM3U
#EXTINF:7200 tvg-id="id1" tvg-logo="http://logo.png" group-title="G",Nome
http://host/x.mp4
''');
      final c = canais.single;
      expect(c.tvgId, 'id1');
      expect(c.logoUrl, 'http://logo.png');
      expect(c.duracaoSegundos, 7200);
    });
  });
}
