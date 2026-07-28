import 'package:flutter_test/flutter_test.dart';
import 'package:iptv_app/services/dispositivo.dart';

/// O EPG e derivado da propria M3U sempre que possivel — o usuario so digita a
/// URL quando o provedor foge do padrao. A MESMA regra vale no site
/// (`website/upload.html`) e no app de TV (`tv-app/device.js`).
void main() {
  group('ListaUtil.derivarEpg', () {
    test('formato querystring (get.php?username=&password=)', () {
      expect(
        ListaUtil.derivarEpg(
          'http://serv.tv:8080/get.php?username=joao&password=1234&type=m3u_plus',
        ),
        'http://serv.tv:8080/xmltv.php?username=joao&password=1234',
      );
    });

    test('formato de caminho (/playlist/user/pass/m3u_plus)', () {
      expect(
        ListaUtil.derivarEpg('http://serv.tv:8080/playlist/joao/1234/m3u_plus'),
        'http://serv.tv:8080/xmltv.php?username=joao&password=1234',
      );
    });

    test('M3U avulsa nao tem EPG derivavel', () {
      expect(ListaUtil.derivarEpg('https://cdn.exemplo.com/lista.m3u'), '');
    });

    test('escapa caracteres especiais do usuario/senha', () {
      expect(
        ListaUtil.derivarEpg('http://s.tv/get.php?username=a%40b&password=p%20w'),
        'http://s.tv/xmltv.php?username=a%40b&password=p%20w',
      );
    });

    test('URL invalida nao quebra', () {
      expect(ListaUtil.derivarEpg('nao e uma url'), '');
    });
  });

  group('ListaUtil.montarXtream', () {
    test('monta lista e EPG a partir das credenciais', () {
      final r = ListaUtil.montarXtream('serv.tv:8080', 'joao', '1234');
      expect(r.listaUrl,
          'http://serv.tv:8080/get.php?username=joao&password=1234&type=m3u_plus&output=ts');
      expect(r.epgUrl, 'http://serv.tv:8080/xmltv.php?username=joao&password=1234');
    });

    test('remove get.php/barra sobrando do host colado pelo usuario', () {
      final r = ListaUtil.montarXtream(
        'http://serv.tv:8080/get.php?username=x&password=y',
        'joao',
        '1234',
      );
      expect(r.listaUrl, startsWith('http://serv.tv:8080/get.php?username=joao'));
    });
  });
}
