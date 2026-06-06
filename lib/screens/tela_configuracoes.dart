import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../models/idioma_app.dart';
import '../state/conta_provider.dart';
import '../state/perfil_provider.dart';
import '../state/preferencias_provider.dart';
import '../theme/app_theme.dart';
import '../utils/layout.dart';
import '../widgets/avatar_perfil.dart';
import 'tela_historico.dart';
import 'tela_login.dart';

/// Tela de configuracoes. Hoje apenas o idioma — ponto de extensao natural
/// para futuras opcoes.
class TelaConfiguracoes extends StatelessWidget {
  const TelaConfiguracoes({super.key});

  @override
  Widget build(BuildContext context) {
    final preferencias = context.watch<PreferenciasProvider>();
    final idiomaAtual = preferencias.idiomaEfetivo;

    return Scaffold(
      appBar: AppBar(title: const Text('Configurações')),
      body: tabletBody(
        context,
        ListView(
          padding: const EdgeInsets.only(bottom: AppSpacing.xl),
          children: [
            const _TituloSecao('Perfil'),
            const _SecaoPerfil(),
            if (context.watch<ContaProvider>().disponivel) ...[
              const _TituloSecao('Conta'),
              const _SecaoConta(),
            ],
            const _TituloSecao('Atividade'),
            _OpcaoNavegacao(
              icone: Icons.history_rounded,
              titulo: 'Histórico',
              subtitulo: 'Canais e episódios assistidos recentemente',
              onTap: () => Navigator.of(context).push(
                MaterialPageRoute(builder: (_) => const TelaHistorico()),
              ),
            ),
            const _TituloSecao('Reprodução'),
            _OpcaoToggle(
              titulo: 'Ajuste automático de qualidade',
              subtitulo:
                  'Reduz a qualidade automaticamente quando a conexão está instável.',
              valor: preferencias.autoQualidade,
              onChanged: preferencias.definirAutoQualidade,
              beta: true,
            ),
            const _TituloSecao('Idioma do áudio'),
            Padding(
              padding: const EdgeInsets.fromLTRB(
                AppSpacing.lg,
                0,
                AppSpacing.lg,
                AppSpacing.sm,
              ),
              child: Text(
                'Define o idioma padrão das faixas de áudio: ao reproduzir, a '
                'faixa nesse idioma é selecionada automaticamente quando '
                'disponível. Não traduz a interface do app.',
                style: Theme.of(context).textTheme.bodySmall,
              ),
            ),
            for (final idioma in IdiomaApp.values)
              _OpcaoIdioma(
                idioma: idioma,
                selecionado: idioma == idiomaAtual,
                onTap: () => preferencias.definirIdioma(idioma),
              ),
          ],
        ),
      ),
    );
  }
}

/// Mostra o perfil ativo e permite voltar para a tela "Quem esta assistindo".
class _SecaoPerfil extends StatelessWidget {
  const _SecaoPerfil();

  @override
  Widget build(BuildContext context) {
    final ativo = context.watch<PerfilProvider>().perfilAtivo;
    return Padding(
      padding: const EdgeInsets.symmetric(
        horizontal: AppSpacing.lg,
        vertical: AppSpacing.md,
      ),
      child: Row(
        children: [
          if (ativo != null)
            AvatarPerfil(chave: ativo.icone, tamanho: 44, animar: false)
          else
            const SizedBox(width: 44, height: 44),
          const SizedBox(width: AppSpacing.base),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(ativo?.nome ?? 'Sem perfil',
                    style: Theme.of(context).textTheme.titleSmall),
                const SizedBox(height: 2),
                Text(
                  'Perfil ativo nesta sessão',
                  style: Theme.of(context).textTheme.bodySmall,
                ),
              ],
            ),
          ),
          const SizedBox(width: AppSpacing.sm),
          OutlinedButton.icon(
            onPressed: () {
              context.read<PerfilProvider>().trocarPerfil();
              Navigator.of(context).popUntil((r) => r.isFirst);
            },
            icon: const Icon(Icons.switch_account_rounded, size: 16),
            label: const Text('Trocar'),
          ),
        ],
      ),
    );
  }
}

