import 'package:flutter/foundation.dart';
import '../models/canal.dart';
import '../models/canal_assistido.dart';
import '../models/lista_m3u.dart';
import '../services/armazenamento.dart';
import '../services/carregador_lista.dart';
import '../services/parser_m3u.dart';

/// Provider central do app: mantem o estado e expoe acoes para a UI.
///
/// Usamos [ChangeNotifier] (do Flutter) - quando algo muda chamamos
/// [notifyListeners] e as telas que escutam se redesenham automaticamente.
class IptvProvider extends ChangeNotifier {
  final Armazenamento _armazenamento;
  final CarregadorLista _carregador;
  final ParserM3U _parser;

  IptvProvider({
    required Armazenamento armazenamento,
    CarregadorLista? carregador,
    ParserM3U? parser,
  })  :
        // ignore: prefer_initializing_formals
        _armazenamento = armazenamento,
        _carregador = carregador ?? CarregadorLista(),
        _parser = parser ?? ParserM3U();

  // ===== ESTADO =====

  List<ListaM3U> _listas = [];
  List<Canal> _favoritos = [];
  List<CanalAssistido> _historico = [];
  ListaM3U? _listaAtiva;
  String _busca = '';
  bool _carregando = false;
  String? _erro;

  List<ListaM3U> get listas => _listas;
  List<Canal> get favoritos => _favoritos;
  List<CanalAssistido> get historico => _historico;
  ListaM3U? get listaAtiva => _listaAtiva;
  String get busca => _busca;
  bool get carregando => _carregando;
  String? get erro => _erro;

  /// Carrega tudo do armazenamento local. Chamar uma vez no startup.
  Future<void> inicializar() async {
    _listas = _armazenamento.carregarListas();
    _favoritos = _armazenamento.carregarFavoritos();
    _historico = _armazenamento.carregarHistorico();
    notifyListeners();
  }

  // ===== IMPORTACAO DE LISTAS =====

  /// Importa uma lista por URL.
  /// Se ja existir lista com a mesma URL, ela e ATUALIZADA (canais sao
  /// reparseados) - util para refresh.
  Future<void> importarPorUrl({required String nome, required String url}) async {
    await _executarComLoading(() async {
      final conteudo = await _carregador.baixarDeUrl(url);
      final canais = _parser.parse(conteudo);
      final lista = ListaM3U(
        nome: nome,
        fonte: url,
        origem: OrigemLista.url,
        canais: canais,
        atualizadaEm: DateTime.now(),
      );
      await _armazenamento.salvarLista(lista);
      _listas = _armazenamento.carregarListas();
    });
  }

  /// Importa uma lista de um arquivo local.
  Future<void> importarPorArquivo({required String nome, required String caminho}) async {
    await _executarComLoading(() async {
      final conteudo = await _carregador.lerDeArquivo(caminho);
      final canais = _parser.parse(conteudo);
      final lista = ListaM3U(
        nome: nome,
        fonte: caminho,
        origem: OrigemLista.arquivo,
        canais: canais,
        atualizadaEm: DateTime.now(),
      );
      await _armazenamento.salvarLista(lista);
      _listas = _armazenamento.carregarListas();
    });
  }

  /// Atualiza uma lista existente (so faz sentido para listas por URL).
  Future<void> atualizarLista(ListaM3U lista) async {
    if (lista.origem != OrigemLista.url) {
      throw Exception('So e possivel atualizar listas importadas por URL.');
    }
    await importarPorUrl(nome: lista.nome, url: lista.fonte);
  }

  Future<void> removerLista(ListaM3U lista) async {
    await _armazenamento.removerLista(lista.id);
    if (_listaAtiva?.id == lista.id) _listaAtiva = null;
    _listas = _armazenamento.carregarListas();
    notifyListeners();
  }

  void selecionarLista(ListaM3U lista) {
    _listaAtiva = lista;
    _busca = '';
    notifyListeners();
  }

  void limparListaAtiva() {
    _listaAtiva = null;
    notifyListeners();
  }

  // ===== FAVORITOS =====

  bool ehFavorito(Canal canal) => _armazenamento.ehFavorito(canal.id);

  Future<void> alternarFavorito(Canal canal) async {
    if (ehFavorito(canal)) {
      await _armazenamento.removerFavorito(canal.id);
    } else {
      await _armazenamento.adicionarFavorito(canal);
    }
    _favoritos = _armazenamento.carregarFavoritos();
    notifyListeners();
  }

  // ===== HISTORICO =====

  Future<void> registrarVisualizacao(Canal canal) async {
    await _armazenamento.registrarVisualizacao(canal);
    _historico = _armazenamento.carregarHistorico();
    notifyListeners();
  }

  Future<void> limparHistorico() async {
    await _armazenamento.limparHistorico();
    _historico = [];
    notifyListeners();
  }

  // ===== BUSCA =====

  void definirBusca(String texto) {
    _busca = texto.trim();
    notifyListeners();
  }

  /// Aplica o filtro da busca na lista ativa. Procura no nome e no grupo
  /// (case-insensitive). Se a busca estiver vazia, retorna todos os canais.
  List<Canal> get canaisFiltrados {
    final canais = _listaAtiva?.canais ?? const <Canal>[];
    if (_busca.isEmpty) return canais;
    final q = _busca.toLowerCase();
    return canais
        .where((c) =>
            c.nome.toLowerCase().contains(q) ||
            c.grupo.toLowerCase().contains(q))
        .toList();
  }

  // ===== HELPERS =====

  Future<void> _executarComLoading(Future<void> Function() acao) async {
    _carregando = true;
    _erro = null;
    notifyListeners();
    try {
      await acao();
    } catch (e) {
      _erro = e.toString();
    } finally {
      _carregando = false;
      notifyListeners();
    }
  }

  void limparErro() {
    _erro = null;
    notifyListeners();
  }
}