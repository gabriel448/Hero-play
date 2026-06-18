import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/physics.dart';
import 'package:provider/provider.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:url_launcher/url_launcher.dart';

import '../state/conta_provider.dart';
import '../state/iptv_provider.dart';
import '../state/perfil_provider.dart';
import '../state/preferencias_provider.dart';
import '../theme/app_theme.dart';
import '../widgets/animado_entrada.dart';

/// Tela de login/cadastro. Aparece no onboarding (apos a escolha de idioma) e
/// tambem pode ser aberta pelas Configuracoes.
///
/// Ao entrar com sucesso, dispara a sincronizacao das listas da conta. A troca
/// de tela em si e feita pelo `app.dart`, que observa o [ContaProvider].
class TelaLogin extends StatefulWidget {
  const TelaLogin({super.key});

  @override
  State<TelaLogin> createState() => _TelaLoginState();
}

class _TelaLoginState extends State<TelaLogin> {
  final _formKey = GlobalKey<FormState>();
  final _emailCtrl = TextEditingController();
  final _senhaCtrl = TextEditingController();
  final _mfaCtrl = TextEditingController();

  bool _modoCriar = false;
  bool _carregando = false;
  String? _erro;
  String? _info;

  // Etapa MFA (2o fator)
  bool _mfaCarregando = false;
  String? _mfaErro;

  @override
  void dispose() {
    _emailCtrl.dispose();
    _senhaCtrl.dispose();
    _mfaCtrl.dispose();
    super.dispose();
  }

  void _trocarModo(bool criar) {
    setState(() {
      _modoCriar = criar;
      _erro = null;
      _info = null;
    });
  }

  Future<void> _enviar() async {
    setState(() {
      _erro = null;
      _info = null;
    });
    if (!_formKey.currentState!.validate()) return;

    final conta = context.read<ContaProvider>();
    final email = _emailCtrl.text.trim();
    final senha = _senhaCtrl.text;

    setState(() => _carregando = true);
    try {
      // Criar conta acontece no site — aqui so login.
      final pendenteMfa = await conta.entrar(email: email, senha: senha);

      if (pendenteMfa) {
        // Mostra a etapa de codigo (o build reage a conta.aguardandoMfa). O
        // gate (app.dart) segura nesta tela ate o 2o fator ser verificado.
        if (mounted) setState(() => _carregando = false);
        return;
      }

      _concluirLogin();
    } on AuthException catch (e) {
      if (mounted) setState(() => _erro = _traduzir(e.message));
    } catch (e) {
      if (mounted) setState(() => _erro = _traduzir(e.toString()));
    } finally {
      if (mounted) setState(() => _carregando = false);
    }
  }

  /// Login completo (sem ou apos o MFA): dispara o sync e sai da tela. O sync
  /// nao trava a navegacao — o `app.dart` troca para "Importando listas".
  void _concluirLogin() {
    if (!mounted) return;
    unawaited(context.read<IptvProvider>().sincronizarDoSupabase());
    unawaited(context.read<PerfilProvider>().sincronizarDoSupabase());
    if (Navigator.of(context).canPop()) Navigator.of(context).pop();
  }

  Future<void> _verificarMfa() async {
    final code = _mfaCtrl.text.replaceAll(RegExp(r'\D'), '');
    if (code.length != 6) {
      setState(() => _mfaErro = 'Digite os 6 dígitos.');
      return;
    }
    setState(() {
      _mfaCarregando = true;
      _mfaErro = null;
    });
    try {
      await context.read<ContaProvider>().verificarMfaCodigo(code);
      if (!mounted) return;
      _concluirLogin();
    } catch (_) {
      if (mounted) {
        setState(() {
          _mfaErro = 'Código inválido ou expirado.';
          _mfaCtrl.clear();
        });
      }
    } finally {
      if (mounted) setState(() => _mfaCarregando = false);
    }
  }

  Future<void> _cancelarMfa() async {
    _mfaCtrl.clear();
    setState(() => _mfaErro = null);
    await context.read<ContaProvider>().cancelarMfa();
  }

  Future<void> _continuarSemConta() async {
    await context.read<PreferenciasProvider>().pularLogin();
  }

  /// Criar conta acontece no site (evita ter que reimplementar verificacao de
  /// email/MFA no app). Abre o site ja na aba de cadastro.
  static const _urlCriarConta =
      'https://heroplaytv.com/login.html?modo=criar';

