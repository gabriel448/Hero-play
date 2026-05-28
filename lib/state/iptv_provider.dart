import 'package:flutter/foundation.dart';
import '../models/canal.dart';
import '../models/canal_assistido.dart';
import '../models/categoria_personalizada.dart';
import '../models/lista_m3u.dart';
import '../models/progresso_canal.dart';
import '../models/serie.dart';
import '../services/armazenamento.dart';
import '../services/carregador_lista.dart';
import '../services/parser_m3u.dart';
import '../services/servico_epg.dart';

/// Provider central do app: mantem o estado e expoe acoes para a UI.
///
/// Usamos [ChangeNotifier] (do Flutter) - quando algo muda chamamos
/// [notifyListeners] e as telas que escutam se redesenham automaticamente.
class IptvProvider extends ChangeNotifier {
  final Armazenamento _armazenamento;
  final CarregadorLista _carregador;
  final ParserM3U _parser;
  final ServicoEpg? _epg;

  IptvProvider({
    required Armazenamento armazenamento,
    CarregadorLista? carregador,
    ParserM3U? parser,
    ServicoEpg? epg,
  })  :
        // ignore: prefer_initializing_formals
        _armazenamento = armazenamento,
        _carregador = carregador ?? CarregadorLista(),
        _parser = parser ?? ParserM3U(),
        _epg = epg;

  // ===== ESTADO =====

  List<ListaM3U> _listas = [];
  List<Canal> _favoritos = [];
  List<CanalAssistido> _historico = [];
  List<ProgressoCanal> _progressos = [];
  List<CategoriaPersonalizada> _categoriasPersonalizadas = [];
  List<String> _minhaListaChaves = [];
  ListaM3U? _listaAtiva;
  String _busca = '';
  bool _carregando = false;
  String? _erro;
  // Tipo do formato não suportado detectado pelo parser ('hls', 'epg', ou null).
  String? _formatoNaoSuportado;
  // Canal que o player embutido do desktop esta exibindo. Null = nenhum
  // (player nao aparece). Usado apenas no layout desktop de TelaCanais.
  Canal? _canalSelecionadoDesktop;

  List<ListaM3U> get listas => _listas;
  List<Canal> get favoritos => _favoritos;
  List<CanalAssistido> get historico => _historico;
  List<ProgressoCanal> get progressos => _progressos;
  List<CategoriaPersonalizada> get categoriasPersonalizadas =>
      _categoriasPersonalizadas;
  List<String> get minhaListaChaves => _minhaListaChaves;
  ListaM3U? get listaAtiva => _listaAtiva;
  String get busca => _busca;
  bool get carregando => _carregando;
  String? get erro => _erro;
  /// Tipo do formato não suportado ('hls', 'epg') ou null se não houve esse erro.
  String? get formatoNaoSuportado => _formatoNaoSuportado;

  /// Canal que esta tocando no player embutido do desktop. Null se nenhum.
  Canal? get canalSelecionadoDesktop => _canalSelecionadoDesktop;

  /// Define o canal a tocar no player embutido do desktop. Passar null fecha
  /// o player. Trocar o canal interrompe o stream anterior e abre o novo.
  void selecionarCanalDesktop(Canal? canal) {
    if (_canalSelecionadoDesktop?.id == canal?.id) return;
    _canalSelecionadoDesktop = canal;
    notifyListeners();
  }

  /// Carrega tudo do armazenamento local. Chamar uma vez no startup.
  Future<void> inicializar() async {
    _listas = _armazenamento.carregarListas();
    _favoritos = _armazenamento.carregarFavoritos();
    _historico = _armazenamento.carregarHistorico();
    _progressos = _armazenamento.carregarProgressos();
    _categoriasPersonalizadas =
        _armazenamento.carregarCategoriasPersonalizadas();
    _minhaListaChaves = _armazenamento.carregarMinhaLista();
    _restaurarListaAtiva();
    notifyListeners();
  }

