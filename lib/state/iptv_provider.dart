import 'package:flutter/foundation.dart';
import '../models/canal.dart';
import '../models/canal_assistido.dart';
import '../models/categoria_personalizada.dart';
import '../models/lista_m3u.dart';
import '../models/lista_remota.dart';
import '../models/progresso_canal.dart';
import '../services/armazenamento.dart';
import '../services/carregador_lista.dart';
import '../services/parser_m3u.dart';
import '../services/servico_conta.dart';
import '../services/servico_epg.dart';
import '../utils/chave_conteudo.dart';

/// Provider central do app: mantem o estado e expoe acoes para a UI.
///
/// Usamos [ChangeNotifier] (do Flutter) - quando algo muda chamamos
/// [notifyListeners] e as telas que escutam se redesenham automaticamente.
class IptvProvider extends ChangeNotifier {
  final Armazenamento _armazenamento;
  final CarregadorLista _carregador;
  final ParserM3U _parser;
  final ServicoEpg? _epg;
  // Conta na nuvem (Supabase). Quando presente e logado, as acoes de lista
  // tambem sao refletidas no Supabase. Opcional: sem ele o app roda local-only.
  final ServicoConta? _conta;

  IptvProvider({
    required Armazenamento armazenamento,
    CarregadorLista? carregador,
    ParserM3U? parser,
    ServicoEpg? epg,
    ServicoConta? conta,
  })  :
        // ignore: prefer_initializing_formals
        _armazenamento = armazenamento,
        _carregador = carregador ?? CarregadorLista(),
        _parser = parser ?? ParserM3U(),
        // ignore: prefer_initializing_formals
        _epg = epg,
        // ignore: prefer_initializing_formals
        _conta = conta;

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
  // Sincronizacao com a nuvem em andamento (puxando/empurrando definicoes).
  bool _sincronizando = false;
  int _progressoSync = 0; // quantas listas ja foram baixadas nesta sincronizacao
  int _totalSync = 0;     // total de listas a baixar nesta sincronizacao
  // True durante a primeira sincronizacao apos login (quando nao havia listas
  // locais). Permanece true ate o sync terminar, mesmo que listas ja estejam
  // disponiveis — usado pelo app.dart para manter a tela de importacao visivel
  // ate o progresso completo.
  bool _primeiraSync = false;
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
  bool get sincronizando => _sincronizando;
  String? get erro => _erro;
  int get progressoSync => _progressoSync;
  int get totalSync => _totalSync;
  bool get primeiraSync => _primeiraSync;
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

  /// Recarrega para a memoria a biblioteca pessoal do perfil ativo (favoritos,
  /// historico, progressos, "minha lista", categorias). Chamado pela tela de
  /// perfis logo apos `PerfilProvider.selecionar`, que ja apontou as boxes do
  /// Hive para o perfil escolhido. As listas M3U sao compartilhadas e nao
  /// precisam recarregar aqui.
  void recarregarDadosDoPerfil() {
    _favoritos = _armazenamento.carregarFavoritos();
    _historico = _armazenamento.carregarHistorico();
    _progressos = _armazenamento.carregarProgressos();
    _categoriasPersonalizadas =
        _armazenamento.carregarCategoriasPersonalizadas();
    _minhaListaChaves = _armazenamento.carregarMinhaLista();
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
      _espelharSalvar(nome: nome, fonteUrl: url, epgUrl: epgNormalizado);
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
    if (lista.origem == OrigemLista.url) {
      _espelharSalvar(nome: lista.nome, fonteUrl: lista.fonte, epgUrl: limpo);
    }
    notifyListeners();
  }

