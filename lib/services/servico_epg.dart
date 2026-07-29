import 'package:flutter/foundation.dart';
import '../models/canal.dart';
import '../models/programa.dart';
import 'armazenamento.dart';
import 'carregador_epg.dart';
import 'parser_epg.dart';

/// Servico central de EPG: orquestra download, parse, cache em memoria
/// e persistencia.
///
/// O cache em memoria evita reparsear o XMLTV (que pode ter MB+) toda vez
/// que abrimos um canal — guardamos a grade ja em estruturas Dart prontas.
class ServicoEpg extends ChangeNotifier {
  final Armazenamento _armazenamento;
  final CarregadorEpg _carregador;

  /// Grade por id de lista — `idLista -> tvgId -> List<Programa>`.
  /// Carregado preguicosamente do disco quando uma lista e selecionada.
  final Map<String, Map<String, List<Programa>>> _grades = {};

  /// Listas que ja sondamos no disco (mesmo que nao tenham EPG).
  final Set<String> _carregadasDoDisco = {};

  /// Listas para as quais um download esta em andamento — evita downloads
  /// duplicados quando o usuario abre varios canais em sequencia.
  final Set<String> _baixando = {};

  ServicoEpg({
    required Armazenamento armazenamento,
    CarregadorEpg? carregador,
  })
      // O `prefer_initializing_formals` sugere `required this._armazenamento`,
      // mas parametro NOMEADO nao pode comecar com underscore em Dart — a
      // sugestao simplesmente nao compila. Silenciado por isso.
      // ignore: prefer_initializing_formals
      : _armazenamento = armazenamento,
        _carregador = carregador ?? CarregadorEpg();

  // ===== ESTADO =====

  /// `true` se ha um download/parse em andamento para [idLista].
  bool estaCarregando(String idLista) => _baixando.contains(idLista);

  /// `true` se a grade ja foi carregada (do disco ou da rede) e tem programas.
  bool temEpg(String idLista) {
    final g = _grades[idLista];
    return g != null && g.isNotEmpty;
  }

  /// Data da ultima atualizacao da grade gravada no disco, ou null.
  DateTime? atualizadoEm(String idLista) =>
      _armazenamento.carregarEpgAtualizadoEm(idLista);

  // ===== CARREGAMENTO =====

  /// Carrega a grade salva no disco para [idLista] (sincrono, em memoria).
  /// Idempotente — chamadas seguintes para a mesma lista sao no-op.
  /// Nao baixa nada da rede.
  void carregarDoDisco(String idLista) {
    if (_carregadasDoDisco.contains(idLista)) return;
    _carregadasDoDisco.add(idLista);
    final disco = _armazenamento.carregarEpg(idLista);
    if (disco != null && disco.isNotEmpty) {
      _grades[idLista] = disco;
      notifyListeners();
    }
  }

  /// Baixa um XMLTV da [url], parseia e substitui a grade salva para [idLista].
  /// Idempotente em relacao a downloads simultaneos — o segundo call para a
  /// mesma lista retorna imediatamente.
  Future<void> baixarEAtualizar({
    required String idLista,
    required String url,
  }) async {
    if (_baixando.contains(idLista)) return;
    _baixando.add(idLista);
    notifyListeners();
    try {
      final texto = await _carregador.baixarDeUrl(url);
      // Parse em isolate quando arquivo for grande — XMLTV chega a 30MB+.
      final grade = await compute(_parseIsolate, texto);
      final agora = DateTime.now();
      await _armazenamento.salvarEpg(idLista, grade, agora);
      _grades[idLista] = grade;
      _carregadasDoDisco.add(idLista);
    } finally {
      _baixando.remove(idLista);
      notifyListeners();
    }
  }

  /// Remove a grade do disco e da memoria para uma lista.
  Future<void> remover(String idLista) async {
    await _armazenamento.removerEpg(idLista);
    _grades.remove(idLista);
    _carregadasDoDisco.remove(idLista);
    notifyListeners();
  }

  // ===== LOOKUPS =====

  /// Todos os programas conhecidos para [canal] na [idLista] (passados,
  /// atual e futuros), ja ordenados por inicio.
  List<Programa> programasPara({
    required String idLista,
    required Canal canal,
  }) {
    final tvgId = canal.tvgId;
    if (tvgId == null || tvgId.isEmpty) return const [];
    return _grades[idLista]?[tvgId] ?? const [];
  }

  /// Programa em exibicao agora, ou null se nao houver dados / nada bater.
  Programa? programaAtual({
    required String idLista,
    required Canal canal,
    DateTime? agora,
  }) {
    final lista = programasPara(idLista: idLista, canal: canal);
    if (lista.isEmpty) return null;
    final ref = agora ?? DateTime.now();
    // Como esta ordenada por inicio, fazemos um scan simples. EPG por canal
    // raramente passa de algumas centenas de entradas.
    for (final p in lista) {
      if (p.ehAtual(ref)) return p;
    }
    return null;
  }

  /// Agenda completa a partir do programa atual: atual + todos os futuros.
  /// Devolve uma lista vazia se nao houver dados ou se o ultimo programa
  /// conhecido ja ficou no passado.
  List<Programa> agenda({
    required String idLista,
    required Canal canal,
    DateTime? agora,
  }) {
    final lista = programasPara(idLista: idLista, canal: canal);
    if (lista.isEmpty) return const [];
    final ref = agora ?? DateTime.now();
    final atualIndex = lista.indexWhere((p) => p.ehAtual(ref));
    final inicio = atualIndex >= 0
        ? atualIndex
        : lista.indexWhere((p) => p.inicio.isAfter(ref));
    if (inicio < 0) return const [];
    return lista.sublist(inicio);
  }

  /// Versao limitada de [agenda] — atual + ate [quantidade] programas
  /// futuros. Util para previews compactos.
  List<Programa> agendaCurta({
    required String idLista,
    required Canal canal,
    int quantidade = 6,
    DateTime? agora,
  }) {
    final completa = agenda(idLista: idLista, canal: canal, agora: agora);
    if (completa.length <= quantidade) return completa;
    return completa.sublist(0, quantidade);
  }
}

/// Funcao top-level chamada por `compute()` para parsear em isolate.
/// Precisa ser top-level (ou static) para serializar no isolate.
Map<String, List<Programa>> _parseIsolate(String texto) =>
    ParserEpg().parse(texto);