  Future<void> _abrirCriarContaSite() async {
    bool ok = false;
    try {
      ok = await launchUrl(
        Uri.parse(_urlCriarConta),
        mode: LaunchMode.externalApplication,
      );
    } catch (_) {
      ok = false;
    }
    if (!ok && mounted) {
      setState(() => _erro =
          'Não foi possível abrir o navegador. Acesse o site para criar sua conta.');
    }
  }

  String _traduzir(String m) {
    final t = m.toLowerCase();
    if (t.contains('invalid login')) return 'Email ou senha incorretos.';
    if (t.contains('already registered') || t.contains('already exists')) {
      return 'Esse email já tem conta. Tente entrar.';
    }
    if (t.contains('password should be at least')) {
      return 'A senha precisa ter pelo menos 6 caracteres.';
    }
    if (t.contains('invalid email') || t.contains('unable to validate email')) {
      return 'Email inválido.';
    }
    if (t.contains('email not confirmed')) {
      return 'Confirme seu email antes de entrar.';
    }
    if (t.contains('email signups are disabled')) {
      return 'Cadastro por email desativado no servidor.';
    }
    return 'Não foi possível concluir. Verifique a conexão e tente de novo.';
  }

  @override
  Widget build(BuildContext context) {
    final textTheme = Theme.of(context).textTheme;
    // Quando logado mas em AAL1 com MFA exigido, mostra a etapa de codigo.
    final aguardandoMfa =
        context.select<ContaProvider, bool>((c) => c.aguardandoMfa);

    // Card cinza (como no site) sobre o fundo preto, para o formulario e os
    // campos nao se perderem no preto. Inputs ganham fill/borda contrastantes.
    final temaCard = Theme.of(context).copyWith(
      inputDecorationTheme:
          Theme.of(context).inputDecorationTheme.copyWith(
        fillColor: AppColors.surface2,
        border: OutlineInputBorder(
          borderRadius: BorderRadius.circular(AppRadius.base),
          borderSide: const BorderSide(color: AppColors.outlineSubtle),
        ),
        enabledBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(AppRadius.base),
          borderSide: const BorderSide(color: AppColors.outlineSubtle),
        ),
      ),
    );

