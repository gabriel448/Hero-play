import 'package:hive_flutter/hive_flutter.dart';
import '../models/canal.dart';
import '../models/canal_assistido.dart';
import '../models/categoria_personalizada.dart';
import '../models/lista_m3u.dart';
import '../models/perfil.dart';
import '../models/programa.dart';
import '../models/progresso_canal.dart';
import '../utils/chave_conteudo.dart';

/// Camada de persistencia local usando Hive (banco NoSQL leve).
///
/// Conceito: cada "box" do Hive e como uma gaveta de chave-valor.
///
/// Existem dois grupos de boxes:
///  - GLOBAIS (compartilhadas entre perfis): `listas`, `epg`, `perfis`,
///    `preferencias` (so flags globais como pulou_login / lista_ativa).
///  - POR PERFIL (biblioteca pessoal): `favoritos`, `historico`, `progressos`,
///    `qualidades`, `categorias_personalizadas`, `minha_lista`. Estas sao
///    abertas com sufixo `__<idPerfil>` e re-apontadas em [ativarPerfil]. Antes
///    de um perfil ser ativado elas ficam null e as leituras retornam vazio.
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
  static const _nomeBoxMinhaLista = 'minha_lista';
  static const _nomeBoxPerfis = 'perfis';

  /// Bases das boxes que sao isoladas por perfil.
  static const _basesPorPerfil = [
    _nomeBoxFavoritos,
    _nomeBoxHistorico,
    _nomeBoxProgressos,
    _nomeBoxQualidades,
    _nomeBoxCategorias,
    _nomeBoxMinhaLista,
  ];

  static const _limiteHistorico = 50;

  // Boxes globais.
  late Box _boxListas;
  late Box _boxPreferencias;
  late Box _boxEpg;
  late Box _boxPerfis;

  // Boxes por perfil — null ate [ativarPerfil] ser chamado.
  Box? _boxFavoritos;
  Box? _boxHistorico;
  Box? _boxProgressos;
  Box? _boxQualidades;
  Box? _boxCategorias;
  Box? _boxMinhaLista;

  String? _perfilAtivoId;

  /// Inicializa o Hive e abre as boxes GLOBAIS. Deve ser chamado UMA vez no
  /// main() antes de runApp. As boxes por perfil sao abertas sob demanda em
  /// [ativarPerfil], depois que o usuario escolhe "quem esta assistindo".
  Future<void> inicializar() async {
    await Hive.initFlutter();
    _boxListas = await Hive.openBox(_nomeBoxListas);
    _boxPreferencias = await Hive.openBox(_nomeBoxPreferencias);
    _boxEpg = await Hive.openBox(_nomeBoxEpg);
    _boxPerfis = await Hive.openBox(_nomeBoxPerfis);
  }

  // ===== PERFIS =====

  /// Id do perfil persistido como ativo na ultima sessao (ou null).
  String? obterIdPerfilAtivo() =>
      _boxPreferencias.get('perfil_ativo_id') as String?;

  /// Aponta as boxes por perfil para [perfilId], abrindo-as se necessario, e
  /// persiste a escolha. Idempotente para o mesmo perfil.
  Future<void> ativarPerfil(String perfilId) async {
    if (_perfilAtivoId == perfilId && _boxFavoritos != null) return;
    _perfilAtivoId = perfilId;
    _boxFavoritos = await Hive.openBox('${_nomeBoxFavoritos}__$perfilId');
    _boxHistorico = await Hive.openBox('${_nomeBoxHistorico}__$perfilId');
    _boxProgressos = await Hive.openBox('${_nomeBoxProgressos}__$perfilId');
    _boxQualidades = await Hive.openBox('${_nomeBoxQualidades}__$perfilId');
    _boxCategorias = await Hive.openBox('${_nomeBoxCategorias}__$perfilId');
    _boxMinhaLista = await Hive.openBox('${_nomeBoxMinhaLista}__$perfilId');
    await _boxPreferencias.put('perfil_ativo_id', perfilId);
  }

  /// Lista todos os perfis salvos, do mais antigo ao mais recente.
  List<Perfil> carregarPerfis() {
    final lista =
        _boxPerfis.values.map((m) => Perfil.fromMap(m as Map)).toList();
    lista.sort((a, b) => a.criadoEm.compareTo(b.criadoEm));
    return lista;
  }

  Future<void> salvarPerfil(Perfil p) => _boxPerfis.put(p.id, p.toMap());

  /// Remove um perfil e apaga toda a sua biblioteca pessoal (boxes proprias).
  Future<void> removerPerfil(String perfilId) async {
    await _boxPerfis.delete(perfilId);
    if (_perfilAtivoId == perfilId) {
      _perfilAtivoId = null;
      _boxFavoritos = _boxHistorico = _boxProgressos = null;
      _boxQualidades = _boxCategorias = _boxMinhaLista = null;
      await _boxPreferencias.delete('perfil_ativo_id');
    }
    for (final base in _basesPorPerfil) {
      await Hive.deleteBoxFromDisk('${base}__$perfilId');
    }
  }

  /// Copia a biblioteca legada (boxes sem sufixo, de antes dos perfis) para o
  /// perfil [perfilId]. So roda se o destino estiver vazio. Chamado uma unica
  /// vez quando o primeiro perfil e criado, para nao perder dados do usuario.
  Future<void> migrarLegadoParaPerfil(String perfilId) async {
    await ativarPerfil(perfilId);
    for (final base in _basesPorPerfil) {
      if (!await Hive.boxExists(base)) continue;
      final legado = await Hive.openBox(base);
      final destino = await Hive.openBox('${base}__$perfilId');
      if (legado.isNotEmpty && destino.isEmpty) {
        for (final chave in legado.keys) {
          await destino.put(chave, legado.get(chave));
        }
      }
      await legado.deleteFromDisk();
    }
  }

  /// Preferencias legadas (globais) usadas para semear a config do 1o perfil.
  String? obterIdiomaLegado() => _boxPreferencias.get('idioma') as String?;
  bool obterAutoQualidadeLegado() =>
      _boxPreferencias.get('auto_qualidade', defaultValue: false) as bool;
  String obterOrdemCategoriasLegado() =>
      _boxPreferencias.get('ordem_categorias', defaultValue: 'popularidade')
          as String;
  String obterOrdemCanaisLegado() =>
      _boxPreferencias.get('ordem_canais', defaultValue: 'padrao') as String;

  /// Apaga todos os perfis e as bibliotecas pessoais associadas. Usado no
  /// logout para nao misturar dados de contas diferentes no mesmo aparelho.
  Future<void> limparPerfis() async {
    for (final p in carregarPerfis()) {
      for (final base in _basesPorPerfil) {
        await Hive.deleteBoxFromDisk('${base}__${p.id}');
      }
    }
    await _boxPerfis.clear();
    _perfilAtivoId = null;
    _boxFavoritos = _boxHistorico = _boxProgressos = null;
    _boxQualidades = _boxCategorias = _boxMinhaLista = null;
    await _boxPreferencias.delete('perfil_ativo_id');
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

  // ===== CATEGORIAS PERSONALIZADAS (por perfil) =====

  /// Salva ou atualiza uma categoria personalizada pelo seu id.
  Future<void> salvarCategoriaPersonalizada(CategoriaPersonalizada c) async =>
      _boxCategorias?.put(c.id, c.toMap());

  /// Apaga uma categoria personalizada pelo id.
  Future<void> removerCategoriaPersonalizada(String id) async =>
      _boxCategorias?.delete(id);

  /// Retorna todas as categorias personalizadas, da mais antiga a mais recente.
  List<CategoriaPersonalizada> carregarCategoriasPersonalizadas() {
    final box = _boxCategorias;
    if (box == null) return [];
    final lista = box.values
        .map((m) => CategoriaPersonalizada.fromMap(m as Map))
        .toList();
    lista.sort((a, b) => a.criadaEm.compareTo(b.criadaEm));
    return lista;
  }

  // ===== QUALIDADE PREFERIDA (canais agrupados, por perfil) =====

  /// Url da variante de qualidade que o usuario escolheu por ultimo para
  /// um canal agrupado, ou null se ele nunca trocou a qualidade.
  String? qualidadeSalva(String idGrupo) =>
      _boxQualidades?.get(idGrupo) as String?;

  /// Lembra a qualidade (url da variante) escolhida para um canal agrupado.
  Future<void> salvarQualidade(String idGrupo, String url) async =>
      _boxQualidades?.put(idGrupo, url);

  // ===== PREFERENCIAS GLOBAIS =====
  //
  // As preferencias por perfil (idioma, auto-qualidade, ordenacoes) vivem no
  // modelo [Perfil], nao aqui. Esta box guarda so flags globais ao aparelho.

  /// Se o usuario escolheu usar o app sem conta (pulou a tela de login).
  bool obterPulouLogin() =>
      _boxPreferencias.get('pulou_login', defaultValue: false) as bool;

  Future<void> salvarPulouLogin(bool valor) =>
      _boxPreferencias.put('pulou_login', valor);

  /// Volume do player (0..150; 100 = sem atenuacao, depende do volume do
  /// aparelho). Padrao 100 — global ao app. Persistido quando o usuario ajusta.
  double obterVolume() =>
      (_boxPreferencias.get('volume', defaultValue: 100.0) as num).toDouble();

  Future<void> salvarVolume(double valor) =>
      _boxPreferencias.put('volume', valor);

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

  /// Salva uma lista a partir de um mapa ja serializado (no formato de
  /// [ListaM3U.toMap]). Usado pela sincronizacao, que monta o mapa dentro de
  /// um isolate — assim a serializacao pesada nao roda na thread da UI.
  Future<void> salvarListaBruta(String id, Map<String, dynamic> mapa) async {
    await _boxListas.put(id, mapa);
  }

  /// Apaga uma lista pelo identificador.
  Future<void> removerLista(String id) async {
    await _boxListas.delete(id);
  }

  /// Apaga TODAS as listas locais (usado ao trocar de conta no logout, para
  /// nao misturar listas de usuarios diferentes no mesmo aparelho).
  Future<void> limparListas() async {
    await _boxListas.clear();
    await _boxPreferencias.delete('lista_ativa_id');
  }

  /// Retorna todas as listas salvas, ordenadas pela data mais recente.
  List<ListaM3U> carregarListas() {
    final lista = _boxListas.values
        .map((m) => ListaM3U.fromMap(m as Map))
        .toList();
    lista.sort((a, b) => b.atualizadaEm.compareTo(a.atualizadaEm));
    return lista;
  }

  // ===== FAVORITOS (por perfil) =====

  Future<void> adicionarFavorito(Canal canal) async {
    await _boxFavoritos?.put(chaveBiblioteca(canal), canal.toMap());
  }

  Future<void> removerFavorito(Canal canal) async {
    await _boxFavoritos?.delete(chaveBiblioteca(canal));
  }

  bool ehFavorito(Canal canal) =>
      _boxFavoritos?.containsKey(chaveBiblioteca(canal)) ?? false;

  List<Canal> carregarFavoritos() {
    final box = _boxFavoritos;
    if (box == null) return [];
    return box.values.map((m) => Canal.fromMap(m as Map)).toList();
  }

  // ===== HISTORICO (por perfil) =====

  /// Registra que o usuario assistiu este canal agora.
  /// Se ja existia, atualiza apenas a data (e mantem unicidade pelo id).
  Future<void> registrarVisualizacao(Canal canal) async {
    final box = _boxHistorico;
    if (box == null) return;
    final agora = DateTime.now();
    final item = CanalAssistido(canal: canal, ultimaVistaEm: agora);
    await box.put(chaveBiblioteca(canal), item.toMap());

    // Mantemos no maximo _limiteHistorico itens - apaga os mais antigos.
    if (box.length > _limiteHistorico) {
      final items = box.keys.toList();
      // Ordena por data ascendente para descobrir os mais antigos.
      final ordenados = items.map((chave) {
        final map = box.get(chave) as Map;
        return MapEntry(
          chave,
          DateTime.tryParse(map['ultimaVistaEm'] as String? ?? '') ??
              DateTime.now(),
        );
      }).toList()
        ..sort((a, b) => a.value.compareTo(b.value));

      final excedente = box.length - _limiteHistorico;
      for (var i = 0; i < excedente; i++) {
        await box.delete(ordenados[i].key);
      }
    }
  }

  /// Retorna o historico ordenado do mais recente ao mais antigo.
  List<CanalAssistido> carregarHistorico() {
    final box = _boxHistorico;
    if (box == null) return [];
    final lista =
        box.values.map((m) => CanalAssistido.fromMap(m as Map)).toList();
    lista.sort((a, b) => b.ultimaVistaEm.compareTo(a.ultimaVistaEm));
    return lista;
  }

  Future<void> limparHistorico() async => _boxHistorico?.clear();

  // ===== PROGRESSO DE REPRODUCAO (por perfil) =====

  Future<void> salvarProgresso(ProgressoCanal p) async =>
      _boxProgressos?.put(chaveConteudo(p.url), p.toMap());

  Future<void> removerProgresso(String url) async =>
      _boxProgressos?.delete(chaveConteudo(url));

  ProgressoCanal? obterProgresso(String url) {
    final m = _boxProgressos?.get(chaveConteudo(url));
    return m != null ? ProgressoCanal.fromMap(m as Map) : null;
  }

  List<ProgressoCanal> carregarProgressos() {
    final box = _boxProgressos;
    if (box == null) return [];
    final lista =
        box.values.map((m) => ProgressoCanal.fromMap(m as Map)).toList();
    lista.sort((a, b) => b.atualizadoEm.compareTo(a.atualizadoEm));
    return lista;
  }

  // ===== MINHA LISTA (por perfil) =====

  // Chaves no formato "c:{url}" (Canal/filme) ou "s:{nome}" (Serie).
  static const _keyMinhaLista = 'keys';

  List<String> carregarMinhaLista() {
    final raw = _boxMinhaLista?.get(_keyMinhaLista);
    if (raw == null) return [];
    return List<String>.from(raw as List);
  }

  Future<void> adicionarAMinhaLista(String chave) async {
    final box = _boxMinhaLista;
    if (box == null) return;
    final lista = carregarMinhaLista();
    if (!lista.contains(chave)) {
      lista.add(chave);
      await box.put(_keyMinhaLista, lista);
    }
  }

  Future<void> removerDeMinhaLista(String chave) async {
    final box = _boxMinhaLista;
    if (box == null) return;
    final lista = carregarMinhaLista();
    if (lista.remove(chave)) {
      await box.put(_keyMinhaLista, lista);
    }
  }

  bool ehMinhaLista(String chave) => carregarMinhaLista().contains(chave);
}