/// Mostra o estado da conta: se logado, email + sair; se nao, botao de entrar.
class _SecaoConta extends StatelessWidget {
  const _SecaoConta();

  @override
  Widget build(BuildContext context) {
    final conta = context.watch<ContaProvider>();

    if (!conta.estaLogado) {
      return _OpcaoNavegacao(
        icone: Icons.login_rounded,
        titulo: 'Entrar na conta',
        subtitulo: 'Carregue e sincronize suas listas na nuvem.',
        onTap: () => Navigator.of(context).push(
          MaterialPageRoute(builder: (_) => const TelaLogin()),
        ),
      );
    }

    return Padding(
      padding: const EdgeInsets.symmetric(
        horizontal: AppSpacing.lg,
        vertical: AppSpacing.md,
      ),
      child: Row(
        children: [
          Container(
            width: 40,
            height: 40,
            decoration: BoxDecoration(
              color: AppColors.accentDim,
              borderRadius: BorderRadius.circular(AppRadius.sm),
            ),
            child: const Icon(
              Icons.person_rounded,
              size: 20,
              color: AppColors.accentBright,
            ),
          ),
          const SizedBox(width: AppSpacing.base),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text('Conectado',
                    style: Theme.of(context).textTheme.titleSmall),
                const SizedBox(height: 2),
                Text(
                  conta.email ?? '',
                  style: Theme.of(context).textTheme.bodySmall,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
              ],
            ),
          ),
          const SizedBox(width: AppSpacing.sm),
          OutlinedButton.icon(
            onPressed: () => _sair(context),
            icon: const Icon(Icons.logout_rounded, size: 16),
            label: const Text('Sair'),
            style: OutlinedButton.styleFrom(
              foregroundColor: AppColors.error,
              side: const BorderSide(color: AppColors.error),
            ),
          ),
        ],
      ),
    );
  }

  Future<void> _sair(BuildContext context) async {
    final confirmar = await showDialog<bool>(
      context: context,
      builder: (_) => AlertDialog(
        title: const Text('Sair da conta?'),
        content: const Text(
          'Você sairá da sua conta neste aparelho. Para voltar a sincronizar '
          'listas e perfis, entre novamente.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('Cancelar'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(context, true),
            style: FilledButton.styleFrom(backgroundColor: AppColors.error),
            child: const Text('Sair'),
          ),
        ],
      ),
    );
    if (confirmar != true || !context.mounted) return;

    final conta = context.read<ContaProvider>();
    final perfis = context.read<PerfilProvider>();
    final preferencias = context.read<PreferenciasProvider>();
    final navigator = Navigator.of(context);

    await conta.sair();
    // NAO apagamos as listas no logout: o cache fica e o re-login na MESMA
    // conta volta instantaneo (sem re-baixar tudo). Se outra conta entrar, o
    // `prune` do sincronizarDoSupabase remove o que nao for dela. Apagar tudo
    // aqui causava ~40s de tela "Conectando" travada ao re-logar.
    await perfis.limparLocais();
    // Volta a exigir login na proxima abertura / imediatamente.
    await preferencias.reativarLogin();

    // Fecha as Configuracoes; o app.dart ja troca a home para a tela de login.
    navigator.popUntil((r) => r.isFirst);
  }
}

class _OpcaoNavegacao extends StatelessWidget {
  final IconData icone;
  final String titulo;
  final String subtitulo;
  final VoidCallback onTap;

  const _OpcaoNavegacao({
    required this.icone,
    required this.titulo,
    required this.subtitulo,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return InkWell(
      onTap: onTap,
      child: Padding(
        padding: const EdgeInsets.symmetric(
          horizontal: AppSpacing.lg,
          vertical: AppSpacing.md,
        ),
        child: Row(
          children: [
            Container(
              width: 40,
              height: 40,
              decoration: BoxDecoration(
                color: AppColors.surface2,
                borderRadius: BorderRadius.circular(AppRadius.sm),
              ),
              child: Icon(icone, size: 20, color: AppColors.textSecondary),
            ),
            const SizedBox(width: AppSpacing.base),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(titulo, style: Theme.of(context).textTheme.titleSmall),
                  const SizedBox(height: 2),
                  Text(
                    subtitulo,
                    style: Theme.of(context).textTheme.bodySmall,
                  ),
                ],
              ),
            ),
            const Icon(
              Icons.chevron_right_rounded,
              size: 20,
              color: AppColors.textTertiary,
            ),
          ],
        ),
      ),
    );
  }
}

