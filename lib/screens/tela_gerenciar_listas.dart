import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../models/lista_m3u.dart';
import '../state/conta_provider.dart';
import '../state/iptv_provider.dart';
import '../theme/app_theme.dart';
import '../utils/layout.dart';
import '../widgets/dialogo_editar_lista.dart';
import 'tela_importar.dart';

/// Gerenciador de listas IPTV: importar, editar (nome/M3U/EPG), ativar
/// e remover. Apenas uma lista pode estar ativa de cada vez — ativar uma
/// nova substitui a anterior automaticamente.
class TelaGerenciarListas extends StatelessWidget {
  const TelaGerenciarListas({super.key});

  @override
  Widget build(BuildContext context) {
    final provider = context.watch<IptvProvider>();
    final conta = context.watch<ContaProvider>();
    final listas = provider.listas;
    final podeSincronizar = conta.disponivel && conta.estaLogado;

    return Scaffold(
      appBar: AppBar(
        title: const Text('Gerenciar listas'),
        actions: [
          if (podeSincronizar) const _BotaoAtualizar(),
        ],
      ),
      body: SafeArea(
        child: tabletBody(
          context,
          listas.isEmpty && provider.sincronizando
              ? _SkeletonListas(count: provider.totalSync)
              : listas.isEmpty
                  ? const _SemListas()
                  : ListView.separated(
                  padding: const EdgeInsets.fromLTRB(
                    AppSpacing.lg,
                    AppSpacing.base,
                    AppSpacing.lg,
                    96,
                  ),
                  itemCount: listas.length,
                  separatorBuilder: (_, _) =>
                      const SizedBox(height: AppSpacing.md),
                  itemBuilder: (_, i) => _ItemLista(lista: listas[i]),
                ),
        ),
      ),
      floatingActionButton: FloatingActionButton.extended(
        onPressed: () => Navigator.of(context).push(
          MaterialPageRoute(builder: (_) => const TelaImportar()),
        ),
        icon: const Icon(Icons.add_rounded),
        label: const Text('Importar lista'),
      ),
    );
  }
}

// ─── Botao de atualizar (sincronizar com a nuvem) ─────────────────────────────

/// Puxa de novo as listas da conta no Supabase — util quando o usuario
/// adicionou/removeu uma lista pelo site. Enquanto sincroniza, vira spinner.
class _BotaoAtualizar extends StatelessWidget {
  const _BotaoAtualizar();

  @override
  Widget build(BuildContext context) {
    final sincronizando = context.watch<IptvProvider>().sincronizando;

    if (sincronizando) {
      return const Padding(
        padding: EdgeInsets.symmetric(horizontal: AppSpacing.base),
        child: Center(
          child: SizedBox(
            width: 18,
            height: 18,
            child: CircularProgressIndicator(strokeWidth: 2),
          ),
        ),
      );
    }

    return IconButton(
      tooltip: 'Atualizar listas',
      icon: const Icon(Icons.cloud_sync_rounded),
      onPressed: () async {
        final provider = context.read<IptvProvider>();
        final messenger = ScaffoldMessenger.of(context);
        await provider.sincronizarDoSupabase();
        if (!context.mounted) return;
        messenger.showSnackBar(
          const SnackBar(content: Text('Listas atualizadas')),
        );
      },
    );
  }
}

// ─── Skeleton Loading ─────────────────────────────────────────────────────────

/// Substituto animado para a lista enquanto as listas da conta carregam.
/// Exibe [count] blocos (ou 2 por padrao) que imitam o layout de [_ItemLista]
/// com efeito shimmer — o brilho varre da esquerda para a direita em loop.
class _SkeletonListas extends StatefulWidget {
  final int count;
  const _SkeletonListas({required this.count});

  @override
  State<_SkeletonListas> createState() => _SkeletonListasState();
}

class _SkeletonListasState extends State<_SkeletonListas>
    with SingleTickerProviderStateMixin {
  late final AnimationController _ctrl;

  @override
  void initState() {
    super.initState();
    _ctrl = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 1300),
    )..repeat();
  }

  @override
  void dispose() {
    _ctrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final n = widget.count > 0 ? widget.count : 2;
    return AnimatedBuilder(
      animation: _ctrl,
      builder: (context, _) => ListView.separated(
        padding: const EdgeInsets.fromLTRB(
          AppSpacing.lg,
          AppSpacing.base,
          AppSpacing.lg,
          96,
        ),
        itemCount: n,
        separatorBuilder: (_, _) => const SizedBox(height: AppSpacing.md),
        itemBuilder: (context, i) => _SkeletonItem(t: _ctrl.value),
      ),
    );
  }
}

