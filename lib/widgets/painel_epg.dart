import 'dart:async';

import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../models/canal.dart';
import '../services/servico_epg.dart';
import '../theme/app_theme.dart';
import '../utils/layout.dart';
import 'modal_programacao.dart';

/// Painel de programacao mostrado abaixo do player em mobile/tablet vertical.
///
/// Mostra o programa atual em destaque (vermelho) e os proximos em cinza.
/// Inclui um botao "Mostrar programacao" que abre o [ModalProgramacao] com
/// a agenda completa.
class PainelEpg extends StatefulWidget {
  final Canal canal;
  final String idLista;

  const PainelEpg({
    super.key,
    required this.canal,
    required this.idLista,
  });

  @override
  State<PainelEpg> createState() => _PainelEpgState();
}

class _PainelEpgState extends State<PainelEpg> {
  Timer? _ticker;
  bool _expandido = false;

  /// Quantidade inicial de programas mostrados (atual + proximos) antes de expandir.
  int _limiteColapsado(BuildContext context) => 3;

  @override
  void initState() {
    super.initState();
    // Reconstroi a cada 30s para mover o "atual" quando o programa muda.
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
    final carregando = epg.estaCarregando(widget.idLista);
    final agendaCompleta = epg.agenda(
      idLista: widget.idLista,
      canal: widget.canal,
    );

    final tablet = isTablet(context);
    final limite = _limiteColapsado(context);
    final total = agendaCompleta.length;
    final temMais = total > limite;
    final visiveis =
        _expandido || !temMais ? agendaCompleta : agendaCompleta.sublist(0, limite);

    // Todos os formatos usam blocos separados (como no modal/desktop).
    // Phone usa blocos compactos; tablet usa blocos largos.
    // Tap abre modal de detalhes com descricao completa.
    final itemWidgets = List.generate(visiveis.length, (i) {
      final p = visiveis[i];
      return LinhaProgramaBlocos(
        programa: p,
        atual: p.ehAtual(),
        versaoLarga: tablet,
        onTap: () => mostrarDetalhesPrograma(
          context,
          canal: widget.canal,
          programa: p,
        ),
      );
    });

    // Quando colapsado e ha itens ocultos, aplica fade-out no rodape da lista.
    Widget itemsWidget = Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: itemWidgets,
    );
    if (temMais && !_expandido) {
      itemsWidget = ShaderMask(
        shaderCallback: (bounds) => const LinearGradient(
          begin: Alignment.topCenter,
          end: Alignment.bottomCenter,
          colors: [Colors.white, Colors.white, Colors.transparent],
          stops: [0.0, 0.48, 1.0],
        ).createShader(bounds),
        blendMode: BlendMode.dstIn,
        child: itemsWidget,
      );
    }

    return Container(
      color: AppColors.surface1,
      padding: const EdgeInsets.fromLTRB(
        AppSpacing.base,
        AppSpacing.md,
        AppSpacing.base,
        AppSpacing.md,
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          // ── Cabecalho: titulo + botao "mostrar programacao" ────────────────
          Row(
            children: [
              Expanded(
                child: Text(
                  'PROGRAMACAO',
                  style: Theme.of(context).textTheme.labelSmall?.copyWith(
                        color: AppColors.textTertiary,
                        letterSpacing: 0.6,
                      ),
                ),
              ),
              if (agendaCompleta.isNotEmpty)
                TextButton.icon(
                  onPressed: () => mostrarModalProgramacao(
                    context,
                    canal: widget.canal,
                    idLista: widget.idLista,
                  ),
                  icon: const Icon(Icons.event_note_rounded, size: 16),
                  label: const Text('Mostrar programacao'),
                  style: TextButton.styleFrom(
                    foregroundColor: AppColors.textSecondary,
                    padding: const EdgeInsets.symmetric(
                      horizontal: AppSpacing.sm,
                      vertical: AppSpacing.xs,
                    ),
                    minimumSize: Size.zero,
                    tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                    textStyle: Theme.of(context).textTheme.labelSmall,
                  ),
                ),
            ],
          ),
          const SizedBox(height: AppSpacing.sm),

          // ── Corpo: linhas de programa ou estado vazio ──────────────────────
          if (agendaCompleta.isEmpty)
            _EpgVazio(
              carregando: carregando,
              temEpg: epg.temEpg(widget.idLista),
              temTvgId:
                  widget.canal.tvgId != null && widget.canal.tvgId!.isNotEmpty,
            )
          else ...[
            itemsWidget,
            // ── Acao de expandir / recolher ─────────────────────────────────
            if (temMais && !_expandido)
              _BotaoExpandir(
                rotulo: 'Mostrar mais',
                quantidade: total - limite,
                icone: Icons.expand_more_rounded,
                onTap: () => setState(() => _expandido = true),
              )
            else if (_expandido && temMais)
              _BotaoExpandir(
                rotulo: 'Mostrar menos',
                icone: Icons.expand_less_rounded,
                onTap: () => setState(() => _expandido = false),
              ),
          ],
        ],
      ),
    );
  }
}

