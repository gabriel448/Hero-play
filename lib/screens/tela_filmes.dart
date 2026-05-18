import 'package:flutter/material.dart';
import 'package:marquee/marquee.dart';
import 'package:provider/provider.dart';
import '../models/canal.dart';
import '../state/iptv_provider.dart';
import '../theme/app_theme.dart';
import 'tela_player.dart';

const double _kPosterWidth = 100.0;
const double _kPosterHeight = 150.0;
const double _kPosterLabel = 28.0;
const double _kItemExtent = _kPosterWidth + AppSpacing.sm;

/// Tela estilo streaming: carrosseis horizontais por categoria de filmes.
/// Cada cartao mostra o poster (tvg-logo) e o titulo do filme.
class TelaFilmes extends StatefulWidget {
  final Map<String, List<Canal>> categorias;
  const TelaFilmes({super.key, required this.categorias});

  @override
  State<TelaFilmes> createState() => _TelaFilmesState();
}

class _TelaFilmesState extends State<TelaFilmes> {
  final _buscaController = TextEditingController();
  bool _buscando = false;
  String _busca = '';

  @override
  void dispose() {
    _buscaController.dispose();
    super.dispose();
  }

  List<Canal> _filtrar(String busca) {
    final q = busca.toLowerCase();
    return widget.categorias.values
        .expand((l) => l)
        .where(
          (c) =>
              c.nome.toLowerCase().contains(q) ||
              c.grupo.toLowerCase().contains(q),
        )
        .toList();
  }

  @override
  Widget build(BuildContext context) {
    final provider = context.watch<IptvProvider>();
    final nomes = widget.categorias.keys.toList()..sort();

    return Scaffold(
      appBar: AppBar(
        titleSpacing: 0,
        title: _buscando
            ? Padding(
                padding: const EdgeInsets.only(right: AppSpacing.sm),
                child: TextField(
                  controller: _buscaController,
                  autofocus: true,
                  decoration: const InputDecoration(
                    hintText: 'Buscar filmes',
                    border: InputBorder.none,
                    enabledBorder: InputBorder.none,
                    focusedBorder: InputBorder.none,
                    filled: false,
                    contentPadding: EdgeInsets.zero,
                  ),
                  style: Theme.of(context).textTheme.bodyLarge,
                  onChanged: (v) => setState(() => _busca = v),
                ),
              )
            : const Text('Filmes'),
        actions: [
          IconButton(
            icon: Icon(
              _buscando ? Icons.close_rounded : Icons.search_rounded,
              size: 22,
            ),
            onPressed: () {
              setState(() {
                _buscando = !_buscando;
                if (!_buscando) {
                  _buscaController.clear();
                  _busca = '';
                }
              });
            },
          ),
        ],
      ),
      body: _buscando && _busca.isNotEmpty
          ? _GradeResultados(
              canais: _filtrar(_busca),
              onTap: (c) {
                provider.registrarVisualizacao(c);
                Navigator.of(context).push(
                  MaterialPageRoute(builder: (_) => TelaPlayer(canal: c)),
                );
              },
            )
          : widget.categorias.isEmpty
              ? const _Vazio()
              : ListView.builder(
                  padding: const EdgeInsets.only(
                    top: AppSpacing.sm,
                    bottom: AppSpacing.xxl,
                  ),
                  itemCount: nomes.length,
                  itemBuilder: (_, i) {
                    final nome = nomes[i];
                    final filmes = widget.categorias[nome]!;
                    return _CarrosselCategoria(
                      nomeCategoria: nome,
                      filmes: filmes,
                      onTapFilme: (c) {
                        provider.registrarVisualizacao(c);
                        Navigator.of(context).push(
                          MaterialPageRoute(
                            builder: (_) => TelaPlayer(canal: c),
                          ),
                        );
                      },
                    );
                  },
                ),
    );
  }
}

class _Vazio extends StatelessWidget {
  const _Vazio();

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(AppSpacing.xxl),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Icon(
              Icons.movie_creation_outlined,
              size: 36,
              color: AppColors.textTertiary,
            ),
            const SizedBox(height: AppSpacing.base),
            Text(
              'Sem filmes nesta lista',
              style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                    color: AppColors.textSecondary,
                  ),
              textAlign: TextAlign.center,
            ),
          ],
        ),
      ),
    );
  }
}