/// Um bloco de placeholder que replica as dimensoes de [_ItemLista].
class _SkeletonItem extends StatelessWidget {
  final double t; // 0.0–1.0: posicao do shimmer
  const _SkeletonItem({required this.t});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(AppSpacing.base),
      decoration: BoxDecoration(
        color: AppColors.surface1,
        borderRadius: BorderRadius.circular(AppRadius.lg),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              // Caixa do contador de canais (48x48)
              _barra(width: 48, height: 48, radius: AppRadius.base),
              const SizedBox(width: AppSpacing.base),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const SizedBox(height: 3),
                    // Linha do nome
                    _barra(height: 13, radius: AppRadius.sm),
                    const SizedBox(height: 7),
                    // Linha do subtitulo (mais curta)
                    _barra(height: 11, radius: AppRadius.sm, widthFactor: 0.55),
                  ],
                ),
              ),
            ],
          ),
          const SizedBox(height: AppSpacing.base),
          // Botoes Ativar / Editar
          Row(
            children: [
              Expanded(child: _barra(height: 36, radius: AppRadius.base)),
              const SizedBox(width: AppSpacing.sm),
              Expanded(child: _barra(height: 36, radius: AppRadius.base)),
            ],
          ),
        ],
      ),
    );
  }

  Widget _barra({
    double? width,
    required double height,
    required double radius,
    double widthFactor = 1.0,
  }) {
    // Shimmer: gradiente que varre da esquerda para a direita.
    // Intervalo [-2, 2] no espaco de alinhamento (fora → dentro → fora).
    final sweep = -2.0 + t * 4.0;
    return FractionallySizedBox(
      widthFactor: width == null ? widthFactor : null,
      child: SizedBox(
        width: width,
        height: height,
        child: DecoratedBox(
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(radius),
            gradient: LinearGradient(
              begin: Alignment(sweep - 1, 0),
              end: Alignment(sweep + 1, 0),
              colors: const [
                AppColors.surface2,
                AppColors.surface3,
                AppColors.surface2,
              ],
            ),
          ),
        ),
      ),
    );
  }
}

// ─── Vazio ────────────────────────────────────────────────────────────────────

class _SemListas extends StatelessWidget {
  const _SemListas();

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: AppSpacing.xl),
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Container(
            width: 72,
            height: 72,
            decoration: BoxDecoration(
              color: AppColors.surface1,
              borderRadius: BorderRadius.circular(AppRadius.lg),
            ),
            child: const Icon(
              Icons.playlist_add_rounded,
              size: 36,
              color: AppColors.accent,
            ),
          ),
          const SizedBox(height: AppSpacing.lg),
          Text(
            'Nenhuma lista ainda',
            style: Theme.of(context).textTheme.titleLarge,
            textAlign: TextAlign.center,
          ),
          const SizedBox(height: AppSpacing.sm),
          Text(
            'Toque em "Importar lista" para adicionar sua primeira lista IPTV.',
            style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                  color: AppColors.textSecondary,
                ),
            textAlign: TextAlign.center,
          ),
        ],
      ),
    );
  }
}

// ─── Card de lista ────────────────────────────────────────────────────────────

class _ItemLista extends StatelessWidget {
  final ListaM3U lista;
  const _ItemLista({required this.lista});

