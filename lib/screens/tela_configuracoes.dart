import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../models/idioma_app.dart';
import '../services/dispositivo.dart';
import '../state/dispositivo_provider.dart';
import '../state/iptv_provider.dart';
import '../state/perfil_provider.dart';
import '../state/preferencias_provider.dart';
import '../theme/app_theme.dart';
import '../utils/layout.dart';
import '../widgets/avatar_perfil.dart';
import 'tela_controle_pais.dart';
import 'tela_historico.dart';

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
          // A barra de gestos do Android fica POR CIMA do conteudo (o app roda
          // edge-to-edge): sem este respiro, o ultimo item da lista — hoje o
          // idioma Espanhol — fica coberto e nao da para tocar.
          padding: EdgeInsets.only(
            bottom: AppSpacing.xl + MediaQuery.viewPaddingOf(context).bottom,
          ),
          children: [
            const _TituloSecao('Perfil'),
            const _SecaoPerfil(),
            const _TituloSecao('Aparelho'),
            const _SecaoDispositivo(),
            const _TituloSecao('Controle dos pais'),
            _OpcaoNavegacao(
              icone: Icons.lock_outline_rounded,
              titulo: 'Bloquear categorias',
              subtitulo: preferencias.controleParentalAtivo
                  ? '${preferencias.categoriasBloqueadas.length} categoria(s) '
                      'bloqueada(s) neste perfil'
                  : 'Defina um PIN e escolha o que fica bloqueado',
              onTap: () => Navigator.of(context).push(
                MaterialPageRoute(builder: (_) => const TelaControlePais()),
              ),
            ),
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

/// Identificacao do aparelho (ID + Chave) e estado da ativacao. Substitui a
/// antiga secao de conta: nao ha login por e-mail — a identidade e o aparelho.
class _SecaoDispositivo extends StatelessWidget {
  const _SecaoDispositivo();

  // Na build de LOJA o app nao pode sinalizar cobranca: "Em teste" e
  // "Expirado" viram estados neutros (o aparelho esta funcionando, ou nao tem
  // lista). A build direta, distribuida pelo site, mostra o estado real.
  static const _rotulosDireto = {
    'ativo': 'Ativo',
    'trial': 'Em teste',
    'expirado': 'Acesso vencido',
    'sem_lista': 'Sem lista vinculada',
  };
  static const _rotulosLoja = {
    'ativo': 'Ativo',
    'trial': 'Ativo',
    'expirado': 'Sem lista vinculada',
    'sem_lista': 'Sem lista vinculada',
  };

  @override
  Widget build(BuildContext context) {
    final d = context.watch<DispositivoProvider>();
    final t = Theme.of(context).textTheme;
    final direto = Dispositivo.mostraAtivacaoNoApp;
    final rotulos = direto ? _rotulosDireto : _rotulosLoja;
    final rotulo = rotulos[d.status] ?? d.status;
    final cor = switch (direto ? d.status : (d.expirado ? 'sem_lista' : 'ativo')) {
      'ativo' => AppColors.success,
      'trial' => AppColors.warn,
      'expirado' => AppColors.error,
      _ => AppColors.textSecondary,
    };
    return Padding(
      padding: const EdgeInsets.symmetric(
        horizontal: AppSpacing.lg,
        vertical: AppSpacing.md,
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Container(
                width: 8,
                height: 8,
                decoration: BoxDecoration(color: cor, shape: BoxShape.circle),
              ),
              const SizedBox(width: AppSpacing.sm),
              Text(rotulo, style: t.titleSmall?.copyWith(color: cor)),
              // Contagem do teste so na build direta (ver comentario acima).
              if (direto && d.emTeste) ...[
                const SizedBox(width: AppSpacing.sm),
                Text('· ${d.diasTeste} dia(s)', style: t.bodySmall),
              ],
              const Spacer(),
              TextButton(
                onPressed: d.consultando
                    ? null
                    : () async {
                        final iptv = context.read<IptvProvider>();
                        if (await d.reconsultar()) {
                          await iptv.sincronizarComDispositivo();
                        }
                      },
                child: const Text('Verificar'),
              ),
            ],
          ),
          const SizedBox(height: AppSpacing.sm),
          SelectableText(
            'ID  ${d.mac}\nChave  ${d.chave}',
            style: t.bodySmall?.copyWith(color: AppColors.textSecondary),
          ),
        ],
      ),
    );
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