class _CarrosselCategoria extends StatelessWidget {
  final String nomeCategoria;
  final List<Canal> filmes;
  final void Function(Canal) onTapFilme;

  const _CarrosselCategoria({
    required this.nomeCategoria,
    required this.filmes,
    required this.onTapFilme,
  });

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        InkWell(
          onTap: () => Navigator.of(context).push(
            MaterialPageRoute(
              builder: (_) => _TelaCategoriaFilmes(
                nomeCategoria: nomeCategoria,
                filmes: filmes,
              ),
            ),
          ),
          child: Padding(
            padding: const EdgeInsets.fromLTRB(
              AppSpacing.lg,
              AppSpacing.lg,
              AppSpacing.lg,
              AppSpacing.sm,
            ),
            child: Row(
              children: [
                Expanded(
                  child: Text(
                    nomeCategoria,
                    style: Theme.of(context).textTheme.titleSmall,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
                ),
                Text(
                  '${filmes.length}',
                  style: tabular(
                    Theme.of(context).textTheme.labelSmall?.copyWith(
                          color: AppColors.textTertiary,
                        ),
                  ),
                ),
                const SizedBox(width: AppSpacing.xs),
                const Icon(
                  Icons.chevron_right_rounded,
                  size: 16,
                  color: AppColors.textTertiary,
                ),
              ],
            ),
          ),
        ),
        SizedBox(
          height: _kPosterHeight + _kPosterLabel,
          child: ListView.builder(
            scrollDirection: Axis.horizontal,
            padding: const EdgeInsets.symmetric(horizontal: AppSpacing.lg),
            itemCount: filmes.length,
            itemExtent: _kItemExtent,
            itemBuilder: (_, i) => _Poster(
              canal: filmes[i],
              onTap: () => onTapFilme(filmes[i]),
            ),
          ),
        ),
      ],
    );
  }
}

class _Poster extends StatelessWidget {
  final Canal canal;
  final VoidCallback onTap;

