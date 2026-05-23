import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../models/canal.dart';
import '../models/categoria_personalizada.dart';
import '../state/iptv_provider.dart';
import '../theme/app_theme.dart';
import '../utils/layout.dart';
import '../widgets/item_canal.dart';
import '../widgets/seletor_categoria.dart';
import 'tela_categoria.dart';
import 'tela_categoria_personalizada.dart';
import 'tela_player.dart';

/// Lista de categorias de canais ao vivo. Cada categoria abre [TelaCategoria]
/// com renderizacao lazy dos canais (suporta 10k+ canais por categoria).
class TelaCanais extends StatefulWidget {
  final Map<String, List<Canal>> categorias;
  const TelaCanais({super.key, required this.categorias});

  @override
  State<TelaCanais> createState() => _TelaCanaisState();
}

class _TelaCanaisState extends State<TelaCanais> {
  final _buscaController = TextEditingController();
  bool _buscando = false;
  String _busca = '';
  String? _categoriaAtiva;

  @override
  void dispose() {
    _buscaController.dispose();
    super.dispose();
  }

  List<Canal> get _resultadosBusca {
    final q = _busca.toLowerCase();
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
                    hintText: 'Buscar canal ou categoria',
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
            : const Text('Canais ao vivo'),
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
          ? _ListaResultados(canais: _resultadosBusca)
          : isTablet(context)
              ? _LayoutTabletCanais(
                  categorias: widget.categorias,
                  categoriaAtiva: _categoriaAtiva,
                  onCategoriaSelecionada: (cat) =>
                      setState(() => _categoriaAtiva = cat),
                )
              : _ListaCategorias(categorias: widget.categorias),
    );
  }
}

class _ListaCategorias extends StatelessWidget {
  final Map<String, List<Canal>> categorias;
  const _ListaCategorias({required this.categorias});

  @override
  Widget build(BuildContext context) {
    final personalizadas =
        context.watch<IptvProvider>().categoriasPersonalizadas;
    final nomes = categorias.keys.toList()..sort();

    return CustomScrollView(
      slivers: [
        SliverToBoxAdapter(
          child: _SecaoMinhasCategoriasPhone(personalizadas: personalizadas),
        ),
        if (nomes.isNotEmpty) ...[
          SliverToBoxAdapter(
            child: Padding(
              padding: const EdgeInsets.fromLTRB(
                AppSpacing.lg,
                AppSpacing.md,
                AppSpacing.lg,
                AppSpacing.xs,
              ),
              child: Text(
                'CATEGORIAS',
                style: Theme.of(context).textTheme.labelSmall?.copyWith(
                      color: AppColors.textTertiary,
                      letterSpacing: 0.6,
                    ),
              ),
            ),
          ),
          SliverList.separated(
            itemCount: nomes.length,
            itemBuilder: (_, i) {
              final nome = nomes[i];
              final canais = categorias[nome]!;
              return _ItemCategoria(
                nome: nome,
                quantidade: canais.length,
                onTap: () => Navigator.of(context).push(
                  MaterialPageRoute(
                    builder: (_) => TelaCategoria(
                      nomeCategoria: nome,
                      canais: canais,
                      tipo: TipoCanal.aoVivo,
                    ),
                  ),
                ),
              );
            },
            separatorBuilder: (_, _) => const Padding(
              padding: EdgeInsets.symmetric(horizontal: AppSpacing.lg),
              child: Divider(height: 1),
            ),
          ),
        ] else
          const SliverToBoxAdapter(child: _SemCanaisAoVivo()),
        const SliverToBoxAdapter(child: SizedBox(height: AppSpacing.lg)),
      ],
    );
  }
}

class _SecaoMinhasCategoriasPhone extends StatelessWidget {
  final List<CategoriaPersonalizada> personalizadas;
  const _SecaoMinhasCategoriasPhone({required this.personalizadas});

