import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/physics.dart';
import 'package:provider/provider.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

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
  final _confirmarCtrl = TextEditingController();

  bool _modoCriar = false;
  bool _carregando = false;
  String? _erro;
  String? _info;

  @override
  void dispose() {
    _emailCtrl.dispose();
    _senhaCtrl.dispose();
    _confirmarCtrl.dispose();
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
    final iptv = context.read<IptvProvider>();
    final perfis = context.read<PerfilProvider>();
    final email = _emailCtrl.text.trim();
    final senha = _senhaCtrl.text;

    setState(() => _carregando = true);
    try {
      if (_modoCriar) {
        final logou = await conta.criarConta(email: email, senha: senha);
        if (!logou) {
          // Projeto exige confirmacao de email antes do primeiro login.
          if (!mounted) return;
          setState(() {
            _modoCriar = false;
            _info = 'Conta criada! Confirme seu email e depois entre.';
          });
          return;
        }
      } else {
        await conta.entrar(email: email, senha: senha);
      }

      // Logado: dispara o sync das listas da conta. Nao esperamos concluir
      // aqui — `sincronizarDoSupabase` ja marca `sincronizando` de imediato,
      // e o app.dart troca para a tela "Importando listas". Assim a navegacao
      // nao trava enquanto as listas baixam.
      unawaited(iptv.sincronizarDoSupabase());
      // Tambem traz os perfis da conta (best-effort, em paralelo).
      unawaited(perfis.sincronizarDoSupabase());
      if (!mounted) return;
      if (Navigator.of(context).canPop()) Navigator.of(context).pop();
    } on AuthException catch (e) {
      if (mounted) setState(() => _erro = _traduzir(e.message));
    } catch (e) {
      if (mounted) setState(() => _erro = _traduzir(e.toString()));
    } finally {
      if (mounted) setState(() => _carregando = false);
    }
  }

  Future<void> _continuarSemConta() async {
    await context.read<PreferenciasProvider>().pularLogin();
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
                  child: Form(
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

                    // ── Campos ─────────────────────────────────────────────
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
                              hintText: 'mínimo 6 caracteres',
                            ),
                            validator: (v) {
                              if (v == null || v.length < 6) {
                                return 'A senha precisa ter ao menos 6 caracteres';
                              }
                              return null;
                            },
                          ),
                          if (_modoCriar) ...[
                            const SizedBox(height: AppSpacing.lg),
                            _Label('Confirmar senha'),
                            const SizedBox(height: AppSpacing.sm),
                            TextFormField(
                              controller: _confirmarCtrl,
                              enabled: !_carregando,
                              obscureText: true,
                              decoration: const InputDecoration(
                                hintText: 'repita a senha',
                              ),
                              validator: (v) {
                                if (!_modoCriar) return null;
                                if (v != _senhaCtrl.text) {
                                  return 'As senhas não coincidem';
                                }
                                return null;
                              },
                            ),
                          ],
                        ],
                      ),
                    ),
                    const SizedBox(height: AppSpacing.xl),

                    // ── Botoes ─────────────────────────────────────────────
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
                                : Text(_modoCriar ? 'Criar conta' : 'Entrar'),
                          ),
                          const SizedBox(height: AppSpacing.md),
                          TextButton(
                            onPressed: _carregando ? null : _continuarSemConta,
                            child: const Text('Continuar sem conta'),
                          ),
                        ],
                      ),
                    ),
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