  @override
  Widget build(BuildContext context) {
    final provider = context.watch<IptvProvider>();
    final ativa = provider.ehListaAtiva(lista);
    final origem = lista.origem == OrigemLista.url ? 'URL' : 'Arquivo';

    return Material(
      color: ativa ? AppColors.accentDim : AppColors.surface1,
      borderRadius: BorderRadius.circular(AppRadius.lg),
      child: InkWell(
        onTap: ativa ? null : () => provider.ativarLista(lista),
        borderRadius: BorderRadius.circular(AppRadius.lg),
        child: Padding(
          padding: const EdgeInsets.all(AppSpacing.base),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Container(
                    width: 48,
                    height: 48,
                    decoration: BoxDecoration(
                      color: ativa
                          ? AppColors.surface0
                          : AppColors.surface2,
                      borderRadius: BorderRadius.circular(AppRadius.base),
                      border: Border.all(
                        color: ativa
                            ? AppColors.accent.withValues(alpha: 0.4)
                            : AppColors.outlineSubtle,
                      ),
                    ),
                    alignment: Alignment.center,
                    child: Text(
                      lista.totalCanais > 9999
                          ? '${lista.totalCanais ~/ 1000}k'
                          : '${lista.totalCanais}',
                      style: tabular(
                        Theme.of(context).textTheme.labelMedium?.copyWith(
                              color: ativa
                                  ? AppColors.accentBright
                                  : AppColors.textPrimary,
                              fontWeight: FontWeight.w700,
                            ),
                      ),
                    ),
                  ),
                  const SizedBox(width: AppSpacing.base),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Row(
                          children: [
                            Expanded(
                              child: Text(
                                lista.nome,
                                style:
                                    Theme.of(context).textTheme.titleSmall,
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                              ),
                            ),
                            if (ativa) const _BadgeAtiva(),
                          ],
                        ),
                        const SizedBox(height: 2),
                        Text(
                          '$origem · ${lista.totalCanais} canais'
                          '${lista.epgUrl != null ? " · EPG" : ""}',
                          style: Theme.of(context).textTheme.bodySmall,
                        ),
                      ],
                    ),
                  ),
                  _MenuLista(lista: lista),
                ],
              ),
              const SizedBox(height: AppSpacing.base),
              Row(
                children: [
                  Expanded(
                    child: ativa
                        ? OutlinedButton.icon(
                            onPressed: null,
                            icon: const Icon(Icons.check_circle_rounded,
                                size: 16),
                            label: const Text('Lista ativa'),
                            style: OutlinedButton.styleFrom(
                              foregroundColor: AppColors.accentBright,
                              disabledForegroundColor:
                                  AppColors.accentBright,
                              side: const BorderSide(
                                  color: AppColors.accent),
                            ),
                          )
                        : FilledButton.tonalIcon(
                            onPressed: () => provider.ativarLista(lista),
                            icon: const Icon(Icons.radio_button_unchecked,
                                size: 16),
                            label: const Text('Ativar'),
                          ),
                  ),
                  const SizedBox(width: AppSpacing.sm),
                  Expanded(
                    child: OutlinedButton.icon(
                      onPressed: () => dialogoEditarLista(context, lista),
                      icon: const Icon(Icons.edit_rounded, size: 16),
                      label: const Text('Editar'),
                    ),
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _BadgeAtiva extends StatelessWidget {
  const _BadgeAtiva();

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
      decoration: BoxDecoration(
        color: AppColors.accent,
        borderRadius: BorderRadius.circular(AppRadius.pill),
      ),
      child: Text(
        'ATIVA',
        style: Theme.of(context).textTheme.labelSmall?.copyWith(
              color: AppColors.accentOn,
              fontWeight: FontWeight.w700,
              fontSize: 10,
              letterSpacing: 0.5,
            ),
      ),
    );
  }
}

class _MenuLista extends StatelessWidget {
  final ListaM3U lista;
  const _MenuLista({required this.lista});

  @override
  Widget build(BuildContext context) {
    return PopupMenuButton<String>(
      icon: const Icon(
        Icons.more_vert_rounded,
        color: AppColors.textSecondary,
        size: 20,
      ),
      onSelected: (acao) => _executar(context, acao),
      itemBuilder: (_) => [
        if (lista.origem == OrigemLista.url)
          const PopupMenuItem(
            value: 'atualizar',
            child: Row(
              children: [
                Icon(Icons.refresh_rounded, size: 18),
                SizedBox(width: AppSpacing.md),
                Text('Atualizar canais'),
              ],
            ),
          ),
        const PopupMenuItem(
          value: 'editar',
          child: Row(
            children: [
              Icon(Icons.edit_rounded, size: 18),
              SizedBox(width: AppSpacing.md),
              Text('Editar lista'),
            ],
          ),
        ),
        const PopupMenuItem(
          value: 'remover',
          child: Row(
            children: [
              Icon(
                Icons.delete_outline_rounded,
                size: 18,
                color: AppColors.error,
              ),
              SizedBox(width: AppSpacing.md),
              Text('Remover', style: TextStyle(color: AppColors.error)),
            ],
          ),
        ),
      ],
    );
  }

  Future<void> _executar(BuildContext context, String acao) async {
    final provider = context.read<IptvProvider>();
    final messenger = ScaffoldMessenger.of(context);

    if (acao == 'atualizar') {
      await provider.atualizarLista(lista);
      if (provider.erro != null) {
        messenger.showSnackBar(SnackBar(content: Text(provider.erro!)));
        provider.limparErro();
      } else {
        messenger.showSnackBar(
          const SnackBar(content: Text('Lista atualizada')),
        );
      }
    } else if (acao == 'editar') {
      await dialogoEditarLista(context, lista);
    } else if (acao == 'remover') {
      final confirmar = await showDialog<bool>(
        context: context,
        builder: (_) => AlertDialog(
          title: const Text('Remover lista?'),
          content: Text('A lista "${lista.nome}" sera apagada.'),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(context, false),
              child: const Text('Cancelar'),
            ),
            FilledButton(
              onPressed: () => Navigator.pop(context, true),
              style:
                  FilledButton.styleFrom(backgroundColor: AppColors.error),
              child: const Text('Remover'),
            ),
          ],
        ),
      );
      if (confirmar == true) await provider.removerLista(lista);
    }
  }
}