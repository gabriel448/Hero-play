import 'dart:ui' show Rect;

import 'package:flutter/foundation.dart';

import '../models/perfil.dart';
import '../services/armazenamento.dart';

/// Estado dos perfis de uso. Cada aparelho tem ate
/// [Perfil.maxPerfis] perfis, cada um com config e biblioteca proprias.
///
/// Fluxo: ao abrir o app, [perfilConfirmado] e `false` — o `app.dart` mostra a
/// tela "Quem esta assistindo". Quando o usuario escolhe um perfil em
/// [selecionar], as boxes por perfil do [Armazenamento] sao apontadas para ele
/// e [perfilConfirmado] vira `true`, liberando a home.
///
/// Tudo e LOCAL (Hive): nao ha conta nem sincronizacao na nuvem — a identidade
/// do usuario e o proprio aparelho (ver `services/dispositivo.dart`).
class PerfilProvider extends ChangeNotifier {
  final Armazenamento _armazenamento;

  PerfilProvider(this._armazenamento);

  List<Perfil> _perfis = [];
  Perfil? _ativo;
  // Flag de sessao: comeca falsa a cada abertura para forcar a tela de perfis.
  bool _confirmado = false;

  List<Perfil> get perfis => List.unmodifiable(_perfis);
  Perfil? get perfilAtivo => _ativo;
  bool get perfilConfirmado => _confirmado;
  bool get podeAdicionar => _perfis.length < Perfil.maxPerfis;
  int get maximo => Perfil.maxPerfis;

  /// Carrega os perfis do disco. Nao ativa nenhum (a tela de perfis decide).
  void inicializar() {
    _perfis = _armazenamento.carregarPerfis();
    notifyListeners();
  }

  /// Escolhe o perfil ativo da sessao: aponta as boxes do Hive para ele e
  /// libera a home. Quem recarrega a biblioteca em memoria e o `IptvProvider`
  /// (via `recarregarDadosDoPerfil`) — a tela de perfis orquestra os dois.
  Future<void> selecionar(Perfil p) async {
    await prepararPerfil(p);
    confirmar();
  }

  /// Ativa o perfil (aponta as boxes, define como ativo) **sem** liberar a home.
  /// Usado pela animacao de entrada da `TelaPerfis`, que mostra o avatar
  /// carregando no centro antes de chamar [confirmar].
  Future<void> prepararPerfil(Perfil p) async {
    await _armazenamento.ativarPerfil(p.id);
    _ativo = p;
    notifyListeners();
  }

  /// Conclui a entrada no perfil: marca a sessao como confirmada — o `app.dart`
  /// entao troca da `TelaPerfis` para a home.
  void confirmar() {
    if (_confirmado) return;
    _confirmado = true;
    notifyListeners();
  }

  // ── Animacao de entrada (origem do toque) ─────────────────────────────────
  //
  // A `TelaPerfis` registra aqui o rect (global) do avatar tocado; a home le e
  // consome esse valor uma vez para animar o avatar da grade ate o canto. E so
  // um dado transiente de UI para coordenar a transicao entre as duas telas.
  Rect? _origemEntrada;
  Rect? get origemEntrada => _origemEntrada;

  void marcarEntrada(Rect origem) => _origemEntrada = origem;
  void consumirEntrada() => _origemEntrada = null;

  /// Cria um perfil novo (respeitando o limite) e devolve-o. O primeiro perfil
  /// herda as preferencias legadas do app e adota a biblioteca que existia
  /// antes do sistema de perfis (migracao unica).
  Future<Perfil?> criar({required String nome, required String icone}) async {
    if (!podeAdicionar) return null;
    final ehPrimeiro = _perfis.isEmpty;
    final p = Perfil.novo(
      nome: nome.trim().isEmpty ? 'Perfil' : nome.trim(),
      icone: icone,
      idioma: ehPrimeiro ? _armazenamento.obterIdiomaLegado() : null,
      autoQualidade:
          ehPrimeiro ? _armazenamento.obterAutoQualidadeLegado() : false,
      ordemCategorias: ehPrimeiro
          ? _armazenamento.obterOrdemCategoriasLegado()
          : 'popularidade',
      ordemCanais:
          ehPrimeiro ? _armazenamento.obterOrdemCanaisLegado() : 'padrao',
    );
    await _armazenamento.salvarPerfil(p);
    if (ehPrimeiro) {
      await _armazenamento.migrarLegadoParaPerfil(p.id);
    }
    _perfis = _armazenamento.carregarPerfis();
    notifyListeners();
    return p;
  }

  /// Edita nome/icone de um perfil existente.
  Future<void> editar(Perfil p, {String? nome, String? icone}) async {
    final atualizado = p.copyWith(
      nome: (nome != null && nome.trim().isNotEmpty) ? nome.trim() : null,
      icone: icone,
    );
    await _persistir(atualizado);
  }

  /// Atualiza a configuracao do perfil ATIVO (chamado pelo PreferenciasProvider).
  Future<void> atualizarConfigAtivo({
    String? idioma,
    bool? autoQualidade,
    String? ordemCategorias,
    String? ordemCanais,
    List<String>? categoriasBloqueadas,
    // Sentinela: null aqui apagaria o PIN sem querer. Ver Perfil.copyWith.
    Object? pin = Perfil.naoMexer,
  }) async {
    final ativo = _ativo;
    if (ativo == null) return;
    final atualizado = ativo.copyWith(
      idioma: idioma,
      autoQualidade: autoQualidade,
      ordemCategorias: ordemCategorias,
      ordemCanais: ordemCanais,
      categoriasBloqueadas: categoriasBloqueadas,
      pin: pin,
    );
    _ativo = atualizado;
    await _persistir(atualizado);
  }

  Future<void> _persistir(Perfil p) async {
    await _armazenamento.salvarPerfil(p);
    _perfis = _armazenamento.carregarPerfis();
    if (_ativo?.id == p.id) _ativo = p;
    notifyListeners();
  }

  /// Remove um perfil e toda a sua biblioteca pessoal.
  Future<void> remover(Perfil p) async {
    await _armazenamento.removerPerfil(p.id);
    if (_ativo?.id == p.id) {
      _ativo = null;
      _confirmado = false;
    }
    _perfis = _armazenamento.carregarPerfis();
    notifyListeners();
  }

  /// Volta para a tela "Quem esta assistindo" sem apagar nada.
  void trocarPerfil() {
    _confirmado = false;
    notifyListeners();
  }

  /// Apaga perfis e bibliotecas locais.
  Future<void> limparLocais() async {
    await _armazenamento.limparPerfis();
    _perfis = [];
    _ativo = null;
    _confirmado = false;
    notifyListeners();
  }
}
