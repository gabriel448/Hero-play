import 'package:flutter/foundation.dart';
import '../models/idioma_app.dart';
import '../services/armazenamento.dart';
import 'perfil_provider.dart';

/// Preferencias de uso. As que sao POR PERFIL (idioma, ajuste automatico de
/// qualidade, ordenacoes) ficam no [Perfil] ativo e sao lidas/gravadas atraves
/// do [PerfilProvider] — assim cada perfil tem a sua configuracao. As globais
/// ao aparelho (ex.: "pulou login") continuam no [Armazenamento].
///
/// Este provider escuta o [PerfilProvider] e re-emite [notifyListeners] quando o
/// perfil ativo (ou a sua config) muda, para que as telas que dependem das
/// preferencias se redesenhem sem precisar saber dos perfis.
class PreferenciasProvider extends ChangeNotifier {
  final Armazenamento _armazenamento;
  final PerfilProvider _perfis;

  PreferenciasProvider(this._armazenamento, this._perfis) {
    _perfis.addListener(notifyListeners);
  }

  @override
  void dispose() {
    _perfis.removeListener(notifyListeners);
    super.dispose();
  }

  // ── Idioma (por perfil) ───────────────────────────────────────────────────

  /// Idioma escolhido para o perfil ativo, ou `null` se ele usa o padrao.
  IdiomaApp? get idioma => IdiomaApp.porCodigo(_perfis.perfilAtivo?.idioma);

  /// Idioma a usar de fato nas consultas. Cai em portugues por padrao.
  IdiomaApp get idiomaEfetivo => idioma ?? IdiomaApp.portugues;

  Future<void> definirIdioma(IdiomaApp idioma) =>
      _perfis.atualizarConfigAtivo(idioma: idioma.codigo);

  // ── Volume do player (global ao app) ──────────────────────────────────────

  /// Volume salvo (0..150). Padrao 100 = sem atenuacao (só o volume do aparelho).
  double get volume => _armazenamento.obterVolume();

  /// Persiste o volume escolhido pelo usuario (sem notificar — o player ja
  /// reflete a mudanca em tempo real; isto e so para reabrir no mesmo nivel).
  Future<void> definirVolume(double valor) =>
      _armazenamento.salvarVolume(valor);

  // ── Ajuste automatico de qualidade (por perfil) ───────────────────────────

  bool get autoQualidade => _perfis.perfilAtivo?.autoQualidade ?? false;

  Future<void> definirAutoQualidade(bool valor) =>
      _perfis.atualizarConfigAtivo(autoQualidade: valor);

  // ── Controle dos pais (por perfil) ────────────────────────────────────────
  //
  // PIN de 4 digitos + categorias bloqueadas. Fica no perfil, entao um perfil
  // "Filhos" pode ter restricao e o do adulto nao. Local, nunca sai do
  // aparelho.

  bool get controleParentalAtivo =>
      _perfis.perfilAtivo?.temControleParental ?? false;

  String? get pinPais => _perfis.perfilAtivo?.pin;

  List<String> get categoriasBloqueadas =>
      _perfis.perfilAtivo?.categoriasBloqueadas ?? const [];

  bool categoriaBloqueada(String categoria) {
    if (!controleParentalAtivo) return false;
    final alvo = categoria.trim().toLowerCase();
    for (final c in categoriasBloqueadas) {
      if (c.trim().toLowerCase() == alvo) return true;
    }
    return false;
  }

  bool pinConfere(String tentativa) =>
      controleParentalAtivo && tentativa.trim() == pinPais;

  /// Define (ou troca) o PIN. Passar `null` DESLIGA o controle e limpa a lista
  /// de categorias bloqueadas.
  Future<void> definirPin(String? pin) async {
    final limpo = (pin == null || pin.trim().isEmpty) ? null : pin.trim();
    await _perfis.atualizarConfigAtivo(
      pin: limpo,
      categoriasBloqueadas: limpo == null ? const [] : null,
    );
    notifyListeners();
  }

  Future<void> definirCategoriasBloqueadas(List<String> categorias) async {
    await _perfis.atualizarConfigAtivo(categoriasBloqueadas: categorias);
    notifyListeners();
  }

  // ── Ordenacao da lista de categorias ao vivo (por perfil) ─────────────────

  OrdemCategorias get ordemCategorias => OrdemCategorias._fromKey(
        _perfis.perfilAtivo?.ordemCategorias ?? 'popularidade',
      );

  Future<void> definirOrdemCategorias(OrdemCategorias valor) =>
      _perfis.atualizarConfigAtivo(ordemCategorias: valor.key);

  // ── Ordenacao dos canais dentro de uma categoria (por perfil) ─────────────

  OrdemCanais get ordemCanais =>
      OrdemCanais._fromKey(_perfis.perfilAtivo?.ordemCanais ?? 'padrao');

  Future<void> definirOrdemCanais(OrdemCanais valor) =>
      _perfis.atualizarConfigAtivo(ordemCanais: valor.key);
}

/// Modos de ordenacao da LISTA de categorias.
enum OrdemCategorias {
  popularidade('popularidade', 'Popularidade'),
  az('az', 'A-Z');

  final String key;
  final String label;
  const OrdemCategorias(this.key, this.label);

  static OrdemCategorias _fromKey(String k) {
    for (final v in values) {
      if (v.key == k) return v;
    }
    return OrdemCategorias.popularidade;
  }
}

/// Modos de ordenacao dos CANAIS dentro de uma categoria.
enum OrdemCanais {
  padrao('padrao', 'Padrão'),
  az('az', 'A-Z');

  final String key;
  final String label;
  const OrdemCanais(this.key, this.label);

  static OrdemCanais _fromKey(String k) {
    for (final v in values) {
      if (v.key == k) return v;
    }
    return OrdemCanais.padrao;
  }
}