  Future<void> removerLista(ListaM3U lista) async {
    await _armazenamento.removerLista(lista.id);
    await _epg?.remover(lista.id);
    if (lista.origem == OrigemLista.url) _espelharRemover(lista.fonte);
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
    if (lista.origem == OrigemLista.url) {
      _espelharSalvar(
        nome: nome,
        fonteUrl: lista.fonte,
        epgUrl: lista.epgUrl,
      );
    }
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
      _espelharTrocaFonte(
        fonteAntiga: lista.fonte,
        fonteNova: url,
        nome: lista.nome,
        epgUrl: lista.epgUrl,
      );
    });
  }

  // ===== SINCRONIZACAO COM A NUVEM (SUPABASE) =====

  /// Traz para o aparelho exatamente as listas da conta logada — a conta e a
  /// fonte da verdade. Independente do que houver no cache local:
  ///  - PODA do cache as listas por URL que nao pertencem a esta conta
  ///    (ex.: listas adicionadas antes de logar / de outra sessao);
  ///  - baixa/parseia e salva as listas da conta que faltam no aparelho;
  ///  - alinha nome/EPG das que existem dos dois lados (a nuvem manda).
  ///
  /// Listas por arquivo local sao preservadas (nao podem existir na nuvem).
  /// Silenciosa: falhas de rede nao quebram o app nem apagam o cache (a poda
  /// so ocorre apos um fetch bem-sucedido). Chamar apos o login e no startup
  /// quando ja houver sessao salva.
  Future<void> sincronizarDoSupabase() async {
    final conta = _conta;
    debugPrint('[SYNC] inicio conta=${conta != null} logado=${conta?.estaLogado}');
    if (conta == null || !conta.estaLogado) return;
    _sincronizando = true;
    // Na primeira sincronizacao (sem listas locais) seguramos a tela de
    // importacao ate TODAS as listas terminarem de baixar — so liberamos no
    // finally. Assim a barra de progresso vai de 0 ate o total de verdade, em
    // vez de pular para a home no meio do caminho.
    if (_listas.isEmpty) _primeiraSync = true;
    notifyListeners();
    try {
      // Timeout defensivo: sem isto, se a Edge Function nao responder a tela
      // "Conectando a sua conta" fica presa pra sempre (o finally nunca roda).
      debugPrint('[SYNC] chamando listarListas...');
      final remotas = await conta
          .listarListas()
          .timeout(const Duration(seconds: 20));
      debugPrint('[SYNC] listarListas retornou ${remotas.length} listas');
      final urlsRemotas = {for (final r in remotas) r.fonteUrl};

      // 1) Poda: remove do cache as listas por URL que nao sao desta conta.
      var podou = false;
      for (final l
          in _listas.where((l) => l.origem == OrigemLista.url).toList()) {
        if (!urlsRemotas.contains(l.fonte)) {
          await _armazenamento.removerLista(l.id);
          await _epg?.remover(l.id);
          podou = true;
        }
      }
      if (podou) _listas = _armazenamento.carregarListas();

      // 2) Alinha metadados das que ja existem (barato) e baixa em PARALELO
      //    (em lotes) as que faltam — varias listas ao mesmo tempo em vez de
      //    uma de cada vez. Cada lista e isolada: uma falha (URL morta/formato
      //    invalido) nao impede as demais.
      final fontesLocais = {for (final l in _listas) l.fonte};
      for (final r in remotas.where((r) => fontesLocais.contains(r.fonteUrl))) {
        try {
          await _alinharMetadados(r);
        } catch (_) {/* ignora */}
      }

      // Dedup por URL: a conta pode ter linhas repetidas apontando para a mesma
      // fonte — sem isto, baixavamos a MESMA lista gigante 2x em paralelo.
      final vistos = <String>{};
      final aBaixar = remotas
          .where((r) => !fontesLocais.contains(r.fonteUrl))
          .where((r) => vistos.add(r.fonteUrl))
          .toList();
      _progressoSync = 0;
      _totalSync = aBaixar.length;
      debugPrint('[SYNC] totalSync=$_totalSync (aBaixar=${aBaixar.length}) '
          'listasLocais=${_listas.length}');
      // Empurra o total para a tela de importacao (a barra usa progresso/total).
      notifyListeners();

      // Baixa de 2 em 2 (o mesmo servidor Xtream costuma estrangular varias
      // conexoes simultaneas — 4 em paralelo deixava cada uma muito mais lenta).
      const maxParalelo = 2;
      for (var i = 0; i < aBaixar.length; i += maxParalelo) {
        final lote = aBaixar.skip(i).take(maxParalelo);
        await Future.wait(lote.map((r) async {
          try {
            debugPrint('[SYNC] baixando ${r.fonteUrl}');
            // Timeout POR LISTA: um download/parse travado nao pode prender o
            // sync (nem a tela de importacao) indefinidamente.
            await _baixarParsearSalvar(
              nome: r.nome,
              url: r.fonteUrl,
              epgUrl: r.epgUrl,
            ).timeout(const Duration(seconds: 90));
            debugPrint('[SYNC] baixou OK ${r.fonteUrl}');
            // So atualiza o progresso (a barra anda). NAO recarregamos do disco
            // aqui: desserializar centenas de milhares de canais na thread da UI
            // a cada download travava tudo. Carregamos uma unica vez no fim.
            _progressoSync++;
            notifyListeners();
          } catch (_) {/* pula esta lista (timeout/erro) */}
        }));
      }

      // Recarrega tudo UMA vez no fim (em vez de a cada download).
      _listas = _armazenamento.carregarListas();
      // Se a lista ativa foi podada (era sem-conta), elege outra.
      final ativaExiste = _listaAtiva != null &&
          _listas.any((l) => l.id == _listaAtiva!.id);
      if (!ativaExiste) {
        _listaAtiva = null;
        _restaurarListaAtiva();
      }
    } catch (e, st) {
      // Sincronizacao e best-effort; mantem o que ja existe localmente.
      debugPrint('[SYNC] ERRO: $e\n$st');
    } finally {
      debugPrint('[SYNC] finally -> primeiraSync=false, sincronizando=false');
      _sincronizando = false;
      _primeiraSync = false;
      notifyListeners();
    }
  }

  /// Baixa uma lista por URL, parseia + serializa DENTRO de um isolate e grava
  /// o mapa pronto no Hive. Tudo o que e pesado (parse e toMap dos milhares de
  /// canais) sai da thread da UI. Nao dispara EPG aqui (feito so para a lista
  /// ativa apos a sincronizacao) e nao reespelha na nuvem (evita laco).
  Future<void> _baixarParsearSalvar({
    required String nome,
    required String url,
    String? epgUrl,
  }) async {
    final conteudo = await _carregador.baixarDeUrl(url);
    final mapa = await compute(
      _parseListaMapIsolate,
      <String?>[nome, url, epgUrl, conteudo],
    );
    await _armazenamento.salvarListaBruta(url, mapa);
  }

  /// Alinha nome/EPG de uma lista local com a versao da nuvem, se diferirem.
  /// Nao reparseia os canais (so metadados).
  Future<void> _alinharMetadados(ListaRemota r) async {
    final local = _listas.firstWhere(
      (l) => l.fonte == r.fonteUrl,
      orElse: () => _listas.first,
    );
    if (local.fonte != r.fonteUrl) return;
    if (local.nome == r.nome && local.epgUrl == r.epgUrl) return;
    final atualizada = ListaM3U(
      nome: r.nome,
      fonte: local.fonte,
      origem: local.origem,
      canais: local.canais,
      atualizadaEm: local.atualizadaEm,
      epgUrl: r.epgUrl,
    );
    await _armazenamento.salvarLista(atualizada);
    if (_listaAtiva?.id == local.id) _listaAtiva = atualizada;
  }

  /// Apaga as listas locais (cache). Usado no logout para nao misturar contas.
  Future<void> limparListasLocais() async {
    await _armazenamento.limparListas();
    _listas = [];
    _listaAtiva = null;
    notifyListeners();
  }

  // ── Espelhamento na nuvem (best-effort, nao bloqueia a UI) ───────────────

  void _espelharSalvar({
    required String nome,
    required String fonteUrl,
    String? epgUrl,
  }) {
    final conta = _conta;
    if (conta == null || !conta.estaLogado) return;
    conta
        .salvarLista(nome: nome, fonteUrl: fonteUrl, epgUrl: epgUrl)
        .catchError((_) {/* silencioso */});
  }

  void _espelharRemover(String fonteUrl) {
    final conta = _conta;
    if (conta == null || !conta.estaLogado) return;
    conta.removerLista(fonteUrl).catchError((_) {/* silencioso */});
  }

  void _espelharTrocaFonte({
    required String fonteAntiga,
    required String fonteNova,
    required String nome,
    String? epgUrl,
  }) {
    final conta = _conta;
    if (conta == null || !conta.estaLogado) return;
    conta
        .trocarFonteLista(
          fonteAntiga: fonteAntiga,
          fonteNova: fonteNova,
          nome: nome,
          epgUrl: epgUrl,
        )
        .catchError((_) {/* silencioso */});
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

  bool ehFavorito(Canal canal) => _armazenamento.ehFavorito(canal);

  Future<void> alternarFavorito(Canal canal) async {
    if (ehFavorito(canal)) {
      await _armazenamento.removerFavorito(canal);
    } else {
      await _armazenamento.adicionarFavorito(canal);
    }
    _favoritos = _armazenamento.carregarFavoritos();
    notifyListeners();
  }

  /// Dado um canal salvo (favorito/historico), tenta achar a versao ATUAL na
  /// lista ativa pela chave estavel (tvgId ou id de conteudo) — assim a URL
  /// fica fresca mesmo se o provedor trocou o IP/dominio. Sem a lista (ou sem
  /// match) devolve o proprio canal salvo (modo offline).
  Canal resolverCanalAtual(Canal salvo) {
    final lista = _listaAtiva;
    if (lista == null) return salvo;
    final tvg = salvo.tvgId?.trim();
    final ck = chaveConteudo(salvo.url);
    for (final c in lista.canais) {
      if (tvg != null && tvg.isNotEmpty && c.tvgId?.trim() == tvg) return c;
      if (chaveConteudo(c.url) == ck) return c;
    }
    return salvo;
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

  static String _chaveMinhaLista(Object item) => chaveItemMinhaLista(item);

  bool ehMinhaLista(Object item) =>
      _minhaListaChaves.contains(_chaveMinhaLista(item));

  Future<void> alternarMinhaLista(Object item) async {
    final chave = _chaveMinhaLista(item);
    final estava = _minhaListaChaves.contains(chave);
    // Atualizacao OTIMISTA: reflete na UI imediatamente (sem esperar o disco),
    // depois persiste. Garante que o botao vire "na hora" do clique.
    _minhaListaChaves = List.of(_minhaListaChaves);
    if (estava) {
      _minhaListaChaves.remove(chave);
    } else {
      _minhaListaChaves.add(chave);
    }
    notifyListeners();
    if (estava) {
      await _armazenamento.removerDeMinhaLista(chave);
    } else {
      await _armazenamento.adicionarAMinhaLista(chave);
    }
  }
}

/// Funcao top-level para `compute()`: dentro de um isolate, parseia a M3U e ja
/// devolve o mapa pronto para o Hive (no formato de [ListaM3U.toMap]). Assim
/// tanto o parse quanto a serializacao dos milhares de canais ficam fora da
/// thread da UI. `args` = [nome, url, epgUrl, conteudo].
Map<String, dynamic> _parseListaMapIsolate(List<String?> args) {
  final nome = args[0]!;
  final url = args[1]!;
  final epg = args[2];
  final conteudo = args[3]!;
  final canais = ParserM3U().parse(conteudo);
  final epgN = (epg == null || epg.trim().isEmpty) ? null : epg.trim();
  return {
    'nome': nome,
    'fonte': url,
    'origem': OrigemLista.url.name,
    'canais': [for (final c in canais) c.toMap()],
    'atualizadaEm': DateTime.now().toIso8601String(),
    'epgUrl': ?epgN,
  };
}