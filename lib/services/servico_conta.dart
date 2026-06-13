import 'package:supabase_flutter/supabase_flutter.dart';

import '../models/lista_remota.dart';
import '../models/perfil.dart';

/// Camada de I/O para contas e sincronizacao de listas via Supabase.
///
/// Autenticacao (email/senha) — login, cadastro, logout, sessao atual.
///
/// CRUD de listas passa pela Edge Function `iptv` em vez de escrever direto
/// na tabela. A Edge Function:
///   - extrai e cifra com AES-256-CBC as credenciais Xtream presentes na URL
///     (username= / password= na querystring) antes de gravar no banco;
///   - reconstroi a URL completa na leitura, descriptografando as credenciais.
/// Assim o banco nunca guarda senhas Xtream em texto puro.
class ServicoConta {
  final SupabaseClient _cliente;

  ServicoConta(this._cliente);

  static const _funcao = 'iptv';

  // ===== AUTENTICACAO =====

  Session? get sessao => _cliente.auth.currentSession;
  User? get usuario => _cliente.auth.currentUser;
  bool get estaLogado => sessao != null;
  String? get email => usuario?.email;

  Stream<AuthState> get mudancasAuth => _cliente.auth.onAuthStateChange;

  Future<void> entrar({required String email, required String senha}) async {
    await _cliente.auth.signInWithPassword(email: email, password: senha);
  }

  Future<bool> criarConta({
    required String email,
    required String senha,
  }) async {
    final resposta = await _cliente.auth.signUp(email: email, password: senha);
    return resposta.session != null;
  }

  Future<void> sair() => _cliente.auth.signOut();

  // ===== LISTAS (via Edge Function) =====

  /// Todas as listas da conta logada. As URLs retornadas ja vem reconstruidas
  /// com as credenciais Xtream descriptografadas pela Edge Function.
  Future<List<ListaRemota>> listarListas() async {
    final resp = await _cliente.functions.invoke(
      _funcao,
      method: HttpMethod.get,
    );
    _checarResposta(resp);
    final lista = resp.data as List<dynamic>;
    return lista
        .map((m) => ListaRemota.fromMap(m as Map<String, dynamic>))
        .toList();
  }

  /// Insere ou atualiza uma lista (upsert por user_id + URL saneada).
  /// [fonteUrl] pode ser a URL completa com credenciais Xtream — a Edge
  /// Function extrai e cifra antes de gravar.
  Future<void> salvarLista({
    required String nome,
    required String fonteUrl,
    String? epgUrl,
  }) async {
    final resp = await _cliente.functions.invoke(
      _funcao,
      method: HttpMethod.post,
      body: {
        'nome': nome,
        'fonte_url': fonteUrl,
        'epg_url': ?epgUrl,
      },
    );
    _checarResposta(resp);
  }

  /// Troca a URL fonte de uma lista: remove a antiga e grava a nova.
  Future<void> trocarFonteLista({
    required String fonteAntiga,
    required String fonteNova,
    required String nome,
    String? epgUrl,
  }) async {
    await removerLista(fonteAntiga);
    await salvarLista(nome: nome, fonteUrl: fonteNova, epgUrl: epgUrl);
  }

  /// Remove a lista identificada pela URL fonte (pode ser a URL completa com
  /// credenciais — a Edge Function sanitiza antes de buscar no banco).
  Future<void> removerLista(String fonteUrl) async {
    final resp = await _cliente.functions.invoke(
      _funcao,
      method: HttpMethod.delete,
      body: {'fonte_url': fonteUrl},
    );
    _checarResposta(resp);
  }

  // ===== PERFIS =====
  //
  // Perfis nao tem credenciais a cifrar (diferente de `listas`), entao usamos
  // a tabela direto, protegida por RLS (cada usuario so ve os seus). A coluna
  // `user_id` recebe o id da sessao automaticamente via default/policy.

  static const _tabelaPerfis = 'perfis';

  /// Todos os perfis da conta logada, do mais antigo ao mais recente.
  Future<List<Perfil>> listarPerfis() async {
    final dados = await _cliente
        .from(_tabelaPerfis)
        .select()
        .order('criado_em', ascending: true);
    return (dados as List)
        .map((m) => Perfil.fromCloudMap(m as Map<String, dynamic>))
        .toList();
  }

  /// Insere ou atualiza um perfil (upsert por id).
  Future<void> salvarPerfil(Perfil p) async {
    final uid = usuario?.id;
    if (uid == null) return;
    await _cliente.from(_tabelaPerfis).upsert({
      ...p.toCloudMap(),
      'user_id': uid,
    });
  }

  Future<void> removerPerfil(String id) async {
    await _cliente.from(_tabelaPerfis).delete().eq('id', id);
  }

  // ===== BIBLIOTECA (favoritos / minha lista / progresso) =====
  //
  // Igual a `perfis`: sem segredos a cifrar, acesso direto a tabela protegida
  // por RLS. Upsert/delete pela PK composta (user_id+perfil_id+tipo+chave).

  static const _tabelaBiblioteca = 'biblioteca';

  /// Todos os itens da biblioteca de um perfil (qualquer tipo).
  Future<List<Map<String, dynamic>>> carregarBiblioteca(String perfilId) async {
    final dados = await _cliente
        .from(_tabelaBiblioteca)
        .select()
        .eq('perfil_id', perfilId);
    return (dados as List).cast<Map<String, dynamic>>();
  }

  /// Insere/atualiza um item da biblioteca.
  Future<void> salvarItemBiblioteca({
    required String perfilId,
    required String tipo,
    required String chave,
    Map<String, dynamic> dados = const {},
  }) async {
    final uid = usuario?.id;
    if (uid == null) return;
    await _cliente.from(_tabelaBiblioteca).upsert({
      'user_id': uid,
      'perfil_id': perfilId,
      'tipo': tipo,
      'chave': chave,
      'dados': dados,
      'atualizado_em': DateTime.now().toUtc().toIso8601String(),
    });
  }

  /// Remove um item da biblioteca.
  Future<void> removerItemBiblioteca({
    required String perfilId,
    required String tipo,
    required String chave,
  }) async {
    final uid = usuario?.id;
    if (uid == null) return;
    await _cliente
        .from(_tabelaBiblioteca)
        .delete()
        .eq('user_id', uid)
        .eq('perfil_id', perfilId)
        .eq('tipo', tipo)
        .eq('chave', chave);
  }

  // ── helpers ───────────────────────────────────────────────────────────────

  void _checarResposta(FunctionResponse resp) {
    if (resp.status >= 400) {
      final msg =
          (resp.data as Map<String, dynamic>?)?['error'] as String? ??
          'Erro ${resp.status}';
      throw Exception(msg);
    }
  }
}
