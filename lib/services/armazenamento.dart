import 'package:hive_flutter/hive_flutter.dart';
import '../models/canal.dart';
import '../models/canal_assistido.dart';
import '../models/lista_m3u.dart';
import '../models/progresso_canal.dart';

/// Camada de persistencia local usando Hive (banco NoSQL leve).
///
/// Conceito: cada "box" do Hive e como uma gaveta de chave-valor.
/// Aqui mantemos tres gavetas: listas, favoritos e historico.
///
/// Como nao usamos code generation, salvamos Maps simples (toMap/fromMap)
/// em vez de objetos tipados - o codigo fica mais facil de evoluir.
class Armazenamento {
  static const _nomeBoxListas = 'listas';
  static const _nomeBoxFavoritos = 'favoritos';
  static const _nomeBoxHistorico = 'historico';
  static const _nomeBoxProgressos = 'progressos';

  static const _limiteHistorico = 50;

  late Box _boxListas;
  late Box _boxFavoritos;
  late Box _boxHistorico;
  late Box _boxProgressos;

  /// Inicializa o Hive e abre as boxes. Deve ser chamado UMA vez no main()
  /// antes de runApp.
  Future<void> inicializar() async {
    await Hive.initFlutter();
    _boxListas = await Hive.openBox(_nomeBoxListas);
    _boxFavoritos = await Hive.openBox(_nomeBoxFavoritos);
    _boxHistorico = await Hive.openBox(_nomeBoxHistorico);
    _boxProgressos = await Hive.openBox(_nomeBoxProgressos);
  }

  // ===== LISTAS M3U =====

  /// Salva ou atualiza uma lista pelo seu identificador (fonte).
  Future<void> salvarLista(ListaM3U lista) async {
    await _boxListas.put(lista.id, lista.toMap());
  }

  /// Apaga uma lista pelo identificador.
  Future<void> removerLista(String id) async {
    await _boxListas.delete(id);
  }

  /// Retorna todas as listas salvas, ordenadas pela data mais recente.
  List<ListaM3U> carregarListas() {
    final lista = _boxListas.values
        .map((m) => ListaM3U.fromMap(m as Map))
        .toList();
    lista.sort((a, b) => b.atualizadaEm.compareTo(a.atualizadaEm));
    return lista;
  }

  // ===== FAVORITOS =====

  Future<void> adicionarFavorito(Canal canal) async {
    await _boxFavoritos.put(canal.id, canal.toMap());
  }

  Future<void> removerFavorito(String idCanal) async {
    await _boxFavoritos.delete(idCanal);
  }

  bool ehFavorito(String idCanal) => _boxFavoritos.containsKey(idCanal);

  List<Canal> carregarFavoritos() {
    return _boxFavoritos.values
        .map((m) => Canal.fromMap(m as Map))
        .toList();
  }

  // ===== HISTORICO =====

  /// Registra que o usuario assistiu este canal agora.
  /// Se ja existia, atualiza apenas a data (e mantem unicidade pelo id).
  Future<void> registrarVisualizacao(Canal canal) async {
    final agora = DateTime.now();
    final item = CanalAssistido(canal: canal, ultimaVistaEm: agora);
    await _boxHistorico.put(canal.id, item.toMap());

    // Mantemos no maximo _limiteHistorico itens - apaga os mais antigos.
    if (_boxHistorico.length > _limiteHistorico) {
      final items = _boxHistorico.keys.toList();
      // Ordena por data ascendente para descobrir os mais antigos.
      final ordenados = items.map((chave) {
        final map = _boxHistorico.get(chave) as Map;
        return MapEntry(
          chave,
          DateTime.tryParse(map['ultimaVistaEm'] as String? ?? '') ??
              DateTime.now(),
        );
      }).toList()
        ..sort((a, b) => a.value.compareTo(b.value));

      final excedente = _boxHistorico.length - _limiteHistorico;
      for (var i = 0; i < excedente; i++) {
        await _boxHistorico.delete(ordenados[i].key);
      }
    }
  }

  /// Retorna o historico ordenado do mais recente ao mais antigo.
  List<CanalAssistido> carregarHistorico() {
    final lista = _boxHistorico.values
        .map((m) => CanalAssistido.fromMap(m as Map))
        .toList();
    lista.sort((a, b) => b.ultimaVistaEm.compareTo(a.ultimaVistaEm));
    return lista;
  }

  Future<void> limparHistorico() => _boxHistorico.clear();

  // ===== PROGRESSO DE REPRODUCAO =====

  Future<void> salvarProgresso(ProgressoCanal p) =>
      _boxProgressos.put(p.url, p.toMap());

  Future<void> removerProgresso(String url) => _boxProgressos.delete(url);

  ProgressoCanal? obterProgresso(String url) {
    final m = _boxProgressos.get(url);
    return m != null ? ProgressoCanal.fromMap(m as Map) : null;
  }

  List<ProgressoCanal> carregarProgressos() {
    final lista = _boxProgressos.values
        .map((m) => ProgressoCanal.fromMap(m as Map))
        .toList();
    lista.sort((a, b) => b.atualizadoEm.compareTo(a.atualizadoEm));
    return lista;
  }
}