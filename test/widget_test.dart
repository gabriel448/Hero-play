import 'package:flutter_test/flutter_test.dart';

import 'package:iptv_app/services/parser_m3u.dart';

void main() {
  group('ParserM3U', () {
    test('faz parsing de lista M3U simples', () {
      const conteudo = '''
#EXTM3U
#EXTINF:-1 tvg-logo="http://logo.com/a.png" group-title="Esportes",ESPN HD
http://servidor.com/espn/stream
#EXTINF:-1 tvg-id="globo.br" group-title="Abertos",Globo
http://servidor.com/globo/stream
''';
      final canais = ParserM3U().parse(conteudo);
      expect(canais.length, 2);
      expect(canais[0].nome, 'ESPN HD');
      expect(canais[0].url, 'http://servidor.com/espn/stream');
      expect(canais[0].grupo, 'Esportes');
      expect(canais[0].logoUrl, 'http://logo.com/a.png');
      expect(canais[1].nome, 'Globo');
      expect(canais[1].tvgId, 'globo.br');
    });

    test('lanca excecao se conteudo nao for M3U', () {
      expect(
        () => ParserM3U().parse('isto nao e m3u'),
        throwsA(isA<M3UInvalidoException>()),
      );
    });

    test('canal sem group-title vira "Sem categoria"', () {
      const conteudo = '''
#EXTM3U
#EXTINF:-1,Canal Solto
http://servidor.com/x
''';
      final canais = ParserM3U().parse(conteudo);
      expect(canais.single.grupo, 'Sem categoria');
    });
  });
}