  /// Restaura a lista marcada como ativa pelo usuario, ou fallback para a
  /// primeira lista importada se nao houver marcacao mas existirem listas.
  void _restaurarListaAtiva() {
    final id = _armazenamento.obterIdListaAtiva();
    ListaM3U? alvo;
    if (id != null) {
      for (final l in _listas) {
        if (l.id == id) {
          alvo = l;
          break;
        }
      }
    }
    alvo ??= _listas.isNotEmpty ? _listas.first : null;
    if (alvo == null) return;
    _listaAtiva = alvo;
    // Persiste se o id atual estava obsoleto.
    if (id != alvo.id) {
      _armazenamento.salvarIdListaAtiva(alvo.id);
    }
    _epg?.carregarDoDisco(alvo.id);
    _baixarEpgEmBackground(alvo);
  }

  // ===== IMPORTACAO DE LISTAS =====

  /// Importa uma lista por URL.
  /// Se ja existir lista com a mesma URL, ela e ATUALIZADA (canais sao
  /// reparseados) - util para refresh.
  ///
  /// O [epgUrl] e opcional — quando informado, dispara um download em
  /// background para que a grade fique pronta antes do usuario abrir um canal.
  Future<void> importarPorUrl({
    required String nome,
    required String url,
    String? epgUrl,
  }) async {
    await _executarComLoading(() async {
      final conteudo = await _carregador.baixarDeUrl(url);
      final canais = _parser.parse(conteudo);
      final epgNormalizado =
          (epgUrl == null || epgUrl.trim().isEmpty) ? null : epgUrl.trim();
      final lista = ListaM3U(
        nome: nome,
        fonte: url,
        origem: OrigemLista.url,
        canais: canais,
        atualizadaEm: DateTime.now(),
        epgUrl: epgNormalizado,
      );
      final eraPrimeiraLista = _listas.isEmpty;
      await _armazenamento.salvarLista(lista);
      _listas = _armazenamento.carregarListas();
      if (eraPrimeiraLista || _listaAtiva == null) {
        await _ativarLista(lista);
      }
      _baixarEpgEmBackground(lista);
    });
  }

  /// Importa uma lista de um arquivo local.
  Future<void> importarPorArquivo({
    required String nome,
    required String caminho,
    String? epgUrl,
  }) async {
    await _executarComLoading(() async {
      final conteudo = await _carregador.lerDeArquivo(caminho);
      final canais = _parser.parse(conteudo);
      final epgNormalizado =
          (epgUrl == null || epgUrl.trim().isEmpty) ? null : epgUrl.trim();
      final lista = ListaM3U(
        nome: nome,
        fonte: caminho,
        origem: OrigemLista.arquivo,
        canais: canais,
        atualizadaEm: DateTime.now(),
        epgUrl: epgNormalizado,
      );
      final eraPrimeiraLista = _listas.isEmpty;
      await _armazenamento.salvarLista(lista);
      _listas = _armazenamento.carregarListas();
      if (eraPrimeiraLista || _listaAtiva == null) {
        await _ativarLista(lista);
      }
      _baixarEpgEmBackground(lista);
    });
  }

  /// Atualiza uma lista existente (so faz sentido para listas por URL).
  /// Preserva o epgUrl atual a menos que [novoEpgUrl] seja informado
  /// explicitamente.
  Future<void> atualizarLista(ListaM3U lista, {String? novoEpgUrl}) async {
    if (lista.origem != OrigemLista.url) {
      throw Exception('So e possivel atualizar listas importadas por URL.');
    }
    await importarPorUrl(
      nome: lista.nome,
      url: lista.fonte,
      epgUrl: novoEpgUrl ?? lista.epgUrl,
    );
  }

  /// Atualiza apenas a URL do EPG de uma lista existente, sem reimportar os
  /// canais. Se [novoEpgUrl] for null ou vazio, o EPG e removido.
  Future<void> atualizarEpgUrl(ListaM3U lista, String? novoEpgUrl) async {
    final limpo = (novoEpgUrl == null || novoEpgUrl.trim().isEmpty)
        ? null
        : novoEpgUrl.trim();
    // Instancia diretamente porque copyWith nao consegue setar null em campos
    // opcionais (usa `?? this.epgUrl`).
    final atualizada = ListaM3U(
      nome: lista.nome,
      fonte: lista.fonte,
      origem: lista.origem,
      canais: lista.canais,
      atualizadaEm: lista.atualizadaEm,
      epgUrl: limpo,
    );
    await _armazenamento.salvarLista(atualizada);
    _listas = _armazenamento.carregarListas();
    if (_listaAtiva?.id == lista.id) _listaAtiva = atualizada;
    if (limpo == null) {
      await _epg?.remover(lista.id);
    } else {
      _baixarEpgEmBackground(atualizada);
    }
    notifyListeners();
  }

