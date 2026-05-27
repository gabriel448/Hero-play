import 'dart:async';

import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../models/canal.dart';
import '../models/programa.dart';
import '../services/servico_epg.dart';
import '../theme/app_theme.dart';
import '../utils/layout.dart';

/// Abre o modal de programacao com a agenda completa do [canal] na [idLista].
///
/// Mobile: bottom sheet quase fullscreen.
/// Tablet/Desktop: dialog centralizado com largura limitada.
Future<void> mostrarModalProgramacao(
  BuildContext context, {
  required Canal canal,
  required String idLista,
}) {
  if (isPhone(context)) {
    return showModalBottomSheet<void>(
      context: context,
      backgroundColor: AppColors.surface2,
      isScrollControlled: true,
      useSafeArea: true,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(AppRadius.lg)),
      ),
      builder: (_) => FractionallySizedBox(
        heightFactor: 0.9,
        child: _ConteudoModalProgramacao(canal: canal, idLista: idLista),
      ),
    );
  }
  return showDialog<void>(
    context: context,
    barrierColor: Colors.black54,
    builder: (_) => Dialog(
      backgroundColor: AppColors.surface2,
      insetPadding: const EdgeInsets.all(AppSpacing.xl),
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(AppRadius.lg),
      ),
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 560, maxHeight: 720),
        child: _ConteudoModalProgramacao(canal: canal, idLista: idLista),
      ),
    ),
  );
}

/// Abre um modal simples com os detalhes completos de um [programa].
/// Mostra logo do canal, horario, titulo e descricao sem truncamento.
/// Disponivel apenas em phone e tablet (nao usado no desktop).
Future<void> mostrarDetalhesPrograma(
  BuildContext context, {
  required Canal canal,
  required Programa programa,
}) {
  final conteudo = _ConteudoDetalhes(canal: canal, programa: programa);
  if (isPhone(context)) {
    return showModalBottomSheet<void>(
      context: context,
      backgroundColor: AppColors.surface2,
      isScrollControlled: true,
      useSafeArea: true,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(AppRadius.lg)),
      ),
      builder: (_) => conteudo,
    );
  }
  return showDialog<void>(
    context: context,
    barrierColor: Colors.black54,
    builder: (_) => Dialog(
      backgroundColor: AppColors.surface2,
      insetPadding: const EdgeInsets.all(AppSpacing.xl),
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(AppRadius.lg),
      ),
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 480, maxHeight: 620),
        child: conteudo,
      ),
    ),
  );
}

class _ConteudoModalProgramacao extends StatefulWidget {
  final Canal canal;
  final String idLista;

  const _ConteudoModalProgramacao({
    required this.canal,
    required this.idLista,
  });

  @override
  State<_ConteudoModalProgramacao> createState() =>
      _ConteudoModalProgramacaoState();
}

class _ConteudoModalProgramacaoState extends State<_ConteudoModalProgramacao> {
  Timer? _ticker;

  @override
  void initState() {
    super.initState();
    // Tick a cada 30s para o item "atual" mover quando o programa virar.
    _ticker = Timer.periodic(const Duration(seconds: 30), (_) {
      if (mounted) setState(() {});
    });
  }

