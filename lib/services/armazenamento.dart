import 'package:hive_flutter/hive_flutter.dart';
import '../models/canal.dart';
import '../models/canal_assistido.dart';
import '../models/categoria_personalizada.dart';
import '../models/lista_m3u.dart';
import '../models/programa.dart';
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
  static const _nomeBoxPreferencias = 'preferencias';
  static const _nomeBoxQualidades = 'qualidades';
  static const _nomeBoxCategorias = 'categorias_personalizadas';
  static const _nomeBoxEpg = 'epg';

  static const _limiteHistorico = 50;

  late Box _boxListas;
  late Box _boxFavoritos;
  late Box _boxHistorico;
  late Box _boxProgressos;
  late Box _boxPreferencias;
  late Box _boxQualidades;
  late Box _boxCategorias;
  late Box _boxEpg;

  /// Inicializa o Hive e abre as boxes. Deve ser chamado UMA vez no main()
  /// antes de runApp.
  Future<void> inicializar() async {
    await Hive.initFlutter();
    _boxListas = await Hive.openBox(_nomeBoxListas);
    _boxFavoritos = await Hive.openBox(_nomeBoxFavoritos);
    _boxHistorico = await Hive.openBox(_nomeBoxHistorico);
    _boxProgressos = await Hive.openBox(_nomeBoxProgressos);
    _boxPreferencias = await Hive.openBox(_nomeBoxPreferencias);
    _boxQualidades = await Hive.openBox(_nomeBoxQualidades);
    _boxCategorias = await Hive.openBox(_nomeBoxCategorias);
    _boxEpg = await Hive.openBox(_nomeBoxEpg);
  }

  // ===== EPG (programacao por lista) =====

  /// Salva a grade EPG inteira (mapa tvgId -> programas) para uma lista,
  /// junto com a data em que foi baixada. A chave da box e o id da lista.
  Future<void> salvarEpg(
    String idLista,
    Map<String, List<Programa>> grade,
    DateTime atualizadoEm,
  ) {
    final canais = <String, dynamic>{};
    grade.forEach((tvgId, programas) {
      canais[tvgId] = programas.map((p) => p.toMap()).toList();
    });
    return _boxEpg.put(idLista, {
      'atualizadoEm': atualizadoEm.toIso8601String(),
      'canais': canais,
    });
  }

  /// Carrega a grade EPG salva para uma lista, ou null se nao houver.
  Map<String, List<Programa>>? carregarEpg(String idLista) {
    final raw = _boxEpg.get(idLista);
    if (raw == null) return null;
    final canais = (raw as Map)['canais'];
    if (canais is! Map) return null;
    final mapa = <String, List<Programa>>{};
    canais.forEach((tvgId, lista) {
      if (lista is! List) return;
      mapa[tvgId.toString()] = lista
          .map((m) => Programa.fromMap(m as Map))
          .toList();
    });
    return mapa;
  }

  /// Data da ultima atualizacao do EPG salvo para a lista, ou null.
  DateTime? carregarEpgAtualizadoEm(String idLista) {
    final raw = _boxEpg.get(idLista);
    if (raw == null) return null;
    final iso = (raw as Map)['atualizadoEm'] as String?;
    return iso == null ? null : DateTime.tryParse(iso);
  }

  Future<void> removerEpg(String idLista) => _boxEpg.delete(idLista);

  // ===== CATEGORIAS PERSONALIZADAS =====

  /// Salva ou atualiza uma categoria personalizada pelo seu id.
  Future<void> salvarCategoriaPersonalizada(CategoriaPersonalizada c) =>
      _boxCategorias.put(c.id, c.toMap());

  /// Apaga uma categoria personalizada pelo id.
  Future<void> removerCategoriaPersonalizada(String id) =>
      _boxCategorias.delete(id);

  /// Retorna todas as categorias personalizadas, da mais antiga a mais recente.
  List<CategoriaPersonalizada> carregarCategoriasPersonalizadas() {
    final lista = _boxCategorias.values
        .map((m) => CategoriaPersonalizada.fromMap(m as Map))
        .toList();
    lista.sort((a, b) => a.criadaEm.compareTo(b.criadaEm));
    return lista;
  }

  // ===== QUALIDADE PREFERIDA (canais agrupados) =====

  /// Url da variante de qualidade que o usuario escolheu por ultimo para
  /// um canal agrupado, ou null se ele nunca trocou a qualidade.
  String? qualidadeSalva(String idGrupo) =>
      _boxQualidades.get(idGrupo) as String?;

  /// Lembra a qualidade (url da variante) escolhida para um canal agrupado.
  Future<void> salvarQualidade(String idGrupo, String url) =>
      _boxQualidades.put(idGrupo, url);

  // ===== PREFERENCIAS =====

  /// Codigo do idioma escolhido (ex.: 'pt-BR'), ou null se ainda nao escolheu.
  String? obterIdioma() => _boxPreferencias.get('idioma') as String?;

  Future<void> salvarIdioma(String codigo) =>
      _boxPreferencias.put('idioma', codigo);

  bool obterAutoQualidade() =>
      _boxPreferencias.get('auto_qualidade', defaultValue: false) as bool;

  Future<void> salvarAutoQualidade(bool valor) =>
      _boxPreferencias.put('auto_qualidade', valor);

  /// Id da lista marcada como ativa pelo usuario (a que abre por padrao ao
  /// iniciar o app). Apenas UMA lista pode estar ativa de cada vez.
  String? obterIdListaAtiva() =>
      _boxPreferencias.get('lista_ativa_id') as String?;

  Future<void> salvarIdListaAtiva(String? id) async {
    if (id == null) {
      await _boxPreferencias.delete('lista_ativa_id');
    } else {
      await _boxPreferencias.put('lista_ativa_id', id);
    }
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