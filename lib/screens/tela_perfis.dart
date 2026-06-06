import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../models/perfil.dart';
import '../state/iptv_provider.dart';
import '../state/perfil_provider.dart';
import '../theme/app_theme.dart';
import '../widgets/animado_entrada.dart';
import '../widgets/avatar_perfil.dart';
import 'tela_gerenciar_listas.dart';

/// Tela "Quem esta assistindo?" — a primeira tela ao abrir o app (depois do
/// eventual login). Lista os perfis da conta/aparelho, permite criar (ate
/// [Perfil.maxPerfis]) e gerenciar (editar/remover).
///
/// Ao escolher um perfil, aponta as boxes do Hive para ele e recarrega a
/// biblioteca pessoal — o `app.dart` entao troca para a home.
class TelaPerfis extends StatefulWidget {
  const TelaPerfis({super.key});

  @override
  State<TelaPerfis> createState() => _TelaPerfisState();
}

class _TelaPerfisState extends State<TelaPerfis> {
  bool _gerenciando = false;
  bool _entrando = false;

  /// Entra no perfil. Toda a animacao (avatar da grade -> centro -> canto +
  /// botoes surgindo) acontece na HOME, em uma unica coreografia continua —
  /// aqui so registramos a origem do toque e confirmamos. Ver `tela_inicial`.
  Future<void> _selecionar(Perfil p, Rect origem) async {
    if (_entrando) return;
    _entrando = true;
    final perfis = context.read<PerfilProvider>();
    final iptv = context.read<IptvProvider>();
    await perfis.prepararPerfil(p);
    iptv.recarregarDadosDoPerfil();
    perfis.marcarEntrada(origem);
    perfis.confirmar(); // app.dart troca para a home, que anima a entrada.
  }

  Future<void> _criar() async {
    await showDialog<void>(
      context: context,
      builder: (_) => const _DialogoPerfil(),
    );
  }

  Future<void> _editar(Perfil p) async {
    await showDialog<void>(
      context: context,
      builder: (_) => _DialogoPerfil(perfil: p),
    );
  }