/// Botao full-width para alternar entre vista compacta e completa da agenda.
/// Indica visualmente a direcao (chevron) e, opcionalmente, quantos itens
/// estao ocultos.
class _BotaoExpandir extends StatelessWidget {
  final String rotulo;
  final IconData icone;
  final int? quantidade;
  final VoidCallback onTap;

  const _BotaoExpandir({
    required this.rotulo,
    required this.icone,
    required this.onTap,
    this.quantidade,
  });

  @override
  Widget build(BuildContext context) {
    final tablet = isTablet(context);
    final alturaMin = tablet ? 44.0 : 38.0;

    return Padding(
      padding: const EdgeInsets.only(top: AppSpacing.sm),
      child: Material(
        color: AppColors.surface2,
        borderRadius: BorderRadius.circular(AppRadius.sm),
        child: InkWell(
          onTap: onTap,
          borderRadius: BorderRadius.circular(AppRadius.sm),
          child: Container(
            constraints: BoxConstraints(minHeight: alturaMin),
            padding: const EdgeInsets.symmetric(
              horizontal: AppSpacing.base,
              vertical: AppSpacing.sm,
            ),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Text(
                  quantidade != null && quantidade! > 0
                      ? '$rotulo  ($quantidade)'
                      : rotulo,
                  style: TextStyle(
                    fontSize: tablet ? 13.5 : 12.5,
                    fontWeight: FontWeight.w600,
                    color: AppColors.textPrimary,
                    letterSpacing: 0.2,
                  ),
                ),
                const SizedBox(width: AppSpacing.xs),
                Icon(icone, size: tablet ? 20 : 18, color: AppColors.accent),
              ],
            ),
          ),
        ),
      ),
    );
  }
}


class _EpgVazio extends StatelessWidget {
  final bool carregando;
  final bool temEpg;
  final bool temTvgId;

  const _EpgVazio({
    required this.carregando,
    required this.temEpg,
    required this.temTvgId,
  });

  @override
  Widget build(BuildContext context) {
    String mensagem;
    if (carregando && !temEpg) {
      mensagem = 'Carregando programacao...';
    } else if (!temEpg) {
      mensagem = 'Sem grade de programacao nesta lista.';
    } else if (!temTvgId) {
      mensagem = 'Este canal nao tem identificador EPG.';
    } else {
      mensagem = 'Nenhum programa proximo encontrado para este canal.';
    }
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: AppSpacing.md),
      child: Row(
        children: [
          if (carregando && !temEpg)
            const SizedBox(
              width: 14,
              height: 14,
              child: CircularProgressIndicator(
                strokeWidth: 2,
                color: AppColors.textTertiary,
              ),
            )
          else
            const Icon(
              Icons.event_busy_rounded,
              size: 16,
              color: AppColors.textTertiary,
            ),
          const SizedBox(width: AppSpacing.sm),
          Expanded(
            child: Text(
              mensagem,
              style: Theme.of(context).textTheme.bodySmall?.copyWith(
                    color: AppColors.textTertiary,
                  ),
            ),
          ),
        ],
      ),
    );
  }
}

