import 'dart:convert';
import 'dart:io';
import 'package:http/http.dart' as http;

/// Excecao levantada quando nao conseguimos obter o conteudo do EPG.
class CarregamentoEpgException implements Exception {
  final String mensagem;
  CarregamentoEpgException(this.mensagem);

  @override
  String toString() => 'Falha ao carregar EPG: $mensagem';
}

/// Servico responsavel por obter o texto bruto de um arquivo XMLTV (EPG).
///
/// Aceita URLs e arquivos locais. Suporta arquivos `.gz` (gzip) automaticamente
/// — muitos provedores distribuem EPG comprimido para economizar banda.
class CarregadorEpg {
  /// Tempo maximo de espera para um download. EPGs costumam ser grandes (10MB+)
  /// e demoram mais que listas M3U, por isso 60s.
  final Duration timeout;

  CarregadorEpg({this.timeout = const Duration(seconds: 60)});

  /// Baixa o XMLTV de uma URL e devolve o texto descomprimido.
  Future<String> baixarDeUrl(String url) async {
    try {
      final uri = Uri.parse(url);
      final resposta = await http.get(uri).timeout(timeout);

      if (resposta.statusCode < 200 || resposta.statusCode >= 300) {
        throw CarregamentoEpgException(
          'Servidor retornou ${resposta.statusCode}. URL pode estar errada ou indisponivel.',
        );
      }

      return _decodificar(resposta.bodyBytes);
    } on FormatException {
      throw CarregamentoEpgException('URL invalida: $url');
    } on SocketException {
      throw CarregamentoEpgException(
        'Sem conexao com a internet ou servidor inacessivel.',
      );
    } on HttpException catch (e) {
      throw CarregamentoEpgException('Erro HTTP: ${e.message}');
    } catch (e) {
      if (e is CarregamentoEpgException) rethrow;
      throw CarregamentoEpgException(e.toString());
    }
  }

  /// Le um arquivo XMLTV local (suporta .gz).
  Future<String> lerDeArquivo(String caminho) async {
    try {
      final arquivo = File(caminho);
      if (!await arquivo.exists()) {
        throw CarregamentoEpgException(
          'Arquivo nao encontrado em: $caminho',
        );
      }
      final bytes = await arquivo.readAsBytes();
      return _decodificar(bytes);
    } catch (e) {
      if (e is CarregamentoEpgException) rethrow;
      throw CarregamentoEpgException(
        'Nao foi possivel ler o arquivo: ${e.toString()}',
      );
    }
  }

  /// Detecta gzip pelos magic bytes (1f 8b) e descomprime se necessario.
  /// Tenta UTF-8 e cai em latin1 se falhar.
  static String _decodificar(List<int> bytes) {
    List<int> conteudo = bytes;
    if (bytes.length >= 2 && bytes[0] == 0x1f && bytes[1] == 0x8b) {
      try {
        conteudo = gzip.decode(bytes);
      } catch (e) {
        throw CarregamentoEpgException(
          'Falha ao descomprimir gzip: $e',
        );
      }
    }
    try {
      return utf8.decode(conteudo);
    } catch (_) {
      return latin1.decode(conteudo);
    }
  }
}