  Future<void> removerLista(ListaM3U lista) async {
    await _armazenamento.removerLista(lista.id);
    await _epg?.remover(lista.id);
    final eraAtiva = _listaAtiva?.id == lista.id;
    _listas = _armazenamento.carregarListas();
    if (eraAtiva) {
      // Promove a primeira lista restante (se houver) para ativa.
      final substituta = _listas.isNotEmpty ? _listas.first : null;
      _listaAtiva = substituta;
      await _armazenamento.salvarIdListaAtiva(substituta?.id);
      if (substituta != null) {
        _epg?.carregarDoDisco(substituta.id);
        _baixarEpgEmBackground(substituta);
      }
    }
    notifyListeners();
  }

  void selecionarLista(ListaM3U lista) {
    _listaAtiva = lista;
    _busca = '';
    _canalSelecionadoDesktop = null;
    // Carrega EPG salvo do disco e dispara refresh em background se houver URL.
    _epg?.carregarDoDisco(lista.id);
    _baixarEpgEmBackground(lista);
    notifyListeners();
  }

  /// Marca [lista] como a lista ativa que abre por padrao ao iniciar o app.
  /// Persiste a escolha e atualiza o estado em memoria. Apenas UMA lista
  /// pode estar ativa de cada vez — chamar com outra lista substitui.
  Future<void> ativarLista(ListaM3U lista) async {
    await _ativarLista(lista);
    notifyListeners();
  }

  /// Verdadeiro se [lista] for a lista ativa atual.
  bool ehListaAtiva(ListaM3U lista) => _listaAtiva?.id == lista.id;

  Future<void> _ativarLista(ListaM3U lista) async {
    _listaAtiva = lista;
    _busca = '';
    _canalSelecionadoDesktop = null;
    await _armazenamento.salvarIdListaAtiva(lista.id);
    _epg?.carregarDoDisco(lista.id);
    _baixarEpgEmBackground(lista);
  }

  /// Renomeia uma lista existente preservando todos os outros campos.
  Future<void> renomearLista(ListaM3U lista, String novoNome) async {
    final nome = novoNome.trim();
    if (nome.isEmpty || nome == lista.nome) return;
    final atualizada = lista.copyWith(nome: nome);
    await _armazenamento.salvarLista(atualizada);
    _listas = _armazenamento.carregarListas();
    if (_listaAtiva?.id == lista.id) _listaAtiva = atualizada;
    notifyListeners();
  }

  /// Atualiza a URL fonte (M3U) de uma lista existente. Reimporta os canais
  /// a partir da nova URL. Apenas para listas com origem URL.
  Future<void> atualizarUrlLista(ListaM3U lista, String novaUrl) async {
    if (lista.origem != OrigemLista.url) {
      throw Exception('Apenas listas por URL podem ter a URL modificada.');
    }
    final url = novaUrl.trim();
    if (url.isEmpty || url == lista.fonte) return;
    await _executarComLoading(() async {
      final conteudo = await _carregador.baixarDeUrl(url);
      final canais = _parser.parse(conteudo);
      // Remove o registro antigo (chave = fonte) antes de salvar com nova chave.
      await _armazenamento.removerLista(lista.id);
      final atualizada = ListaM3U(
        nome: lista.nome,
        fonte: url,
        origem: OrigemLista.url,
        canais: canais,
        atualizadaEm: DateTime.now(),
        epgUrl: lista.epgUrl,
      );
      await _armazenamento.salvarLista(atualizada);
      _listas = _armazenamento.carregarListas();
      if (_listaAtiva?.id == lista.id) {
        await _ativarLista(atualizada);
      }
    });
  }

  /// Dispara um download/refresh do EPG sem bloquear a UI. Erros sao
  /// silenciados — EPG nao deve quebrar o fluxo principal.
  void _baixarEpgEmBackground(ListaM3U lista) {
    final url = lista.epgUrl;
    final epg = _epg;
    if (url == null || url.isEmpty || epg == null) return;
    epg
        .baixarEAtualizar(idLista: lista.id, url: url)
        .catchError((_) {/* silencioso */});
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
    _formatoNaoSuportado = null;
    notifyListeners();
    try {
      await acao();
    } on FormatoNaoSuportadoException catch (e) {
      _formatoNaoSuportado = e.mensagem; // 'hls' ou 'epg'
      _erro = e.mensagem;
    } catch (e) {
      _erro = e.toString();
    } finally {
      _carregando = false;
      notifyListeners();
    }
  }

