import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../services/servico_conta.dart';

/// Provider de conta: expoe o estado de autenticacao para a UI e delega as
/// acoes (entrar, criar conta, sair) ao [ServicoConta].
///
/// Escuta as mudancas de auth do Supabase e chama [notifyListeners] — assim o
/// `app.dart` troca entre tela de login e app sozinho quando o usuario entra
/// ou sai.
///
/// Aceita um servico nulo: se o app rodar sem credenciais do Supabase no .env,
/// [disponivel] fica `false` e o login simplesmente nao e exigido (modo local).
class ContaProvider extends ChangeNotifier {
  final ServicoConta? _conta;
  StreamSubscription<AuthState>? _sub;

  // ── MFA ──────────────────────────────────────────────────────────────────
  // Apos o login (signInWithPassword cria sessao AAL1), a conta pode exigir o
  // 2o fator (TOTP) para chegar a AAL2. Enquanto pendente, o gate (app.dart)
  // segura na tela de login mostrando a etapa de codigo.
  bool _aguardandoMfa = false;
  bool _resolvendoLogin = false;
  String? _factorId;
  String? _challengeId;
  Future<bool>? _prepInFlight;

  /// `true` quando falta o usuario digitar o codigo TOTP.
  bool get aguardandoMfa => _aguardandoMfa;

  /// `true` durante a checagem (logo apos logar) se o MFA e necessario — o gate
  /// segura na tela de login para nao "piscar" a home com sessao AAL1.
  bool get resolvendoLogin => _resolvendoLogin;

  ContaProvider(this._conta) {
    _sub = _conta?.mudancasAuth.listen(_aoMudarAuth);
  }

  /// Reage a cada mudanca de auth. Cobre tambem a RESTAURACAO de sessao no
  /// cold start (se a sessao salva estava em AAL1, exige o MFA na abertura).
  Future<void> _aoMudarAuth(AuthState _) async {
    final conta = _conta;
    if (conta == null || !conta.estaLogado) {
      _aguardandoMfa = false;
      _resolvendoLogin = false;
      _factorId = _challengeId = null;
      _prepInFlight = null;
      notifyListeners();
      return;
    }
    _resolvendoLogin = true;
    notifyListeners();
    await prepararMfa();
    _resolvendoLogin = false;
    notifyListeners();
  }

  /// Prepara o desafio MFA se a conta exigir. Dedup de chamadas concorrentes
  /// (login pela tela + listener disparam juntos) — uma so challenge. Retorna
  /// `true` se o codigo ainda precisa ser digitado.
  Future<bool> prepararMfa() {
    return _prepInFlight ??= () async {
      final f = _prepararMfaImpl();
      try {
        return await f;
      } finally {
        _prepInFlight = null;
      }
    }();
  }

  Future<bool> _prepararMfaImpl() async {
    final conta = _conta;
    if (conta == null) return false;
    if (!await conta.precisaMfa()) {
      _aguardandoMfa = false;
      _factorId = _challengeId = null;
      notifyListeners();
      return false;
    }
    final d = await conta.iniciarDesafioMfa();
    if (d == null) {
      // Exige AAL2 mas nao ha fator verificado (caso raro) — segue sem MFA.
      _aguardandoMfa = false;
      notifyListeners();
      return false;
    }
    _factorId = d.factorId;
    _challengeId = d.challengeId;
    _aguardandoMfa = true;
    notifyListeners();
    return true;
  }

  /// Verifica o codigo TOTP; eleva a sessao a AAL2 e libera o gate. Lanca se
  /// o codigo for invalido.
  Future<void> verificarMfaCodigo(String code) async {
    final conta = _conta;
    final fid = _factorId, cid = _challengeId;
    if (conta == null || fid == null || cid == null) {
      throw StateError('Desafio MFA nao iniciado.');
    }
    await conta.verificarMfa(factorId: fid, challengeId: cid, code: code);
    _aguardandoMfa = false;
    _factorId = _challengeId = null;
    notifyListeners();
  }

  /// Cancela o MFA (volta a tela de login): desloga a sessao AAL1.
  Future<void> cancelarMfa() async {
    await _conta?.sair();
    // O listener (_aoMudarAuth) zera os flags ao detectar o logout.
  }

  /// Se ha um backend de contas configurado (credenciais Supabase presentes).
  bool get disponivel => _conta != null;

  bool get estaLogado => _conta?.estaLogado ?? false;
  String? get email => _conta?.email;

  /// Faz login e ja prepara o MFA. Retorna `true` se o 2o fator e necessario
  /// (a UI deve mostrar a etapa de codigo em vez de prosseguir).
  Future<bool> entrar({required String email, required String senha}) async {
    final conta = _conta;
    if (conta == null) throw StateError('Contas indisponiveis.');
    await conta.entrar(email: email, senha: senha);
    return prepararMfa();
  }

  /// Retorna `true` se logou na hora; `false` se precisa confirmar o email.
  Future<bool> criarConta({
    required String email,
    required String senha,
  }) async {
    final conta = _conta;
    if (conta == null) throw StateError('Contas indisponiveis.');
    return conta.criarConta(email: email, senha: senha);
  }

  Future<void> sair() async => _conta?.sair();

  @override
  void dispose() {
    _sub?.cancel();
    super.dispose();
  }
}