    return Scaffold(
      body: SafeArea(
        child: Center(
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 440),
            child: SingleChildScrollView(
              padding: const EdgeInsets.all(AppSpacing.lg),
              child: Container(
                padding: const EdgeInsets.all(AppSpacing.xl),
                decoration: BoxDecoration(
                  // Cinza levemente mais claro que o preto do fundo (como o site).
                  color: const Color(0xFF1A1815),
                  borderRadius: BorderRadius.circular(20),
                  border: Border.all(color: AppColors.divider),
                ),
                child: Theme(
                  data: temaCard,
                  child: aguardandoMfa
                      ? _MfaStep(
                          carregando: _mfaCarregando,
                          erro: _mfaErro,
                          controller: _mfaCtrl,
                          onVerificar: _verificarMfa,
                          onCancelar: _carregando ? null : _cancelarMfa,
                        )
                      : Form(
                key: _formKey,
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    // ── Logo ──────────────────────────────────────────────
                    AnimadoEntrada(
                      child: Center(
                        child: Container(
                          width: 88,
                          height: 88,
                          decoration: BoxDecoration(
                            color: AppColors.surface1,
                            borderRadius: BorderRadius.circular(AppRadius.lg),
                          ),
                          child: const Icon(
                            Icons.live_tv_rounded,
                            size: 44,
                            color: AppColors.accent,
                          ),
                        ),
                      ),
                    ),
                    const SizedBox(height: AppSpacing.xl),

                    // ── Titulo + subtitulo ─────────────────────────────────
                    AnimadoEntrada(
                      delay: const Duration(milliseconds: 80),
                      child: AnimatedSwitcher(
                        duration: const Duration(milliseconds: 300),
                        transitionBuilder: (child, animation) => FadeTransition(
                          opacity: CurvedAnimation(
                            parent: animation,
                            curve: Curves.easeOut,
                          ),
                          child: SlideTransition(
                            position: Tween<Offset>(
                              begin: const Offset(0, 0.02),
                              end: Offset.zero,
                            ).animate(CurvedAnimation(
                              parent: animation,
                              curve: Curves.easeOut,
                            )),
                            child: child,
                          ),
                        ),
                        child: Column(
                          key: ValueKey(_modoCriar),
                          children: [
                            Text(
                              _modoCriar ? 'Criar conta' : 'Entrar',
                              style: textTheme.headlineMedium,
                              textAlign: TextAlign.center,
                            ),
                            const SizedBox(height: AppSpacing.xs),
                            Text(
                              _modoCriar
                                  ? 'Crie sua conta para salvar e sincronizar suas listas.'
                                  : 'Acesse sua conta para carregar suas listas.',
                              style: textTheme.bodySmall?.copyWith(
                                color: AppColors.textSecondary,
                              ),
                              textAlign: TextAlign.center,
                            ),
                          ],
                        ),
                      ),
                    ),
                    const SizedBox(height: AppSpacing.xl),

                    // ── Abas Entrar / Criar conta ──────────────────────────
                    AnimadoEntrada(
                      delay: const Duration(milliseconds: 160),
                      child: _SeletorModo(
                        modoCriar: _modoCriar,
                        onSelecionar: _carregando ? null : _trocarModo,
                      ),
                    ),
                    const SizedBox(height: AppSpacing.lg),

                    if (_info != null) ...[
                      _Aviso(texto: _info!, erro: false),
                      const SizedBox(height: AppSpacing.md),
                    ],
                    if (_erro != null) ...[
                      _Aviso(texto: _erro!, erro: true),
                      const SizedBox(height: AppSpacing.md),
                    ],

                    // ── Conteudo: form de login OU CTA p/ criar no site ────
                    if (_modoCriar)
                      AnimadoEntrada(
                        delay: const Duration(milliseconds: 240),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.stretch,
                          children: [
                            Container(
                              padding: const EdgeInsets.all(AppSpacing.base),
                              decoration: BoxDecoration(
                                color: AppColors.surface2,
                                borderRadius:
                                    BorderRadius.circular(AppRadius.base),
                                border: Border.all(
                                    color: AppColors.outlineSubtle),
                              ),
                              child: Text(
                                'A criação de conta é feita no nosso site, em '
                                'poucos segundos. Depois é só voltar e entrar '
                                'aqui com seu email e senha.',
                                style: textTheme.bodySmall?.copyWith(
                                  color: AppColors.textSecondary,
                                  height: 1.5,
                                ),
                                textAlign: TextAlign.center,
                              ),
                            ),
                            const SizedBox(height: AppSpacing.lg),
                            FilledButton.icon(
                              onPressed:
                                  _carregando ? null : _abrirCriarContaSite,
                              icon: const Icon(Icons.open_in_new_rounded,
                                  size: 18),
                              label: const Text('Criar conta no site'),
                            ),
                            const SizedBox(height: AppSpacing.md),
                            TextButton(
                              onPressed:
                                  _carregando ? null : _continuarSemConta,
                              child: const Text('Continuar sem conta'),
                            ),
                          ],
                        ),
                      )
                    else ...[
                      // ── Campos (Entrar) ────────────────────────────────
                      AnimadoEntrada(
                        delay: const Duration(milliseconds: 240),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.stretch,
                          children: [
                            _Label('Email'),
                            const SizedBox(height: AppSpacing.sm),
                            TextFormField(
                              controller: _emailCtrl,
                              enabled: !_carregando,
                              keyboardType: TextInputType.emailAddress,
                              autofillHints: const [AutofillHints.email],
                              decoration: const InputDecoration(
                                hintText: 'voce@email.com',
                              ),
                              validator: (v) {
                                final t = v?.trim() ?? '';
                                if (t.isEmpty) return 'Informe o email';
                                if (!t.contains('@') || !t.contains('.')) {
                                  return 'Email inválido';
                                }
                                return null;
                              },
                            ),
                            const SizedBox(height: AppSpacing.lg),
                            _Label('Senha'),
                            const SizedBox(height: AppSpacing.sm),
                            TextFormField(
                              controller: _senhaCtrl,
                              enabled: !_carregando,
                              obscureText: true,
                              decoration: const InputDecoration(
                                hintText: 'sua senha',
                              ),
                              validator: (v) {
                                if (v == null || v.isEmpty) {
                                  return 'Informe a senha';
                                }
                                return null;
                              },
                            ),
                          ],
                        ),
                      ),
                      const SizedBox(height: AppSpacing.xl),

                      // ── Botoes (Entrar) ────────────────────────────────
                      AnimadoEntrada(
                        delay: const Duration(milliseconds: 320),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.stretch,
                          children: [
                            FilledButton(
                              onPressed: _carregando ? null : _enviar,
                              child: _carregando
                                  ? const SizedBox(
                                      width: 18,
                                      height: 18,
                                      child: CircularProgressIndicator(
                                        strokeWidth: 2,
                                        color: AppColors.accentOn,
                                      ),
                                    )
                                  : const Text('Entrar'),
                            ),
                            const SizedBox(height: AppSpacing.md),
                            TextButton(
                              onPressed:
                                  _carregando ? null : _continuarSemConta,
                              child: const Text('Continuar sem conta'),
                            ),
                          ],
                        ),
                      ),
                    ],
                  ],
                ),
              ),
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}