  @override
  Widget build(BuildContext context) {
    final perfis = context.watch<PerfilProvider>();
    final lista = perfis.perfis;
    final temPerfis = lista.isNotEmpty;
    final textTheme = Theme.of(context).textTheme;

    return Scaffold(
      body: SafeArea(
        child: Center(
          child: SingleChildScrollView(
            padding: const EdgeInsets.all(AppSpacing.xl),
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 720),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  AnimadoEntrada(
                    child: Text(
                      _gerenciando ? 'Gerenciar perfis' : 'Quem está assistindo?',
                      style: textTheme.displayMedium,
                      textAlign: TextAlign.center,
                    ),
                  ),
                  if (!temPerfis) ...[
                    const SizedBox(height: AppSpacing.sm),
                    AnimadoEntrada(
                      delay: const Duration(milliseconds: 80),
                      child: Text(
                        'Crie um perfil para começar. Cada perfil tem o seu '
                        'idioma, favoritos e histórico.',
                        style: textTheme.bodyMedium
                            ?.copyWith(color: AppColors.textSecondary),
                        textAlign: TextAlign.center,
                      ),
                    ),
                  ],
                  const SizedBox(height: AppSpacing.xxxl),
                  Wrap(
                    alignment: WrapAlignment.center,
                    spacing: AppSpacing.xl,
                    runSpacing: AppSpacing.xl,
                    children: [
                      for (final (i, p) in lista.indexed)
                        AnimadoEntrada(
                          delay: Duration(milliseconds: 120 + i * 80),
                          child: _CartaoPerfil(
                            perfil: p,
                            gerenciando: _gerenciando,
                            onTap: (origem) => _gerenciando
                                ? _editar(p)
                                : _selecionar(p, origem),
                          ),
                        ),
                      if (perfis.podeAdicionar)
                        AnimadoEntrada(
                          delay:
                              Duration(milliseconds: 120 + lista.length * 80),
                          child: _CartaoAdicionar(onTap: _criar),
                        ),
                    ],
                  ),
                  if (!perfis.podeAdicionar) ...[
                    const SizedBox(height: AppSpacing.base),
                    Text(
                      'Máximo de ${perfis.maximo} perfis por conta.',
                      style: textTheme.bodySmall,
                    ),
                  ],
                  const SizedBox(height: AppSpacing.xxxl),
                  AnimadoEntrada(
                    delay: const Duration(milliseconds: 240),
                    child: Wrap(
                      alignment: WrapAlignment.center,
                      spacing: AppSpacing.md,
                      runSpacing: AppSpacing.md,
                      children: [
                        if (temPerfis)
                          OutlinedButton.icon(
                            onPressed: () =>
                                setState(() => _gerenciando = !_gerenciando),
                            icon: Icon(
                              _gerenciando
                                  ? Icons.check_rounded
                                  : Icons.manage_accounts_rounded,
                              size: 18,
                            ),
                            label: Text(
                              _gerenciando ? 'Concluir' : 'Gerenciar perfis',
                            ),
                          ),
                        OutlinedButton.icon(
                          onPressed: () => Navigator.of(context).push(
                            MaterialPageRoute(
                              builder: (_) => const TelaGerenciarListas(),
                            ),
                          ),
                          icon: const Icon(Icons.playlist_play_rounded, size: 18),
                          label: const Text('Gerenciar listas'),
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
    );
  }
}

/// Cartao de um perfil: avatar + nome, com escala ao passar o mouse / tocar.
class _CartaoPerfil extends StatefulWidget {
  final Perfil perfil;
  final bool gerenciando;

  /// Recebe o rect (em coordenadas globais) do avatar tocado — ponto de
  /// partida da animacao de entrada no perfil.
  final void Function(Rect origem) onTap;

  const _CartaoPerfil({
    required this.perfil,
    required this.gerenciando,
    required this.onTap,
  });

  @override
  State<_CartaoPerfil> createState() => _CartaoPerfilState();
}

class _CartaoPerfilState extends State<_CartaoPerfil> {
  bool _hover = false;
  final GlobalKey _avatarKey = GlobalKey();

  void _disparar() {
    final box = _avatarKey.currentContext?.findRenderObject() as RenderBox?;
    final origem = box != null
        ? box.localToGlobal(Offset.zero) & box.size
        : Rect.zero;
    widget.onTap(origem);
  }

  @override
  Widget build(BuildContext context) {
    // Circulos estaticos: sem escala/pulsacao. O hover so realca o nome.
    return MouseRegion(
      cursor: SystemMouseCursors.click,
      onEnter: (_) => setState(() => _hover = true),
      onExit: (_) => setState(() => _hover = false),
      child: GestureDetector(
        onTap: _disparar,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Stack(
              alignment: Alignment.center,
              children: [
                AvatarPerfil(
                  key: _avatarKey,
                  chave: widget.perfil.icone,
                  tamanho: 112,
                ),
                if (widget.gerenciando)
                  Container(
                    width: 112,
                    height: 112,
                    decoration: BoxDecoration(
                      shape: BoxShape.circle,
                      color: AppColors.surface0.withValues(alpha: 0.45),
                    ),
                    child: const Icon(
                      Icons.edit_rounded,
                      color: AppColors.textPrimary,
                      size: 30,
                    ),
                  ),
              ],
            ),
            const SizedBox(height: AppSpacing.md),
            SizedBox(
              width: 120,
              child: Text(
                widget.perfil.nome,
                style: Theme.of(context).textTheme.titleSmall?.copyWith(
                      color: _hover
                          ? AppColors.textPrimary
                          : AppColors.textSecondary,
                    ),
                textAlign: TextAlign.center,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// Cartao "+" de criar perfil.
class _CartaoAdicionar extends StatefulWidget {
  final VoidCallback onTap;
  const _CartaoAdicionar({required this.onTap});

  @override
  State<_CartaoAdicionar> createState() => _CartaoAdicionarState();
}

class _CartaoAdicionarState extends State<_CartaoAdicionar> {
  bool _hover = false;

  @override
  Widget build(BuildContext context) {
    return MouseRegion(
      cursor: SystemMouseCursors.click,
      onEnter: (_) => setState(() => _hover = true),
      onExit: (_) => setState(() => _hover = false),
      child: GestureDetector(
        onTap: widget.onTap,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            AnimatedContainer(
              duration: AppMotion.base,
              curve: AppMotion.ease,
              width: 112,
              height: 112,
              decoration: BoxDecoration(
                color: _hover ? AppColors.surface2 : AppColors.surface1,
                borderRadius: BorderRadius.circular(AppRadius.lg),
                border: Border.all(
                  color: _hover ? AppColors.accent : AppColors.outlineSubtle,
                  width: 2,
                ),
              ),
              child: Icon(
                Icons.add_rounded,
                size: 44,
                color: _hover ? AppColors.accent : AppColors.textSecondary,
              ),
            ),
            const SizedBox(height: AppSpacing.md),
            SizedBox(
              width: 120,
              child: Text(
                'Adicionar perfil',
                style: Theme.of(context)
                    .textTheme
                    .titleSmall
                    ?.copyWith(color: AppColors.textSecondary),
                textAlign: TextAlign.center,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// Dialogo de criar/editar perfil: nome + escolha do avatar. Quando recebe um
/// [perfil], opera em modo edicao (e oferece remover).
class _DialogoPerfil extends StatefulWidget {
  final Perfil? perfil;
  const _DialogoPerfil({this.perfil});

  @override
  State<_DialogoPerfil> createState() => _DialogoPerfilState();
}

class _DialogoPerfilState extends State<_DialogoPerfil> {
  late final TextEditingController _nomeCtrl;
  late String _icone;
  bool _salvando = false;

  bool get _ehEdicao => widget.perfil != null;

  @override
  void initState() {
    super.initState();
    _nomeCtrl = TextEditingController(text: widget.perfil?.nome ?? '');
    _icone = widget.perfil?.icone ?? avatarPadrao;
  }

  @override
  void dispose() {
    _nomeCtrl.dispose();
    super.dispose();
  }

  Future<void> _salvar() async {
    final nome = _nomeCtrl.text.trim();
    if (nome.isEmpty) return;
    setState(() => _salvando = true);
    final perfis = context.read<PerfilProvider>();
    final navigator = Navigator.of(context);
    if (_ehEdicao) {
      await perfis.editar(widget.perfil!, nome: nome, icone: _icone);
    } else {
      await perfis.criar(nome: nome, icone: _icone);
    }
    navigator.pop();
  }

  Future<void> _remover() async {
    final perfis = context.read<PerfilProvider>();
    final navigator = Navigator.of(context);
    final ok = await showDialog<bool>(
      context: context,
      builder: (_) => AlertDialog(
        title: const Text('Remover perfil?'),
        content: Text(
          'O perfil "${widget.perfil!.nome}" e toda a sua biblioteca pessoal '
          '(favoritos, histórico) serão apagados. As listas não são afetadas.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('Cancelar'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(context, true),
            style: FilledButton.styleFrom(backgroundColor: AppColors.error),
            child: const Text('Remover'),
          ),
        ],
      ),
    );
    if (ok != true) return;
    await perfis.remover(widget.perfil!);
    navigator.pop();
  }

  @override
  Widget build(BuildContext context) {
    final textTheme = Theme.of(context).textTheme;
    return AlertDialog(
      title: Text(_ehEdicao ? 'Editar perfil' : 'Novo perfil'),
      content: SizedBox(
        width: 360,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            TextField(
              controller: _nomeCtrl,
              enabled: !_salvando,
              autofocus: true,
              textCapitalization: TextCapitalization.words,
              decoration: const InputDecoration(hintText: 'Nome do perfil'),
              onSubmitted: (_) => _salvar(),
            ),
            const SizedBox(height: AppSpacing.lg),
            Text(
              'ESCOLHA UM AVATAR',
              style: textTheme.labelSmall
                  ?.copyWith(color: AppColors.textTertiary, letterSpacing: 0.6),
            ),
            const SizedBox(height: AppSpacing.md),
            Wrap(
              spacing: AppSpacing.lg,
              runSpacing: AppSpacing.lg,
              children: [
                for (final chave in avataresDisponiveis)
                  GestureDetector(
                    onTap: () => setState(() => _icone = chave),
                    // O selecionado cresce um pouco e fica assim ate outro ser
                    // escolhido; o anterior volta ao tamanho original (anima de
                    // volta a 1.0). Origem central para crescer "no lugar".
                    child: AnimatedScale(
                      scale: chave == _icone ? 1.18 : 1.0,
                      duration: AppMotion.base,
                      curve: AppMotion.ease,
                      child: AvatarPerfil(
                        chave: chave,
                        tamanho: 60,
                        selecionado: chave == _icone,
                      ),
                    ),
                  ),
              ],
            ),
          ],
        ),
      ),
      actions: [
        if (_ehEdicao)
          TextButton(
            onPressed: _salvando ? null : _remover,
            style: TextButton.styleFrom(foregroundColor: AppColors.error),
            child: const Text('Remover'),
          ),
        TextButton(
          onPressed: _salvando ? null : () => Navigator.pop(context),
          child: const Text('Cancelar'),
        ),
        FilledButton(
          onPressed: _salvando ? null : _salvar,
          child: Text(_ehEdicao ? 'Salvar' : 'Criar'),
        ),
      ],
    );
  }
}