  @override
  void dispose() {
    _ticker?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final epg = context.watch<ServicoEpg>();
    final todos = epg.programasPara(idLista: widget.idLista, canal: widget.canal);
    final agora = DateTime.now();
    // Mostra so a partir do atual em diante — passado nao interessa.
    final indexAtual = todos.indexWhere((p) => p.ehAtual(agora));
    final inicioFuturos = indexAtual >= 0
        ? indexAtual
        : todos.indexWhere((p) => p.inicio.isAfter(agora));
    final visiveis = inicioFuturos >= 0 ? todos.sublist(inicioFuturos) : <Programa>[];
    final carregando = epg.estaCarregando(widget.idLista);

    return Padding(
      padding: const EdgeInsets.fromLTRB(
        AppSpacing.lg,
        AppSpacing.md,
        AppSpacing.lg,
        AppSpacing.base,
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          // Handle (apenas phone bottom sheet)
          if (isPhone(context))
            Center(
              child: Container(
                width: 36,
                height: 4,
                margin: const EdgeInsets.only(bottom: AppSpacing.base),
                decoration: BoxDecoration(
                  color: AppColors.outlineSubtle,
                  borderRadius: BorderRadius.circular(AppRadius.pill),
                ),
              ),
            ),

          // ── Cabecalho: logo + nome + close ────────────────────────────────
          Row(
            crossAxisAlignment: CrossAxisAlignment.center,
            children: [
              _LogoCanal(canal: widget.canal),
              const SizedBox(width: AppSpacing.md),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Text(
                      widget.canal.nome,
                      style: Theme.of(context).textTheme.titleMedium,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                    Text(
                      'Programacao',
                      style: Theme.of(context).textTheme.bodySmall?.copyWith(
                            color: AppColors.textTertiary,
                          ),
                    ),
                  ],
                ),
              ),
              IconButton(
                icon: const Icon(Icons.close_rounded),
                color: AppColors.textSecondary,
                onPressed: () => Navigator.of(context).pop(),
              ),
            ],
          ),
          const SizedBox(height: AppSpacing.sm),
          const Divider(height: 1, color: AppColors.divider),

          // ── Conteudo: lista de programas ──────────────────────────────────
          Expanded(
            child: visiveis.isEmpty
                ? _ModalEpgVazio(carregando: carregando)
                : _ListaProgramas(programas: visiveis, agora: agora, canal: widget.canal),
          ),
        ],
      ),
    );
  }
}

class _ListaProgramas extends StatelessWidget {
  final List<Programa> programas;
  final DateTime agora;
  final Canal canal;

  const _ListaProgramas({
    required this.programas,
    required this.agora,
    required this.canal,
  });

  @override
  Widget build(BuildContext context) {
    String? ultimaData;
    final widgets = <Widget>[];

    for (var i = 0; i < programas.length; i++) {
      final p = programas[i];
      final dataLocal = _rotuloData(p.inicio.toLocal(), agora);
      if (dataLocal != ultimaData) {
        widgets.add(_SeparadorDia(rotulo: dataLocal));
        ultimaData = dataLocal;
      }
      final atual = p.ehAtual(agora);
      widgets.add(_LinhaProgramaModal(programa: p, atual: atual, canal: canal));
    }

    return ListView(
      padding: const EdgeInsets.only(top: AppSpacing.sm, bottom: AppSpacing.base),
      children: widgets,
    );
  }
}

class _SeparadorDia extends StatelessWidget {
  final String rotulo;
  const _SeparadorDia({required this.rotulo});

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(
        0,
        AppSpacing.md,
        0,
        AppSpacing.xs,
      ),
      child: Text(
        rotulo,
        style: Theme.of(context).textTheme.labelSmall?.copyWith(
              color: AppColors.textTertiary,
              letterSpacing: 0.6,
            ),
      ),
    );
  }
}

/// Linha completa de programa: horario + programa em blocos separados.
/// Reutilizada pelo modal e pelo player embutido do desktop.
class LinhaProgramaBlocos extends StatelessWidget {
  final Programa programa;
  final bool atual;
  /// Quando true, usa metricas e fontes maiores. Util quando ha bastante
  /// espaco horizontal (tablet, desktop).
  final bool versaoLarga;
  /// Quando nao-null, toda a linha fica tappable (phone/tablet apenas).
  final VoidCallback? onTap;

  const LinhaProgramaBlocos({
    super.key,
    required this.programa,
    required this.atual,
    this.versaoLarga = false,
    this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final largo = versaoLarga;
    final largurahora = largo ? 100.0 : 80.0;

    final conteudo = Padding(
      padding: const EdgeInsets.symmetric(vertical: AppSpacing.xs),
      child: IntrinsicHeight(
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            BlocoHorario(
              programa: programa,
              atual: atual,
              tablet: largo,
              largura: largurahora,
            ),
            const SizedBox(width: AppSpacing.sm),
            Expanded(
              child: BlocoPrograma(
                programa: programa,
                atual: atual,
                tablet: largo,
              ),
            ),
          ],
        ),
      ),
    );
    if (onTap == null) return conteudo;
    return GestureDetector(
      onTap: onTap,
      behavior: HitTestBehavior.opaque,
      child: conteudo,
    );
  }
}