// ── Etapa do 2o fator (TOTP) ─────────────────────────────────────────────────
class _MfaStep extends StatelessWidget {
  final bool carregando;
  final String? erro;
  final TextEditingController controller;
  final VoidCallback onVerificar;
  final VoidCallback? onCancelar;

  const _MfaStep({
    required this.carregando,
    required this.erro,
    required this.controller,
    required this.onVerificar,
    required this.onCancelar,
  });

  @override
  Widget build(BuildContext context) {
    final textTheme = Theme.of(context).textTheme;
    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Center(
          child: Container(
            width: 72,
            height: 72,
            decoration: BoxDecoration(
              color: AppColors.surface2,
              borderRadius: BorderRadius.circular(AppRadius.lg),
            ),
            child: const Icon(
              Icons.verified_user_rounded,
              size: 36,
              color: AppColors.accent,
            ),
          ),
        ),
        const SizedBox(height: AppSpacing.lg),
        Text(
          'Verificação em duas etapas',
          style: textTheme.titleLarge,
          textAlign: TextAlign.center,
        ),
        const SizedBox(height: AppSpacing.xs),
        Text(
          'Digite o código de 6 dígitos do seu app autenticador.',
          style: textTheme.bodySmall?.copyWith(color: AppColors.textSecondary),
          textAlign: TextAlign.center,
        ),
        const SizedBox(height: AppSpacing.xl),
        if (erro != null) ...[
          _Aviso(texto: erro!, erro: true),
          const SizedBox(height: AppSpacing.md),
        ],
        TextField(
          controller: controller,
          enabled: !carregando,
          autofocus: true,
          keyboardType: TextInputType.number,
          textAlign: TextAlign.center,
          maxLength: 6,
          style: textTheme.headlineSmall?.copyWith(
            letterSpacing: 8,
            fontWeight: FontWeight.w700,
          ),
          decoration: const InputDecoration(
            hintText: '000000',
            counterText: '',
          ),
          onChanged: (v) {
            if (!carregando &&
                v.replaceAll(RegExp(r'\D'), '').length == 6) {
              onVerificar();
            }
          },
        ),
        const SizedBox(height: AppSpacing.lg),
        FilledButton(
          onPressed: carregando ? null : onVerificar,
          child: carregando
              ? const SizedBox(
                  width: 18,
                  height: 18,
                  child: CircularProgressIndicator(
                    strokeWidth: 2,
                    color: AppColors.accentOn,
                  ),
                )
              : const Text('Verificar'),
        ),
        const SizedBox(height: AppSpacing.md),
        TextButton(
          onPressed: onCancelar,
          child: const Text('Usar outra conta'),
        ),
      ],
    );
  }
}

// Seletor de modo com indicador deslizante animado por spring physics,
// identico ao comportamento do site (anime.js spring(1, 90, 12, 0)).
class _SeletorModo extends StatefulWidget {
  final bool modoCriar;
  final void Function(bool criar)? onSelecionar;

  const _SeletorModo({required this.modoCriar, required this.onSelecionar});

  @override
  State<_SeletorModo> createState() => _SeletorModoState();
}