  const _Poster({required this.canal, required this.onTap});

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(right: AppSpacing.sm),
      child: SizedBox(
        width: _kPosterWidth,
        child: Material(
          color: AppColors.surface1,
          borderRadius: BorderRadius.circular(AppRadius.sm),
          clipBehavior: Clip.antiAlias,
          child: InkWell(
            onTap: onTap,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                SizedBox(
                  height: _kPosterHeight,
                  child: canal.logoUrl != null && canal.logoUrl!.isNotEmpty
                      ? Image.network(
                          canal.logoUrl!,
                          fit: BoxFit.cover,
                          errorBuilder: (context, error, _) => const _PosterFallback(),
                          loadingBuilder: (_, child, progress) =>
                              progress == null ? child : const _PosterFallback(),
                        )
                      : const _PosterFallback(),
                ),
                SizedBox(
                  height: _kPosterLabel,
                  child: Padding(
                    padding: const EdgeInsets.symmetric(
                      horizontal: AppSpacing.xs,
                      vertical: AppSpacing.xs,
                    ),
                    child: Marquee(
                      text: canal.nome,
                      style: Theme.of(context).textTheme.labelSmall!,
                      scrollAxis: Axis.horizontal,
                      crossAxisAlignment: CrossAxisAlignment.center,
                      blankSpace: 32.0,
                      velocity: 30.0,
                      pauseAfterRound: const Duration(seconds: 3),
                      startAfter: const Duration(seconds: 2),
                      fadingEdgeStartFraction: 0.0,
                      fadingEdgeEndFraction: 0.12,
                    ),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _PosterFallback extends StatelessWidget {
  const _PosterFallback();

  @override
  Widget build(BuildContext context) {
    return const ColoredBox(
      color: AppColors.surface2,
      child: Center(
        child: Icon(
          Icons.movie_creation_outlined,
          size: 32,
          color: AppColors.textTertiary,
        ),
      ),
    );
  }
}

class _GradeResultados extends StatelessWidget {
  final List<Canal> canais;
  final void Function(Canal) onTap;

  const _GradeResultados({required this.canais, required this.onTap});

  @override
  Widget build(BuildContext context) {
    if (canais.isEmpty) {
      return Center(
        child: Text(
          'Nenhum filme encontrado',
          style: Theme.of(context)
              .textTheme
              .bodyMedium
              ?.copyWith(color: AppColors.textSecondary),
        ),
      );
    }

    return GridView.builder(
      padding: const EdgeInsets.all(AppSpacing.base),
      gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
        crossAxisCount: 3,
        childAspectRatio: _kPosterWidth / (_kPosterHeight + _kPosterLabel),
        crossAxisSpacing: AppSpacing.sm,
        mainAxisSpacing: AppSpacing.sm,
      ),
      itemCount: canais.length,
      itemBuilder: (_, i) => _Poster(
        canal: canais[i],
        onTap: () => onTap(canais[i]),
      ),
    );
  }
}

/// Tela de detalhe de uma categoria de filmes: grade 3 colunas + busca local.
class _TelaCategoriaFilmes extends StatefulWidget {
  final String nomeCategoria;
  final List<Canal> filmes;

  const _TelaCategoriaFilmes({
    required this.nomeCategoria,
    required this.filmes,
  });

  @override
  State<_TelaCategoriaFilmes> createState() => _TelaCategoriaFilmesState();
}

class _TelaCategoriaFilmesState extends State<_TelaCategoriaFilmes> {
  late List<Canal> _filtrados;
  final _buscaController = TextEditingController();
  String _busca = '';

  @override
  void initState() {
    super.initState();
    _filtrados = widget.filmes;
  }

  @override
  void dispose() {
    _buscaController.dispose();
    super.dispose();
  }

  void _filtrar(String q) {
    final lower = q.trim().toLowerCase();
    setState(() {
      _busca = q;
      _filtrados = lower.isEmpty
          ? widget.filmes
          : widget.filmes
              .where((c) => c.nome.toLowerCase().contains(lower))
              .toList();
    });
  }

  @override
  Widget build(BuildContext context) {
    final provider = context.watch<IptvProvider>();

    return Scaffold(
      appBar: AppBar(
        title: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              widget.nomeCategoria,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
            ),
            Text(
              '${widget.filmes.length} filmes',
              style: tabular(Theme.of(context).textTheme.bodySmall),
            ),
          ],
        ),
        bottom: PreferredSize(
          preferredSize: const Size.fromHeight(64),
          child: Padding(
            padding: const EdgeInsets.fromLTRB(
              AppSpacing.lg,
              0,
              AppSpacing.lg,
              AppSpacing.md,
            ),
            child: TextField(
              controller: _buscaController,
              decoration: InputDecoration(
                hintText: 'Buscar nesta categoria',
                prefixIcon: const Icon(Icons.search_rounded, size: 18),
                suffixIcon: _busca.isNotEmpty
                    ? IconButton(
                        icon: const Icon(Icons.clear_rounded, size: 18),
                        onPressed: () {
                          _buscaController.clear();
                          _filtrar('');
                        },
                      )
                    : null,
              ),
              onChanged: _filtrar,
            ),
          ),
        ),
      ),
      body: _filtrados.isEmpty
          ? Center(
              child: Text(
                'Nenhum filme encontrado',
                style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                      color: AppColors.textSecondary,
                    ),
              ),
            )
          : GridView.builder(
              padding: const EdgeInsets.all(AppSpacing.base),
              gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
                crossAxisCount: 3,
                childAspectRatio: _kPosterWidth / (_kPosterHeight + _kPosterLabel),
                crossAxisSpacing: AppSpacing.sm,
                mainAxisSpacing: AppSpacing.sm,
              ),
              itemCount: _filtrados.length,
              itemBuilder: (_, i) {
                final c = _filtrados[i];
                return _Poster(
                  canal: c,
                  onTap: () {
                    provider.registrarVisualizacao(c);
                    Navigator.of(context).push(
                      MaterialPageRoute(builder: (_) => TelaPlayer(canal: c)),
                    );
                  },
                );
              },
            ),
    );
  }
}