class _LinhaProgramaModal extends StatelessWidget {
  final Programa programa;
  final bool atual;
  final Canal canal;

  const _LinhaProgramaModal({
    required this.programa,
    required this.atual,
    required this.canal,
  });

  @override
  Widget build(BuildContext context) {
    return LinhaProgramaBlocos(
      programa: programa,
      atual: atual,
      versaoLarga: isTablet(context),
      onTap: !isDesktop(context)
          ? () => mostrarDetalhesPrograma(
                context,
                canal: canal,
                programa: programa,
              )
          : null,
    );
  }
}

/// Bloco lateral com o horario de inicio/fim. Quando o programa esta em
/// exibicao agora, o fundo fica tintado com accent e exibe o badge "AGORA".
class BlocoHorario extends StatelessWidget {
  final Programa programa;
  final bool atual;
  final bool tablet;
  final double largura;

  const BlocoHorario({
    super.key,
    required this.programa,
    required this.atual,
    required this.tablet,
    required this.largura,
  });

  @override
  Widget build(BuildContext context) {
    final corFundo =
        atual ? AppColors.accent.withValues(alpha: 0.18) : AppColors.surface3;
    final corBorda = atual
        ? AppColors.accent.withValues(alpha: 0.45)
        : Colors.transparent;
    final corTexto = atual ? AppColors.accentBright : AppColors.textPrimary;
    final corLabel = atual
        ? AppColors.accent
        : AppColors.textTertiary;

    return Container(
      width: largura,
      padding: EdgeInsets.symmetric(
        horizontal: AppSpacing.sm,
        vertical: tablet ? AppSpacing.md : AppSpacing.sm,
      ),
      decoration: BoxDecoration(
        color: corFundo,
        borderRadius: BorderRadius.circular(AppRadius.sm),
        border: Border.all(color: corBorda, width: 1),
      ),
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        crossAxisAlignment: CrossAxisAlignment.center,
        children: [
          Text(
            _hhmm(programa.inicio),
            style: TextStyle(
              fontSize: tablet ? 17 : 15,
              fontWeight: FontWeight.w700,
              color: corTexto,
              fontFeatures: const [FontFeature.tabularFigures()],
              height: 1.1,
            ),
          ),
          const SizedBox(height: 2),
          Text(
            'ate ${_hhmm(programa.fim)}',
            style: TextStyle(
              fontSize: tablet ? 11 : 10.5,
              fontWeight: FontWeight.w500,
              color: corLabel,
              letterSpacing: 0.3,
              fontFeatures: const [FontFeature.tabularFigures()],
            ),
          ),
          if (atual) ...[
            const SizedBox(height: AppSpacing.xs),
            Container(
              padding: const EdgeInsets.symmetric(
                horizontal: AppSpacing.xs,
                vertical: 2,
              ),
              decoration: BoxDecoration(
                color: AppColors.accent,
                borderRadius: BorderRadius.circular(AppRadius.sm),
              ),
              child: const Text(
                'AGORA',
                style: TextStyle(
                  fontSize: 9.5,
                  fontWeight: FontWeight.w800,
                  color: AppColors.accentOn,
                  letterSpacing: 0.8,
                ),
              ),
            ),
          ],
        ],
      ),
    );
  }
}

/// Bloco do programa: titulo + descricao. Mais largo que o bloco do horario;
/// quando atual, recebe o mesmo tratamento de destaque (fundo accentDim).
class BlocoPrograma extends StatelessWidget {
  final Programa programa;
  final bool atual;
  final bool tablet;

  const BlocoPrograma({
    super.key,
    required this.programa,
    required this.atual,
    required this.tablet,
  });

