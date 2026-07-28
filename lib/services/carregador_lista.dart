import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:typed_data' show BytesBuilder;
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
  /// Tempo maximo SEM receber bytes antes de desistir.
  ///
  /// Antes usavamos um timeout unico de 30s para o download inteiro: uma lista
  /// de dezenas de MB em rede movel estoura isso mesmo baixando bem, e a
  /// importacao falhava sempre. Agora so desistimos quando o fluxo PARA de
  /// andar — download lento mas progredindo continua. Mesma regra do watchdog
  /// do app de TV (`baixarTexto` em `tv-app/app.js`).
  final Duration timeoutSemDados;

  /// Teto absoluto de seguranca (um download que nunca termina).
  final Duration timeoutTotal;

  CarregadorLista({
    this.timeoutSemDados = const Duration(seconds: 40),
    this.timeoutTotal = const Duration(minutes: 15),
  });

  /// Baixa o conteudo de uma URL e retorna o texto.
  ///
  /// [aoProgredir] recebe (bytesRecebidos, bytesTotais) — `bytesTotais` e null
  /// quando o servidor nao manda `Content-Length` (comum em Xtream). Serve para
  /// a tela de carregamento mostrar avanco real em vez de uma barra infinita.
  Future<String> baixarDeUrl(
    String url, {
    void Function(int recebidos, int? total)? aoProgredir,
  }) async {
    final cliente = http.Client();
    try {
      final uri = Uri.parse(url);
      final requisicao = http.Request('GET', uri)
        ..headers['Accept-Encoding'] = 'gzip';

      final resposta = await cliente
          .send(requisicao)
          .timeout(timeoutSemDados, onTimeout: () {
        throw CarregamentoListaException('O servidor nao respondeu.');
      });

      if (resposta.statusCode < 200 || resposta.statusCode >= 300) {
        throw CarregamentoListaException(
          'Servidor retornou ${resposta.statusCode}. URL pode estar errada ou indisponivel.',
        );
      }

      final bytes = await _lerComWatchdog(
        resposta.stream,
        total: resposta.contentLength,
        aoProgredir: aoProgredir,
      );
      return _decodificar(bytes);
    } on FormatException {
      throw CarregamentoListaException('URL invalida: $url');
    } on SocketException {
      throw CarregamentoListaException(
        'Sem conexao com a internet ou servidor inacessivel.',
      );
    } on HttpException catch (e) {
      throw CarregamentoListaException('Erro HTTP: ${e.message}');
    } on TimeoutException {
      throw CarregamentoListaException('O servidor nao respondeu.');
    } catch (e) {
      if (e is CarregamentoListaException) rethrow;
      throw CarregamentoListaException(e.toString());
    } finally {
      cliente.close();
    }
  }

  /// Consome o corpo da resposta acumulando os bytes, com dois relogios:
  /// inatividade ([timeoutSemDados]) e duracao total ([timeoutTotal]).
  Future<List<int>> _lerComWatchdog(
    Stream<List<int>> corpo, {
    int? total,
    void Function(int recebidos, int? total)? aoProgredir,
  }) {
    final concluido = Completer<List<int>>();
    final acumulado = BytesBuilder(copy: false);
    final inicio = DateTime.now();
    var ultimoDado = DateTime.now();
    StreamSubscription<List<int>>? sub;
    Timer? vigia;

    void encerrar(FutureOr<List<int>> Function() resultado) {
      if (concluido.isCompleted) return;
      vigia?.cancel();
      sub?.cancel();
      try {
        concluido.complete(resultado());
      } catch (e) {
        concluido.completeError(e);
      }
    }

    vigia = Timer.periodic(const Duration(seconds: 2), (_) {
      final agora = DateTime.now();
      if (agora.difference(ultimoDado) > timeoutSemDados) {
        encerrar(() => throw CarregamentoListaException(
              'Download travado: o servidor parou de responder.',
            ));
      } else if (agora.difference(inicio) > timeoutTotal) {
        encerrar(() => throw CarregamentoListaException(
              'O download demorou demais e foi cancelado.',
            ));
      }
    });

    sub = corpo.listen(
      (pedaco) {
        ultimoDado = DateTime.now();
        acumulado.add(pedaco);
        aoProgredir?.call(acumulado.length, total);
      },
      onDone: () => encerrar(acumulado.takeBytes),
      onError: (Object e) => encerrar(
        () => throw CarregamentoListaException(e.toString()),
      ),
      cancelOnError: true,
    );

    return concluido.future;
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