class _TituloSecao extends StatelessWidget {
  final String texto;
  const _TituloSecao(this.texto);

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(
        AppSpacing.lg,
        AppSpacing.lg,
        AppSpacing.lg,
        AppSpacing.xs,
      ),
      child: Text(
        texto.toUpperCase(),
        style: Theme.of(context).textTheme.labelSmall?.copyWith(
              color: AppColors.textTertiary,
              letterSpacing: 0.6,
            ),
      ),
    );
  }
}

class _OpcaoToggle extends StatelessWidget {
  final String titulo;
  final String subtitulo;
  final bool valor;
  final ValueChanged<bool> onChanged;
  final bool beta;

  const _OpcaoToggle({
    required this.titulo,
    required this.subtitulo,
    required this.valor,
    required this.onChanged,
    this.beta = false,
  });

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(
        horizontal: AppSpacing.lg,
        vertical: AppSpacing.sm,
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Text(titulo, style: Theme.of(context).textTheme.titleSmall),
                    if (beta) ...[
                      const SizedBox(width: 8),
                      Container(
                        padding: const EdgeInsets.symmetric(
                            horizontal: 6, vertical: 2),
                        decoration: BoxDecoration(
                          color: AppColors.accentDim,
                          borderRadius: BorderRadius.circular(4),
                        ),
                        child: Text(
                          'BETA',
                          style:
                              Theme.of(context).textTheme.labelSmall?.copyWith(
                                    color: AppColors.accentBright,
                                    fontWeight: FontWeight.w700,
                                    fontSize: 10,
                                  ),
                        ),
                      ),
                    ],
                  ],
                ),
                const SizedBox(height: 2),
                Text(subtitulo,
                    style: Theme.of(context).textTheme.bodySmall),
              ],
            ),
          ),
          Switch(value: valor, onChanged: onChanged),
        ],
      ),
    );
  }
}

class _OpcaoIdioma extends StatelessWidget {
  final IdiomaApp idioma;
  final bool selecionado;
  final VoidCallback onTap;

  const _OpcaoIdioma({
    required this.idioma,
    required this.selecionado,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return InkWell(
      onTap: onTap,
      child: Padding(
        padding: const EdgeInsets.symmetric(
          horizontal: AppSpacing.lg,
          vertical: AppSpacing.md,
        ),
        child: Row(
          children: [
            Container(
              width: 40,
              height: 40,
              decoration: BoxDecoration(
                color: selecionado
                    ? AppColors.accentDim
                    : AppColors.surface2,
                borderRadius: BorderRadius.circular(AppRadius.sm),
              ),
              alignment: Alignment.center,
              child: Text(
                idioma.codigo.substring(0, 2).toUpperCase(),
                style: Theme.of(context).textTheme.labelMedium?.copyWith(
                      color: selecionado
                          ? AppColors.accentBright
                          : AppColors.textSecondary,
                      fontWeight: FontWeight.w700,
                    ),
              ),
            ),
            const SizedBox(width: AppSpacing.base),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    idioma.nome,
                    style: Theme.of(context).textTheme.titleSmall,
                  ),
                  Text(
                    idioma.regiao,
                    style: Theme.of(context).textTheme.bodySmall,
                  ),
                ],
              ),
            ),
            Icon(
              selecionado
                  ? Icons.check_circle_rounded
                  : Icons.circle_outlined,
              size: 22,
              color: selecionado
                  ? AppColors.accent
                  : AppColors.textTertiary,
            ),
          ],
        ),
      ),
    );
  }
}
