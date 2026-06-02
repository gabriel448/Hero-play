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

  ContaProvider(this._conta) {
    _sub = _conta?.mudancasAuth.listen((_) => notifyListeners());
  }

  /// Se ha um backend de contas configurado (credenciais Supabase presentes).
  bool get disponivel => _conta != null;

  bool get estaLogado => _conta?.estaLogado ?? false;
  String? get email => _conta?.email;

  Future<void> entrar({required String email, required String senha}) async {
    final conta = _conta;
    if (conta == null) throw StateError('Contas indisponiveis.');
    await conta.entrar(email: email, senha: senha);
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
