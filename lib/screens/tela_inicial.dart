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
import 'tela_configuracoes.dart';
import 'tela_filmes.dart';
import 'tela_gerenciar_listas.dart';
import 'tela_importar.dart';
import 'tela_series.dart';

/// Home unificada: tela de selecao entre Canais ao vivo, Filmes, Series, mais
/// um bloco secundario com Gerenciar listas e Configuracoes. Funciona em
/// phone, tablet e desktop — apenas a disposicao varia.
///
/// Quando nao existe lista ativa, mostra o empty state com CTA de importar.
class TelaInicial extends StatefulWidget {
  const TelaInicial({super.key});

  @override
  State<TelaInicial> createState() => _TelaInicialState();
}

class _TelaInicialState extends State<TelaInicial> {
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
      return const _HomeSemLista();
    }

    _atualizarCache(lista);
    return _HomeComLista(
      lista: lista,
      cacheAoVivo: _cacheAoVivo!,
      cacheFilmes: _cacheFilmes!,
      totalMovies: _totalMovies,
      totalSeries: _totalSeries,
    );
  }
}

// ─── Home com lista ativa ─────────────────────────────────────────────────────

class _HomeComLista extends StatelessWidget {
  final ListaM3U lista;
  final Map<String, List<Canal>> cacheAoVivo;
  final Map<String, List<Canal>> cacheFilmes;
  final int totalMovies;
  final int totalSeries;

  const _HomeComLista({
    required this.lista,
    required this.cacheAoVivo,
    required this.cacheFilmes,
    required this.totalMovies,
    required this.totalSeries,
  });

