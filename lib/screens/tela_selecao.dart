import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../models/canal.dart';
import '../models/lista_m3u.dart';
import '../models/serie.dart';
import '../services/agrupador_canais.dart';
import '../state/iptv_provider.dart';
import '../theme/app_theme.dart';
import '../utils/layout.dart';
import 'tela_canais.dart';
import 'tela_filmes.dart';
import 'tela_series.dart';

/// Tela intermediaria apos selecionar uma lista: escolher entre Canais ao vivo
/// ou Filmes. Cada opcao leva a uma experiencia de navegacao diferente.
class TelaSelecao extends StatefulWidget {
  const TelaSelecao({super.key});

  @override
  State<TelaSelecao> createState() => _TelaSelecaoState();
}

class _TelaSelecaoState extends State<TelaSelecao> {
  Map<String, List<Canal>>? _cacheAoVivo;
  Map<String, List<Canal>>? _cacheFilmes;
  String? _idListaCacheada;
  int _totalMovies = 0;
  int _totalSeries = 0;

  void _atualizarCache(ListaM3U lista) {
    if (_idListaCacheada == lista.id) return;
    _cacheAoVivo = agruparCanaisAoVivo(lista.canaisAoVivo);
    _cacheFilmes = lista.agruparPorCategoria(TipoCanal.filme);
    _idListaCacheada = lista.id;
    final seriesNomes = <String>{};
    int movies = 0;
    for (final canais in _cacheFilmes!.values) {
      for (final c in canais) {
        final nome = Serie.nomeSerie(c.nome);
        if (nome != null) {
          seriesNomes.add(nome);
        } else {
          movies++;
        }
      }
    }
    _totalMovies = movies;
    _totalSeries = seriesNomes.length;
  }

  @override
  Widget build(BuildContext context) {
    final lista = context.watch<IptvProvider>().listaAtiva;

    if (lista == null) {
      return Scaffold(
        appBar: AppBar(title: const Text('Lista')),
        body: const Center(child: Text('Nenhuma lista selecionada')),
      );
    }

    _atualizarCache(lista);
    final cacheAoVivo = _cacheAoVivo!;
    final cacheFilmes = _cacheFilmes!;
    final totalLive = lista.canaisAoVivo.length;

    final tablet = isTablet(context);
    final cardAoVivo = _CardOpcao(
      icone: Icons.live_tv_rounded,
      titulo: 'Canais ao vivo',
      contagem: totalLive,
      unidade: 'canal',
      destaque: true,
      onTap: () => Navigator.of(context).push(
        MaterialPageRoute(builder: (_) => TelaCanais(categorias: cacheAoVivo)),
      ),
    );
    final cardFilmes = _CardOpcao(
      icone: Icons.movie_creation_outlined,
      titulo: 'Filmes',
      contagem: _totalMovies,
      unidade: 'filme',
      destaque: false,
      onTap: () => Navigator.of(context).push(
        MaterialPageRoute(builder: (_) => TelaFilmes(categorias: cacheFilmes)),
      ),
    );
    final cardSeries = _CardOpcao(
      icone: Icons.tv_rounded,
      titulo: 'Séries',
      contagem: _totalSeries,
      unidade: 'série',
      destaque: false,
      onTap: () => Navigator.of(context).push(
        MaterialPageRoute(builder: (_) => TelaSeries(categorias: cacheFilmes)),
      ),
    );

    return Scaffold(
      backgroundColor: AppColors.surface0,
      appBar: AppBar(title: Text(lista.nome)),
      body: Center(
        child: ConstrainedBox(
          constraints: BoxConstraints(maxWidth: tablet ? 1000 : double.infinity),
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: AppSpacing.xl),
            child: tablet
                ? IntrinsicHeight(
                    child: Row(
                      mainAxisSize: MainAxisSize.min,
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: [
                        Expanded(child: cardAoVivo),
                        const SizedBox(width: AppSpacing.base),
                        Expanded(child: cardFilmes),
                        const SizedBox(width: AppSpacing.base),
                        Expanded(child: cardSeries),
                      ],
                    ),
                  )
                : Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      cardAoVivo,
                      const SizedBox(height: AppSpacing.base),
                      cardFilmes,
                      const SizedBox(height: AppSpacing.base),
                      cardSeries,
                    ],
                  ),
          ),
        ),
      ),
    );
  }
}

class _CardOpcao extends StatelessWidget {
  final IconData icone;
  final String titulo;
  final int contagem;
  final String unidade;
  final bool destaque;
  final VoidCallback onTap;

  const _CardOpcao({
    required this.icone,
    required this.titulo,
    required this.contagem,
    required this.unidade,
    required this.destaque,
    required this.onTap,
  });

  String _label() {
    if (contagem >= 1000) {
      final k = (contagem / 1000).toStringAsFixed(contagem % 1000 == 0 ? 0 : 1);
      return '${k}k ${unidade}s';
    }
    return '$contagem ${contagem == 1 ? unidade : "${unidade}s"}';
  }

  @override
  Widget build(BuildContext context) {
    return Material(
      color: destaque ? AppColors.accentDim : AppColors.surface1,
      borderRadius: BorderRadius.circular(AppRadius.lg),
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(AppRadius.lg),
        child: Padding(
          padding: const EdgeInsets.all(AppSpacing.xl),
          child: Row(
            children: [
              Container(
                width: 56,
                height: 56,
                decoration: BoxDecoration(
                  color: destaque ? AppColors.surface0 : AppColors.surface2,
                  borderRadius: BorderRadius.circular(AppRadius.base),
                  border: Border.all(
                    color: destaque
                        ? AppColors.accent.withValues(alpha: 0.4)
                        : AppColors.outlineSubtle,
                  ),
                ),
                child: Icon(
                  icone,
                  size: 28,
                  color: destaque ? AppColors.accent : AppColors.textSecondary,
                ),
              ),
              const SizedBox(width: AppSpacing.base),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(titulo, style: Theme.of(context).textTheme.titleLarge),
                    const SizedBox(height: 3),
                    Text(
                      _label(),
                      style: tabular(
                        Theme.of(context).textTheme.bodySmall?.copyWith(
                              color: AppColors.textSecondary,
                            ),
                      ),
                    ),
                  ],
                ),
              ),
              Icon(
                Icons.chevron_right_rounded,
                size: 22,
                color: destaque ? AppColors.accentBright : AppColors.textTertiary,
              ),
            ],
          ),
        ),
      ),
    );
  }
}