  Future<void> _criar(BuildContext context) async {
    final provider = context.read<IptvProvider>();
    final nome = await dialogoCriarCategoria(context);
    if (nome != null) await provider.criarCategoriaPersonalizada(nome);
  }

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(
            AppSpacing.lg,
            AppSpacing.md,
            AppSpacing.sm,
            AppSpacing.xs,
          ),
          child: Row(
            children: [
              Expanded(
                child: Text(
                  'MINHAS CATEGORIAS',
                  style: Theme.of(context).textTheme.labelSmall?.copyWith(
                        color: AppColors.textTertiary,
                        letterSpacing: 0.6,
                      ),
                ),
              ),
              IconButton(
                icon: const Icon(Icons.add_rounded, size: 20),
                tooltip: 'Nova categoria',
                onPressed: () => _criar(context),
              ),
            ],
          ),
        ),
        if (personalizadas.isEmpty)
          Padding(
            padding: const EdgeInsets.fromLTRB(
              AppSpacing.lg,
              0,
              AppSpacing.lg,
              AppSpacing.sm,
            ),
            child: Text(
              'Toque em + para criar uma categoria.',
              style: Theme.of(context).textTheme.bodySmall?.copyWith(
                    color: AppColors.textTertiary,
                  ),
            ),
          )
        else
          ...personalizadas.map((cat) => _ItemCategoria(
                nome: cat.nome,
                quantidade: cat.canais.length,
                icone: Icons.bookmark_rounded,
                onTap: () => Navigator.of(context).push(
                  MaterialPageRoute(
                    builder: (_) =>
                        TelaCategoriaPersonalizada(idCategoria: cat.id),
                  ),
                ),
              )),
      ],
    );
  }
}

