import 'dart:convert';
import 'dart:io';
import 'package:http/http.dart' as http;

/// Excecao levantada quando nao conseguimos obter o conteudo da lista.
class CarregamentoListaException implements Exception {
  final String mensagem;
  CarregamentoListaException(this.mensagem);

  @override
  String toString() => 'Falha ao carregar lista: $mensagem';
}

/// Servico responsavel por obter o texto bruto de uma lista M3U,
/// seja a partir de uma URL (HTTP/HTTPS) ou de um arquivo local.
///
/// Esta classe NAO sabe parsear M3U - so devolve o texto. A separacao
/// permite testar parsing isoladamente sem precisar de rede.
class CarregadorLista {
  /// Tempo maximo de espera para um download HTTP.
  final Duration timeout;

  CarregadorLista({this.timeout = const Duration(seconds: 30)});

  /// Baixa o conteudo de uma URL e retorna o texto.
  Future<String> baixarDeUrl(String url) async {
    try {
      final uri = Uri.parse(url);
      final resposta = await http.get(uri).timeout(timeout);

      if (resposta.statusCode < 200 || resposta.statusCode >= 300) {
        throw CarregamentoListaException(
          'Servidor retornou ${resposta.statusCode}. URL pode estar errada ou indisponivel.',
        );
      }

      return _decodificar(resposta.bodyBytes);
    } on FormatException {
      throw CarregamentoListaException('URL invalida: $url');
    } on SocketException {
      throw CarregamentoListaException(
        'Sem conexao com a internet ou servidor inacessivel.',
      );
    } on HttpException catch (e) {
      throw CarregamentoListaException('Erro HTTP: ${e.message}');
    } catch (e) {
      if (e is CarregamentoListaException) rethrow;
      throw CarregamentoListaException(e.toString());
    }
  }

  /// Decodifica bytes tentando UTF-8 primeiro; cai em latin1 se invalido.
  static String _decodificar(List<int> bytes) {
    try {
      return utf8.decode(bytes);
    } catch (_) {
      return latin1.decode(bytes);
    }
  }

  /// Le o conteudo de um arquivo local.
  Future<String> lerDeArquivo(String caminho) async {
    try {
      final arquivo = File(caminho);
      if (!await arquivo.exists()) {
        throw CarregamentoListaException(
          'Arquivo nao encontrado em: $caminho',
        );
      }
      return await arquivo.readAsString();
    } catch (e) {
      if (e is CarregamentoListaException) rethrow;
      throw CarregamentoListaException(
        'Nao foi possivel ler o arquivo: ${e.toString()}',
      );
    }
  }
}