  @override
  Widget build(BuildContext context) {
    final corFundo = atual
        ? AppColors.accentDim.withValues(alpha: 0.45)
        : AppColors.surface1;
    final corBorda = atual
        ? AppColors.accent.withValues(alpha: 0.45)
        : Colors.transparent;
    final corTitulo = atual ? AppColors.accentBright : AppColors.textPrimary;
    final corDesc = atual
        ? AppColors.textPrimary.withValues(alpha: 0.85)
        : AppColors.textSecondary;

    return Container(
      padding: EdgeInsets.symmetric(
        horizontal: AppSpacing.md,
        vertical: tablet ? AppSpacing.md : AppSpacing.sm,
      ),
      decoration: BoxDecoration(
        color: corFundo,
        borderRadius: BorderRadius.circular(AppRadius.sm),
        border: Border.all(color: corBorda, width: 1),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Text(
            programa.titulo,
            style: TextStyle(
              fontSize: tablet ? 15 : 14,
              fontWeight: atual ? FontWeight.w700 : FontWeight.w600,
              color: corTitulo,
              height: 1.3,
            ),
          ),
          if (programa.descricao != null && programa.descricao!.isNotEmpty) ...[
            const SizedBox(height: 4),
            Text(
              programa.descricao!,
              maxLines: atual ? 4 : 2,
              overflow: TextOverflow.ellipsis,
              style: TextStyle(
                fontSize: tablet ? 12.5 : 12,
                color: corDesc,
                height: 1.4,
              ),
            ),
          ],
        ],
      ),
    );
  }
}

// ─── Modal de detalhes de um programa ────────────────────────────────────────

class _ConteudoDetalhes extends StatelessWidget {
  final Canal canal;
  final Programa programa;

  const _ConteudoDetalhes({required this.canal, required this.programa});

  @override
  Widget build(BuildContext context) {
    final tablet = isTablet(context);
    final temDesc = programa.descricao != null && programa.descricao!.isNotEmpty;
    final atual = programa.ehAtual();

    return SingleChildScrollView(
      padding: const EdgeInsets.fromLTRB(
        AppSpacing.lg,
        AppSpacing.md,
        AppSpacing.lg,
        AppSpacing.lg,
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        mainAxisSize: MainAxisSize.min,
        children: [
          // Handle (phone)
          if (isPhone(context))
            Center(
              child: Container(
                width: 36,
                height: 4,
                margin: const EdgeInsets.only(bottom: AppSpacing.base),
                decoration: BoxDecoration(
                  color: AppColors.outlineSubtle,
                  borderRadius: BorderRadius.circular(AppRadius.pill),
                ),
              ),
            ),

          // Logo + nome do canal + botao fechar
          Row(
            children: [
              _LogoCanal(canal: canal),
              const SizedBox(width: AppSpacing.md),
              Expanded(
                child: Text(
                  canal.nome,
                  style: Theme.of(context).textTheme.labelLarge?.copyWith(
                        color: AppColors.textSecondary,
                      ),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
              ),
              IconButton(
                icon: const Icon(Icons.close_rounded),
                color: AppColors.textSecondary,
                onPressed: () => Navigator.of(context).pop(),
              ),
            ],
          ),
          const SizedBox(height: AppSpacing.sm),
          const Divider(height: 1, color: AppColors.divider),
          const SizedBox(height: AppSpacing.base),

          // Horario + badge AGORA
          Wrap(
            spacing: AppSpacing.sm,
            runSpacing: AppSpacing.xs,
            crossAxisAlignment: WrapCrossAlignment.center,
            children: [
              Container(
                padding: const EdgeInsets.symmetric(
                  horizontal: AppSpacing.sm,
                  vertical: AppSpacing.xs,
                ),
                decoration: BoxDecoration(
                  color: atual
                      ? AppColors.accent.withValues(alpha: 0.18)
                      : AppColors.surface3,
                  borderRadius: BorderRadius.circular(AppRadius.sm),
                  border: Border.all(
                    color: atual
                        ? AppColors.accent.withValues(alpha: 0.45)
                        : Colors.transparent,
                  ),
                ),
                child: Text(
                  '${_hhmm(programa.inicio)} – ${_hhmm(programa.fim)}',
                  style: TextStyle(
                    fontSize: tablet ? 14 : 13,
                    fontWeight: FontWeight.w700,
                    color:
                        atual ? AppColors.accentBright : AppColors.textPrimary,
                    fontFeatures: const [FontFeature.tabularFigures()],
                  ),
                ),
              ),
              if (atual)
                Container(
                  padding: const EdgeInsets.symmetric(
                    horizontal: AppSpacing.sm,
                    vertical: 3,
                  ),
                  decoration: BoxDecoration(
                    color: AppColors.accent,
                    borderRadius: BorderRadius.circular(AppRadius.sm),
                  ),
                  child: const Text(
                    'AGORA',
                    style: TextStyle(
                      fontSize: 10,
                      fontWeight: FontWeight.w800,
                      color: AppColors.accentOn,
                      letterSpacing: 0.8,
                    ),
                  ),
                ),
            ],
          ),
          const SizedBox(height: AppSpacing.sm),

          // Titulo
          Text(
            programa.titulo,
            style: TextStyle(
              fontSize: tablet ? 18 : 16,
              fontWeight: FontWeight.w700,
              color: AppColors.textPrimary,
              height: 1.3,
            ),
          ),

          // Descricao completa (sem limite de linhas)
          if (temDesc) ...[
            const SizedBox(height: AppSpacing.sm),
            Text(
              programa.descricao!,
              style: TextStyle(
                fontSize: tablet ? 14 : 13,
                color: AppColors.textSecondary,
                height: 1.5,
              ),
            ),
          ] else ...[
            const SizedBox(height: AppSpacing.xs),
            Text(
              'Sem descricao disponivel.',
              style: TextStyle(
                fontSize: tablet ? 13 : 12,
                color: AppColors.textTertiary,
                fontStyle: FontStyle.italic,
              ),
            ),
          ],
        ],
      ),
    );
  }
}

class _LogoCanal extends StatelessWidget {
  final Canal canal;
  const _LogoCanal({required this.canal});