class _SemCanaisAoVivo extends StatelessWidget {
  const _SemCanaisAoVivo();

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(
        AppSpacing.lg,
        AppSpacing.xl,
        AppSpacing.lg,
        AppSpacing.xl,
      ),
      child: Column(
        children: [
          const Icon(
            Icons.live_tv_rounded,
            size: 36,
            color: AppColors.textTertiary,
          ),
          const SizedBox(height: AppSpacing.base),
          Text(
            'Sem canais ao vivo nesta lista',
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

class _ItemCategoria extends StatelessWidget {
  final String nome;
  final int quantidade;
  final IconData icone;
  final VoidCallback onTap;

  const _ItemCategoria({
    required this.nome,
    required this.quantidade,
    required this.onTap,
    this.icone = Icons.live_tv_rounded,
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
              width: 36,
              height: 36,
              decoration: BoxDecoration(
                color: AppColors.accentDim,
                borderRadius: BorderRadius.circular(AppRadius.sm),
              ),
              alignment: Alignment.center,
              child: Icon(
                icone,
                size: 18,
                color: AppColors.accent,
              ),
            ),
            const SizedBox(width: AppSpacing.base),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Text(
                    nome,
                    style: Theme.of(context).textTheme.titleSmall,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
                  const SizedBox(height: 2),
                  Text(
                    '$quantidade ${quantidade == 1 ? "canal" : "canais"}',
                    style: tabular(Theme.of(context).textTheme.bodySmall),
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

// ─── Layout tablet: sidebar de categorias + painel de canais ─────────────────

class _LayoutTabletCanais extends StatefulWidget {
  final Map<String, List<Canal>> categorias;
  final String? categoriaAtiva;
  final ValueChanged<String> onCategoriaSelecionada;

  const _LayoutTabletCanais({
    required this.categorias,
    required this.categoriaAtiva,
    required this.onCategoriaSelecionada,
  });

  @override
  State<_LayoutTabletCanais> createState() => _LayoutTabletCanaisState();
}

class _LayoutTabletCanaisState extends State<_LayoutTabletCanais> {
  final _buscaController = TextEditingController();
  late List<Canal> _canaisFiltrados;

  @override
  void initState() {
    super.initState();
    _canaisFiltrados = _canaisAtivos;
  }

  @override
  void didUpdateWidget(_LayoutTabletCanais old) {
    super.didUpdateWidget(old);
    if (old.categoriaAtiva != widget.categoriaAtiva) {
      _buscaController.clear();
      _canaisFiltrados = _canaisAtivos;
    }
  }

  @override
  void dispose() {
    _buscaController.dispose();
    super.dispose();
  }

  List<Canal> get _canaisAtivos =>
      widget.categoriaAtiva != null
          ? (widget.categorias[widget.categoriaAtiva] ?? [])
          : [];

  void _filtrar(String texto) {
    final q = texto.trim().toLowerCase();
    setState(() {
      _canaisFiltrados = q.isEmpty
          ? _canaisAtivos
          : _canaisAtivos.where((c) => c.nome.toLowerCase().contains(q)).toList();
    });
  }

  @override
  Widget build(BuildContext context) {
    final nomes = widget.categorias.keys.toList()..sort();
    final personalizadas =
        context.watch<IptvProvider>().categoriasPersonalizadas;

    return Row(
      children: [
        // ── Sidebar categorias ──────────────────────────────────────────────
        SizedBox(
          width: channelSidebarWidth(context),
          child: ListView(
            padding: const EdgeInsets.only(bottom: AppSpacing.lg),
            children: [
              // ── MINHAS CATEGORIAS ────────────────────────────────────────
              Padding(
                padding: const EdgeInsets.fromLTRB(
                  AppSpacing.base,
                  AppSpacing.md,
                  AppSpacing.xs,
                  AppSpacing.xs,
                ),
                child: Row(
                  children: [
                    Expanded(
                      child: Text(
                        'MINHAS CATEGORIAS',
                        style:
                            Theme.of(context).textTheme.labelSmall?.copyWith(
                                  color: AppColors.textTertiary,
                                  letterSpacing: 0.6,
                                ),
                      ),
                    ),
                    SizedBox(
                      width: 32,
                      height: 32,
                      child: IconButton(
                        icon: const Icon(Icons.add_rounded, size: 18),
                        tooltip: 'Nova categoria',
                        padding: EdgeInsets.zero,
                        onPressed: () async {
                          final provider = context.read<IptvProvider>();
                          final nome = await dialogoCriarCategoria(context);
                          if (nome != null) {
                            await provider.criarCategoriaPersonalizada(nome);
                          }
                        },
                      ),
                    ),
                  ],
                ),
              ),
              if (personalizadas.isEmpty)
                Padding(
                  padding: const EdgeInsets.fromLTRB(
                    AppSpacing.base,
                    0,
                    AppSpacing.base,
                    AppSpacing.sm,
                  ),
                  child: Text(
                    'Toque em + para criar.',
                    style: Theme.of(context).textTheme.bodySmall?.copyWith(
                          color: AppColors.textTertiary,
                        ),
                  ),
                )
              else
                ...personalizadas.map(
                  (cat) => Padding(
                    padding: const EdgeInsets.symmetric(
                      horizontal: AppSpacing.sm,
                    ),
                    child: _ItemCategoriaTablet(
                      nome: cat.nome,
                      quantidade: cat.canais.length,
                      ativo: false,
                      onTap: () => Navigator.of(context).push(
                        MaterialPageRoute(
                          builder: (_) => TelaCategoriaPersonalizada(
                            idCategoria: cat.id,
                          ),
                        ),
                      ),
                    ),
                  ),
                ),
              const SizedBox(height: AppSpacing.sm),
              const Padding(
                padding: EdgeInsets.symmetric(horizontal: AppSpacing.base),
                child: Divider(height: 1, color: AppColors.divider),
              ),
              // ── CATEGORIAS ───────────────────────────────────────────────
              Padding(
                padding: const EdgeInsets.fromLTRB(
                  AppSpacing.base,
                  AppSpacing.md,
                  AppSpacing.base,
                  AppSpacing.xs,
                ),
                child: Text(
                  'CATEGORIAS',
                  style: Theme.of(context).textTheme.labelSmall?.copyWith(
                        color: AppColors.textTertiary,
                        letterSpacing: 0.6,
                      ),
                ),
              ),
              ...nomes.map((nome) {
                final ativo = nome == widget.categoriaAtiva;
                return Padding(
                  padding:
                      const EdgeInsets.symmetric(horizontal: AppSpacing.sm),
                  child: _ItemCategoriaTablet(
                    nome: nome,
                    quantidade: widget.categorias[nome]!.length,
                    ativo: ativo,
                    onTap: () => widget.onCategoriaSelecionada(nome),
                  ),
                );
              }),
            ],
          ),
        ),
        // Divisor vertical
        const VerticalDivider(width: 1, thickness: 1, color: AppColors.divider),
        // ── Painel de canais ───────────────────────────────────────────────
        Expanded(
          child: widget.categoriaAtiva == null
              ? _EmptyPainel()
              : _PainelCanaisTablet(
                  nomeCategoria: widget.categoriaAtiva!,
                  canais: _canaisAtivos,
                  canaisFiltrados: _canaisFiltrados,
                  buscaController: _buscaController,
                  onFiltrar: _filtrar,
                ),
        ),
      ],
    );
  }
}

class _ItemCategoriaTablet extends StatelessWidget {
  final String nome;
  final int quantidade;
  final bool ativo;
  final VoidCallback onTap;

  const _ItemCategoriaTablet({
    required this.nome,
    required this.quantidade,
    required this.ativo,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return Material(
      color: ativo ? AppColors.accentDim : Colors.transparent,
      borderRadius: BorderRadius.circular(AppRadius.sm),
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(AppRadius.sm),
        child: Padding(
          padding: const EdgeInsets.symmetric(
            horizontal: AppSpacing.md,
            vertical: AppSpacing.sm,
          ),
          child: Row(
            children: [
              if (ativo)
                Container(
                  width: 3,
                  height: 32,
                  margin: const EdgeInsets.only(right: AppSpacing.sm),
                  decoration: BoxDecoration(
                    color: AppColors.accent,
                    borderRadius: BorderRadius.circular(AppRadius.pill),
                  ),
                )
              else
                const SizedBox(width: 11),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      nome,
                      style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                            color: ativo
                                ? AppColors.textPrimary
                                : AppColors.textSecondary,
                            fontWeight:
                                ativo ? FontWeight.w600 : FontWeight.w500,
                          ),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                    Text(
                      '$quantidade canais',
                      style: tabular(
                        Theme.of(context).textTheme.bodySmall?.copyWith(
                              color: ativo
                                  ? AppColors.accentBright
                                  : AppColors.textTertiary,
                            ),
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _EmptyPainel extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    return Center(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          const Icon(
            Icons.live_tv_rounded,
            size: 48,
            color: AppColors.textTertiary,
          ),
          const SizedBox(height: AppSpacing.base),
          Text(
            'Selecione uma categoria',
            style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                  color: AppColors.textSecondary,
                ),
          ),
        ],
      ),
    );
  }
}

class _PainelCanaisTablet extends StatelessWidget {
  final String nomeCategoria;
  final List<Canal> canais;
  final List<Canal> canaisFiltrados;
  final TextEditingController buscaController;
  final ValueChanged<String> onFiltrar;

  const _PainelCanaisTablet({
    required this.nomeCategoria,
    required this.canais,
    required this.canaisFiltrados,
    required this.buscaController,
    required this.onFiltrar,
  });

  @override
  Widget build(BuildContext context) {
    final provider = context.watch<IptvProvider>();

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(
            AppSpacing.base,
            AppSpacing.md,
            AppSpacing.base,
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
              const SizedBox(width: AppSpacing.sm),
              Text(
                '${canais.length} canais',
                style: tabular(
                  Theme.of(context)
                      .textTheme
                      .bodySmall
                      ?.copyWith(color: AppColors.textTertiary),
                ),
              ),
            ],
          ),
        ),
        Padding(
          padding: const EdgeInsets.fromLTRB(
            AppSpacing.base,
            0,
            AppSpacing.base,
            AppSpacing.sm,
          ),
          child: TextField(
            controller: buscaController,
            decoration: InputDecoration(
              hintText: 'Buscar nesta categoria',
              prefixIcon: const Icon(Icons.search_rounded, size: 18),
              suffixIcon: buscaController.text.isEmpty
                  ? null
                  : IconButton(
                      icon: const Icon(Icons.clear_rounded, size: 18),
                      onPressed: () {
                        buscaController.clear();
                        onFiltrar('');
                      },
                    ),
            ),
            onChanged: onFiltrar,
          ),
        ),
        const Divider(height: 1),
        Expanded(
          child: canaisFiltrados.isEmpty
              ? Center(
                  child: Text(
                    'Nenhum canal encontrado',
                    style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                          color: AppColors.textSecondary,
                        ),
                  ),
                )
              : ListView.builder(
                  itemExtent: 64,
                  itemCount: canaisFiltrados.length,
                  padding: const EdgeInsets.only(bottom: AppSpacing.lg),
                  itemBuilder: (_, i) {
                    final c = canaisFiltrados[i];
                    return ItemCanal(
                      canal: c,
                      ehFavorito: provider.ehFavorito(c),
                      onTap: () {
                        provider.registrarVisualizacao(c);
                        Navigator.of(context).push(
                          MaterialPageRoute(
                              builder: (_) => TelaPlayer(canal: c)),
                        );
                      },
                      onToggleFavorito: () => provider.alternarFavorito(c),
                    );
                  },
                ),
        ),
      ],
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────

class _ListaResultados extends StatelessWidget {
  final List<Canal> canais;
  const _ListaResultados({required this.canais});

  @override
  Widget build(BuildContext context) {
    final provider = context.watch<IptvProvider>();

    if (canais.isEmpty) {
      return Center(
        child: Text(
          'Nenhum canal encontrado',
          style: Theme.of(context)
              .textTheme
              .bodyMedium
              ?.copyWith(color: AppColors.textSecondary),
        ),
      );
    }

    return ListView.builder(
      itemCount: canais.length,
      itemExtent: 64,
      itemBuilder: (_, i) {
        final c = canais[i];
        return ItemCanal(
          canal: c,
          ehFavorito: provider.ehFavorito(c),
          mostrarGrupo: true,
          onTap: () {
            provider.registrarVisualizacao(c);
            Navigator.of(context).push(
              MaterialPageRoute(builder: (_) => TelaPlayer(canal: c)),
            );
          },
          onToggleFavorito: () => provider.alternarFavorito(c),
        );
      },
    );
  }
}