  void limparErro() {
    _erro = null;
    _formatoNaoSuportado = null;
    notifyListeners();
  }

  // ===== QUALIDADE PREFERIDA (canais agrupados) =====

  /// Url da variante de qualidade lembrada para um canal agrupado, ou null.
  String? qualidadePreferida(String idGrupo) =>
      _armazenamento.qualidadeSalva(idGrupo);

  /// Lembra a qualidade escolhida para um canal agrupado.
  Future<void> salvarQualidadePreferida(String idGrupo, String url) =>
      _armazenamento.salvarQualidade(idGrupo, url);

  // ===== CATEGORIAS PERSONALIZADAS =====

  CategoriaPersonalizada? categoriaPersonalizadaPorId(String id) {
    for (final c in _categoriasPersonalizadas) {
      if (c.id == id) return c;
    }
    return null;
  }

  /// Cria uma categoria personalizada vazia e devolve o id gerado.
  Future<String> criarCategoriaPersonalizada(String nome) async {
    final cat = CategoriaPersonalizada.nova(nome.trim());
    await _armazenamento.salvarCategoriaPersonalizada(cat);
    _categoriasPersonalizadas =
        _armazenamento.carregarCategoriasPersonalizadas();
    notifyListeners();
    return cat.id;
  }

  Future<void> removerCategoriaPersonalizada(String id) async {
    await _armazenamento.removerCategoriaPersonalizada(id);
    _categoriasPersonalizadas =
        _armazenamento.carregarCategoriasPersonalizadas();
    notifyListeners();
  }

  Future<void> adicionarCanalACategoria(String idCategoria, Canal canal) async {
    final cat = categoriaPersonalizadaPorId(idCategoria);
    if (cat == null || cat.contem(canal)) return;
    await _armazenamento.salvarCategoriaPersonalizada(
      cat.copyWith(canais: [...cat.canais, canal]),
    );
    _categoriasPersonalizadas =
        _armazenamento.carregarCategoriasPersonalizadas();
    notifyListeners();
  }

  Future<void> removerCanalDeCategoria(String idCategoria, Canal canal) async {
    final cat = categoriaPersonalizadaPorId(idCategoria);
    if (cat == null) return;
    await _armazenamento.salvarCategoriaPersonalizada(
      cat.copyWith(
        canais: cat.canais.where((c) => c.id != canal.id).toList(),
      ),
    );
    _categoriasPersonalizadas =
        _armazenamento.carregarCategoriasPersonalizadas();
    notifyListeners();
  }

  // ===== PROGRESSO DE REPRODUCAO =====

  ProgressoCanal? obterProgresso(Canal canal) =>
      _armazenamento.obterProgresso(canal.url);

  Future<void> salvarProgresso(
      Canal canal, int posicaoSeg, int? duracaoSeg) async {
    final p = ProgressoCanal(
      url: canal.url,
      posicaoSeg: posicaoSeg,
      duracaoSeg: duracaoSeg,
      atualizadoEm: DateTime.now(),
    );
    await _armazenamento.salvarProgresso(p);
    _progressos = _armazenamento.carregarProgressos();
    notifyListeners();
  }

  Future<void> removerProgresso(Canal canal) async {
    await _armazenamento.removerProgresso(canal.url);
    _progressos = _armazenamento.carregarProgressos();
    notifyListeners();
  }

  // ===== MINHA LISTA =====

  static String _chaveMinhaLista(Object item) {
    if (item is Canal) return 'c:${item.url}';
    return 's:${(item as Serie).nome}';
  }

  bool ehMinhaLista(Object item) =>
      _minhaListaChaves.contains(_chaveMinhaLista(item));

  Future<void> alternarMinhaLista(Object item) async {
    final chave = _chaveMinhaLista(item);
    if (_minhaListaChaves.contains(chave)) {
      await _armazenamento.removerDeMinhaLista(chave);
    } else {
      await _armazenamento.adicionarAMinhaLista(chave);
    }
    _minhaListaChaves = _armazenamento.carregarMinhaLista();
    notifyListeners();
  }
}