class _SeletorModoState extends State<_SeletorModo>
    with SingleTickerProviderStateMixin {
  late final AnimationController _ctrl;

  // spring(mass:1, stiffness:90, damping:12) — mesmo do site
  static final _spring = SpringDescription(mass: 1, stiffness: 90, damping: 12);
  static const _pad = 4.0;

  @override
  void initState() {
    super.initState();
    // Bounds generosos para o spring poder ultrapassar (overshoot) sem ser clamped.
    _ctrl = AnimationController(vsync: this, lowerBound: -0.2, upperBound: 1.2)
      ..value = widget.modoCriar ? 1.0 : 0.0;
  }

  @override
  void didUpdateWidget(_SeletorModo old) {
    super.didUpdateWidget(old);
    if (old.modoCriar != widget.modoCriar) {
      _ctrl.animateWith(
        SpringSimulation(_spring, _ctrl.value, widget.modoCriar ? 1.0 : 0.0, 0),
      );
    }
  }

  @override
  void dispose() {
    _ctrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(_pad),
      decoration: BoxDecoration(
        color: AppColors.surface2,
        borderRadius: BorderRadius.circular(AppRadius.base),
      ),
      child: LayoutBuilder(
        builder: (context, constraints) {
          final tabW = constraints.maxWidth / 2;
          return Stack(
            clipBehavior: Clip.hardEdge,
            children: [
              // ── Indicador deslizante ─────────────────────────────────
              // Fica num Positioned fixo em left:0 e desliza via Transform,
              // que roda na GPU sem reconstruir o layout nem os GestureDetectors.
              Positioned(
                top: 0,
                bottom: 0,
                left: 0,
                width: tabW,
                child: AnimatedBuilder(
                  animation: _ctrl,
                  builder: (context, child) => Transform.translate(
                    offset: Offset(_ctrl.value * tabW, 0),
                    child: child,
                  ),
                  child: Container(
                    decoration: BoxDecoration(
                      color: AppColors.surface3,
                      borderRadius: BorderRadius.circular(AppRadius.sm),
                    ),
                  ),
                ),
              ),
              // ── Abas (fora do AnimatedBuilder — nunca reconstruidas pelo spring) ──
              Row(
                children: [
                  _Aba(
                    texto: 'Entrar',
                    ativa: !widget.modoCriar,
                    habilitada: widget.onSelecionar != null,
                    onTap: () => widget.onSelecionar?.call(false),
                  ),
                  _Aba(
                    texto: 'Criar conta',
                    ativa: widget.modoCriar,
                    habilitada: widget.onSelecionar != null,
                    onTap: () => widget.onSelecionar?.call(true),
                  ),
                ],
              ),
            ],
          );
        },
      ),
    );
  }
}

class _Aba extends StatelessWidget {
  final String texto;
  final bool ativa;
  final bool habilitada;
  final VoidCallback onTap;

  const _Aba({
    required this.texto,
    required this.ativa,
    required this.habilitada,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return Expanded(
      child: GestureDetector(
        // opaque: registra toque em qualquer ponto da aba, nao so no texto
        behavior: HitTestBehavior.opaque,
        onTap: habilitada ? onTap : null,
        child: Padding(
          padding: const EdgeInsets.symmetric(vertical: AppSpacing.sm),
          child: AnimatedDefaultTextStyle(
            duration: const Duration(milliseconds: 250),
            curve: Curves.easeOut,
            style: (Theme.of(context).textTheme.titleSmall ?? const TextStyle())
                .copyWith(
              color: ativa ? AppColors.textPrimary : AppColors.textSecondary,
            ),
            child: Text(texto, textAlign: TextAlign.center),
          ),
        ),
      ),
    );
  }
}

class _Aviso extends StatelessWidget {
  final String texto;
  final bool erro;
  const _Aviso({required this.texto, required this.erro});

  @override
  Widget build(BuildContext context) {
    final cor = erro ? AppColors.error : AppColors.success;
    return Container(
      padding: const EdgeInsets.all(AppSpacing.md),
      decoration: BoxDecoration(
        color: cor.withValues(alpha: 0.10),
        borderRadius: BorderRadius.circular(AppRadius.sm),
        border: Border.all(color: cor.withValues(alpha: 0.35)),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(
            erro ? Icons.error_outline_rounded : Icons.check_circle_outline,
            size: 18,
            color: cor,
          ),
          const SizedBox(width: AppSpacing.sm),
          Expanded(
            child: Text(
              texto,
              style: Theme.of(context).textTheme.bodySmall?.copyWith(
                    color: AppColors.textPrimary,
                  ),
            ),
          ),
        ],
      ),
    );
  }
}

class _Label extends StatelessWidget {
  final String texto;
  const _Label(this.texto);

  @override
  Widget build(BuildContext context) {
    return Text(
      texto.toUpperCase(),
      style: Theme.of(context).textTheme.labelSmall?.copyWith(
            color: AppColors.textTertiary,
          ),
    );
  }
}