  @override
  Widget build(BuildContext context) {
    final tablet = isTablet(context);
    final totalLive = lista.canaisAoVivo.length;

    final cardAoVivo = _CardOpcao(
      icone: Icons.live_tv_rounded,
      titulo: 'Canais ao vivo',
      contagem: totalLive,
      unidade: 'canal',
      destaque: true,
      onTap: () => Navigator.of(context).push(
        MaterialPageRoute(
          builder: (_) => TelaCanais(categorias: cacheAoVivo),
        ),
      ),
    );
    final cardFilmes = _CardOpcao(
      icone: Icons.movie_creation_outlined,
      titulo: 'Filmes',
      contagem: totalMovies,
      unidade: 'filme',
      destaque: false,
      onTap: () => Navigator.of(context).push(
        MaterialPageRoute(
          builder: (_) => TelaFilmes(categorias: cacheFilmes),
        ),
      ),
    );
    final cardSeries = _CardOpcao(
      icone: Icons.tv_rounded,
      titulo: 'Séries',
      contagem: totalSeries,
      unidade: 'série',
      destaque: false,
      onTap: () => Navigator.of(context).push(
        MaterialPageRoute(
          builder: (_) => TelaSeries(categorias: cacheFilmes),
        ),
      ),
    );

    final cardGerenciar = _CardSecundario(
      icone: Icons.playlist_play_rounded,
      titulo: 'Gerenciar listas',
      subtitulo: 'Importar, editar e ativar listas IPTV',
      onTap: () => Navigator.of(context).push(
        MaterialPageRoute(builder: (_) => const TelaGerenciarListas()),
      ),
    );
    final cardConfig = _CardSecundario(
      icone: Icons.settings_rounded,
      titulo: 'Configurações',
      subtitulo: 'Idioma, histórico, reprodução',
      onTap: () => Navigator.of(context).push(
        MaterialPageRoute(builder: (_) => const TelaConfiguracoes()),
      ),
    );

    return Scaffold(
      backgroundColor: AppColors.surface0,
      body: SafeArea(
        child: Center(
          child: ConstrainedBox(
            constraints: BoxConstraints(
              maxWidth: tablet ? 1100 : double.infinity,
            ),
            child: SingleChildScrollView(
              padding: const EdgeInsets.symmetric(
                horizontal: AppSpacing.xl,
                vertical: AppSpacing.xl,
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                mainAxisSize: MainAxisSize.min,
                children: [
                  _Cabecalho(nomeLista: lista.nome),
                  const SizedBox(height: AppSpacing.xl),
                  // ── Bloco principal: 3 cards de conteudo ─────────────────
                  if (tablet)
                    IntrinsicHeight(
                      child: Row(
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
                  else
                    Column(
                      children: [
                        cardAoVivo,
                        const SizedBox(height: AppSpacing.base),
                        cardFilmes,
                        const SizedBox(height: AppSpacing.base),
                        cardSeries,
                      ],
                    ),
                  const SizedBox(height: AppSpacing.xl),
                  // ── Separador ────────────────────────────────────────────
                  Padding(
                    padding: const EdgeInsets.symmetric(
                      horizontal: AppSpacing.xs,
                    ),
                    child: Divider(
                      height: 1,
                      color: AppColors.divider,
                    ),
                  ),
                  const SizedBox(height: AppSpacing.lg),
                  // ── Bloco secundario: gerenciar + configuracoes ──────────
                  if (tablet)
                    IntrinsicHeight(
                      child: Row(
                        crossAxisAlignment: CrossAxisAlignment.stretch,
                        children: [
                          Expanded(child: cardGerenciar),
                          const SizedBox(width: AppSpacing.base),
                          Expanded(child: cardConfig),
                        ],
                      ),
                    )
                  else
                    Column(
                      children: [
                        cardGerenciar,
                        const SizedBox(height: AppSpacing.base),
                        cardConfig,
                      ],
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

// ─── Home sem lista (empty state) ─────────────────────────────────────────────

class _HomeSemLista extends StatelessWidget {
  const _HomeSemLista();

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.surface0,
      body: SafeArea(
        child: Center(
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 480),
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: AppSpacing.xl),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  const Spacer(),
                  Center(
                    child: Container(
                      width: 88,
                      height: 88,
                      decoration: BoxDecoration(
                        color: AppColors.surface1,
                        borderRadius: BorderRadius.circular(AppRadius.lg),
                      ),
                      child: const Icon(
                        Icons.playlist_play_rounded,
                        size: 44,
                        color: AppColors.accent,
                      ),
                    ),
                  ),
                  const SizedBox(height: AppSpacing.xl),
                  Text(
                    'Bem-vindo',
                    style: Theme.of(context).textTheme.headlineMedium,
                    textAlign: TextAlign.center,
                  ),
                  const SizedBox(height: AppSpacing.sm),
                  Text(
                    'Importe sua primeira lista IPTV para começar a assistir.',
                    style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                          color: AppColors.textSecondary,
                        ),
                    textAlign: TextAlign.center,
                  ),
                  const SizedBox(height: AppSpacing.xl),
                  FilledButton.icon(
                    onPressed: () => Navigator.of(context).push(
                      MaterialPageRoute(
                        builder: (_) => const TelaImportar(),
                      ),
                    ),
                    icon: const Icon(Icons.add_rounded),
                    label: const Text('Importar lista M3U'),
                    style: FilledButton.styleFrom(
                      padding: const EdgeInsets.symmetric(
                        vertical: AppSpacing.base,
                      ),
                    ),
                  ),
                  const SizedBox(height: AppSpacing.md),
                  OutlinedButton.icon(
                    onPressed: () => Navigator.of(context).push(
                      MaterialPageRoute(
                        builder: (_) => const TelaConfiguracoes(),
                      ),
                    ),
                    icon: const Icon(Icons.settings_rounded, size: 18),
                    label: const Text('Configurações'),
                    style: OutlinedButton.styleFrom(
                      padding: const EdgeInsets.symmetric(
                        vertical: AppSpacing.base,
                      ),
                    ),
                  ),
                  const Spacer(flex: 2),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}

// ─── Cabecalho ────────────────────────────────────────────────────────────────

class _Cabecalho extends StatelessWidget {
  final String nomeLista;
  const _Cabecalho({required this.nomeLista});

  @override
  Widget build(BuildContext context) {
    return Row(
      crossAxisAlignment: CrossAxisAlignment.center,
      children: [
        const Icon(
          Icons.live_tv_rounded,
          color: AppColors.accent,
          size: 24,
        ),
        const SizedBox(width: AppSpacing.sm),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                'LISTA ATIVA',
                style: Theme.of(context).textTheme.labelSmall?.copyWith(
                      color: AppColors.textTertiary,
                      letterSpacing: 0.6,
                    ),
              ),
              const SizedBox(height: 2),
              Text(
                nomeLista,
                style: Theme.of(context).textTheme.headlineSmall,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
              ),
            ],
          ),
        ),
      ],
    );
  }
}

// ─── Card principal (conteudo) ────────────────────────────────────────────────

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

// ─── Card secundario (gerenciar / configuracoes) ──────────────────────────────

class _CardSecundario extends StatelessWidget {
  final IconData icone;
  final String titulo;
  final String subtitulo;
  final VoidCallback onTap;

  const _CardSecundario({
    required this.icone,
    required this.titulo,
    required this.subtitulo,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return Material(
      color: AppColors.surface1,
      borderRadius: BorderRadius.circular(AppRadius.base),
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(AppRadius.base),
        child: Padding(
          padding: const EdgeInsets.all(AppSpacing.base),
          child: Row(
            children: [
              Container(
                width: 40,
                height: 40,
                decoration: BoxDecoration(
                  color: AppColors.surface2,
                  borderRadius: BorderRadius.circular(AppRadius.sm),
                ),
                child: Icon(
                  icone,
                  size: 20,
                  color: AppColors.textSecondary,
                ),
              ),
              const SizedBox(width: AppSpacing.base),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      titulo,
                      style: Theme.of(context).textTheme.titleSmall,
                    ),
                    const SizedBox(height: 2),
                    Text(
                      subtitulo,
                      style: Theme.of(context).textTheme.bodySmall?.copyWith(
                            color: AppColors.textTertiary,
                          ),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                  ],
                ),
              ),
              const Icon(
                Icons.chevron_right_rounded,
                size: 18,
                color: AppColors.textTertiary,
              ),
            ],
          ),
        ),
      ),
    );
  }
}