  @override
  Widget build(BuildContext context) {
    final tamanho = isTablet(context) ? 56.0 : 48.0;
    final tem = canal.logoUrl != null && canal.logoUrl!.isNotEmpty;
    return Container(
      width: tamanho,
      height: tamanho,
      decoration: BoxDecoration(
        color: AppColors.surface3,
        borderRadius: BorderRadius.circular(AppRadius.sm),
      ),
      clipBehavior: Clip.antiAlias,
      child: tem
          ? Image.network(
              canal.logoUrl!,
              fit: BoxFit.contain,
              errorBuilder: (_, _, _) => const _LogoFallback(),
            )
          : const _LogoFallback(),
    );
  }
}

class _LogoFallback extends StatelessWidget {
  const _LogoFallback();

  @override
  Widget build(BuildContext context) {
    return const Center(
      child: Icon(
        Icons.live_tv_rounded,
        color: AppColors.textTertiary,
        size: 24,
      ),
    );
  }
}

class _ModalEpgVazio extends StatelessWidget {
  final bool carregando;
  const _ModalEpgVazio({required this.carregando});

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          if (carregando)
            const CircularProgressIndicator(
              color: AppColors.textTertiary,
              strokeWidth: 2,
            )
          else
            const Icon(
              Icons.event_busy_rounded,
              size: 36,
              color: AppColors.textTertiary,
            ),
          const SizedBox(height: AppSpacing.base),
          Text(
            carregando
                ? 'Carregando programacao...'
                : 'Sem programacao disponivel.',
            style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                  color: AppColors.textSecondary,
                ),
          ),
        ],
      ),
    );
  }
}

String _hhmm(DateTime dt) {
  final local = dt.toLocal();
  final h = local.hour.toString().padLeft(2, '0');
  final m = local.minute.toString().padLeft(2, '0');
  return '$h:$m';
}

/// "Hoje", "Amanha" ou "DD/MM" dependendo da distancia ate [agora].
String _rotuloData(DateTime data, DateTime agora) {
  final hoje = DateTime(agora.year, agora.month, agora.day);
  final amanha = hoje.add(const Duration(days: 1));
  final dia = DateTime(data.year, data.month, data.day);
  if (dia == hoje) return 'HOJE';
  if (dia == amanha) return 'AMANHA';
  final d = data.day.toString().padLeft(2, '0');
  final m = data.month.toString().padLeft(2, '0');
  return '$d/$m';
}
