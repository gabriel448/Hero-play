import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../models/canal.dart';
import '../models/categoria_personalizada.dart';
import '../services/agrupador_canais.dart';
import '../state/iptv_provider.dart';
import '../state/mini_player_provider.dart';
import '../state/preferencias_provider.dart';
import '../theme/app_theme.dart';
import '../utils/layout.dart';
import '../utils/popularidade_categorias.dart';
import '../widgets/item_canal.dart';
import '../widgets/player_embutido_desktop.dart';
import '../widgets/seletor_categoria.dart';
import 'tela_categoria.dart';
import 'tela_categoria_personalizada.dart';
import 'tela_favoritos.dart';
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
  // Quando a categoria ativa é de MINHAS CATEGORIAS (favoritos, qualidade,
  // personalizada), os canais vêm daqui em vez do mapa de categorias.
  List<Canal>? _canaisOverride;
  Orientation? _orientacaoAnterior;
  late final Map<String, List<Canal>> _categoriasQualidade;

  @override
  void initState() {
    super.initState();
    // Pseudo-categorias SD/HD/FHD com canais apontando para a variante exata.
    // Calculado uma vez — categorias originais sao imutaveis.
    _categoriasQualidade = agruparPorQualidade(widget.categorias);
  }

  @override
  void dispose() {
    _buscaController.dispose();
    super.dispose();
  }

  Widget _buildBody(BuildContext context) {
    final landscape =
        MediaQuery.orientationOf(context) == Orientation.landscape;
    final busca = _buscando && _busca.isNotEmpty;

    void onSelecionada(String nome, {List<Canal>? canaisOverride}) =>
        setState(() {
          _categoriaAtiva = nome;
          _canaisOverride = canaisOverride;
        });

    // Desktop: sempre 3 colunas.
    if (isDesktop(context)) {
      return _LayoutDesktopCanais(
        categorias: widget.categorias,
        categoriasQualidade: _categoriasQualidade,
        categoriaAtiva: _categoriaAtiva,
        canaisOverride: _canaisOverride,
        onCategoriaSelecionada: onSelecionada,
        resultadosBuscaGlobal: busca ? _resultadosBusca : null,
      );
    }

    // Tablet landscape: 3 colunas com player embutido.
    if (isTablet(context) && landscape) {
      return _LayoutDesktopCanais(
        categorias: widget.categorias,
        categoriasQualidade: _categoriasQualidade,
        categoriaAtiva: _categoriaAtiva,
        canaisOverride: _canaisOverride,
        onCategoriaSelecionada: onSelecionada,
        resultadosBuscaGlobal: busca ? _resultadosBusca : null,
      );
    }

    // Tablet portrait: 2 colunas (categorias + canais).
    if (isTablet(context)) {
      return busca
          ? _ListaResultados(canais: _resultadosBusca)
          : _LayoutTabletCanais(
              categorias: widget.categorias,
              categoriasQualidade: _categoriasQualidade,
              categoriaAtiva: _categoriaAtiva,
              canaisOverride: _canaisOverride,
              onCategoriaSelecionada: onSelecionada,
            );
    }

    // Phone (qualquer orientacao): lista de categorias ou resultados.
    return busca
        ? _ListaResultados(canais: _resultadosBusca)
        : _ListaCategorias(
            categorias: widget.categorias,
            categoriasQualidade: _categoriasQualidade,
          );
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

  /// Chamado num post-frame callback quando o tablet muda de orientação.
  /// Portrait → Landscape: move o mini player para a 3ª coluna.
  /// Landscape → Portrait: move o canal da 3ª coluna para o mini player.
  void _tratarMudancaOrientacao(Orientation novaOrientacao) {
    if (!mounted) return;
    final mini = context.read<MiniPlayerProvider>();
    final provider = context.read<IptvProvider>();

    if (novaOrientacao == Orientation.landscape) {
      // Mini player ativo → transfere para a 3ª coluna (layout desktop)
      if (mini.ativo) {
        final canal = mini.canal!;
        mini.fechar();
        provider.selecionarCanalDesktop(canal);
      }
    } else {
      // Canal na 3ª coluna → transfere para mini player
      // PlayerEmbutidoDesktop já foi descartado e parou o singleton durante
      // a reconciliação — iniciarComSingleton reabre o stream.
      final canal = provider.canalSelecionadoDesktop;
      if (canal != null) {
        provider.selecionarCanalDesktop(null);
        mini.iniciarComSingleton(canal);
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    // Detecta rotação no tablet para transferir o canal entre mini player
    // e layout 3 colunas (landscape usa _LayoutDesktopCanais; portrait usa
    // _LayoutTabletCanais sem player embutido).
    if (!isDesktop(context) && isTablet(context)) {
      final orientation = MediaQuery.orientationOf(context);
      if (_orientacaoAnterior != null && _orientacaoAnterior != orientation) {
        WidgetsBinding.instance.addPostFrameCallback(
          (_) => _tratarMudancaOrientacao(orientation),
        );
      }
      _orientacaoAnterior = orientation;
    }

    return PopScope(
      canPop: !_buscando,
      onPopInvokedWithResult: (didPop, _) {
        if (!didPop) {
          setState(() {
            _buscando = false;
            _buscaController.clear();
            _busca = '';
          });
        }
      },
      child: Scaffold(
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
      body: _buildBody(context),
      ),
    );
  }
}

class _ListaCategorias extends StatelessWidget {
  final Map<String, List<Canal>> categorias;
  final Map<String, List<Canal>> categoriasQualidade;
  const _ListaCategorias({
    required this.categorias,
    required this.categoriasQualidade,
  });

  @override
  Widget build(BuildContext context) {
    final personalizadas =
        context.watch<IptvProvider>().categoriasPersonalizadas;
    final ordem = context.watch<PreferenciasProvider>().ordemCategorias;
    final nomes = _ordenarCategorias(categorias.keys, ordem);
    final todosOsCanais = categorias.values.expand((l) => l).toList()
      ..sort((a, b) => a.nome.toLowerCase().compareTo(b.nome.toLowerCase()));

    return CustomScrollView(
      slivers: [
        SliverToBoxAdapter(
          child: _SecaoMinhasCategoriasPhone(
            personalizadas: personalizadas,
            categoriasQualidade: categoriasQualidade,
          ),
        ),
        if (nomes.isNotEmpty) ...[
          SliverToBoxAdapter(
            child: Padding(
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
                      'CATEGORIAS',
                      style: Theme.of(context).textTheme.labelSmall?.copyWith(
                            color: AppColors.textTertiary,
                            letterSpacing: 0.6,
                          ),
                    ),
                  ),
                  const _BotaoOrdenarCategorias(),
                ],
              ),
            ),
          ),
          // "Todos" — sempre no topo da lista de categorias.
          SliverToBoxAdapter(
            child: _ItemCategoria(
              nome: 'Todos',
              quantidade: todosOsCanais.length,
              icone: Icons.grid_view_rounded,
              onTap: () => Navigator.of(context).push(
                MaterialPageRoute(
                  builder: (_) => TelaCategoria(
                    nomeCategoria: 'Todos',
                    canais: todosOsCanais,
                    tipo: TipoCanal.aoVivo,
                  ),
                ),
              ),
            ),
          ),
          const SliverToBoxAdapter(
            child: Padding(
              padding: EdgeInsets.symmetric(horizontal: AppSpacing.lg),
              child: Divider(height: 1),
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

// Helper compartilhado pelos 3 layouts (phone, tablet, desktop).
List<String> _ordenarCategorias(Iterable<String> nomes, OrdemCategorias ordem) {
  switch (ordem) {
    case OrdemCategorias.popularidade:
      return ordenarPorPopularidade(nomes);
    case OrdemCategorias.az:
      return nomes.toList()
        ..sort((a, b) => a.toLowerCase().compareTo(b.toLowerCase()));
  }
}

class _BotaoOrdenarCategorias extends StatelessWidget {
  const _BotaoOrdenarCategorias();

  @override
  Widget build(BuildContext context) {
    final prefs = context.watch<PreferenciasProvider>();
    final atual = prefs.ordemCategorias;
    return PopupMenuButton<OrdemCategorias>(
      tooltip: 'Ordenar por',
      position: PopupMenuPosition.under,
      onSelected: prefs.definirOrdemCategorias,
      itemBuilder: (_) => [
        for (final o in OrdemCategorias.values)
          PopupMenuItem(
            value: o,
            child: Row(
              children: [
                Icon(
                  atual == o ? Icons.check_rounded : Icons.remove,
                  size: 16,
                  color: atual == o
                      ? AppColors.accent
                      : Colors.transparent,
                ),
                const SizedBox(width: AppSpacing.sm),
                Text(o.label),
              ],
            ),
          ),
      ],
      child: Padding(
        padding: const EdgeInsets.symmetric(
          horizontal: AppSpacing.sm,
          vertical: AppSpacing.xs,
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Icon(
              Icons.sort_rounded,
              size: 16,
              color: AppColors.textSecondary,
            ),
            const SizedBox(width: 4),
            Text(
              atual.label,
              style: Theme.of(context).textTheme.labelSmall?.copyWith(
                    color: AppColors.textSecondary,
                  ),
            ),
            const SizedBox(width: 2),
            const Icon(
              Icons.arrow_drop_down_rounded,
              size: 16,
              color: AppColors.textSecondary,
            ),
          ],
        ),
      ),
    );
  }
}

class _SecaoMinhasCategoriasPhone extends StatelessWidget {
  final List<CategoriaPersonalizada> personalizadas;
  final Map<String, List<Canal>> categoriasQualidade;
  const _SecaoMinhasCategoriasPhone({
    required this.personalizadas,
    required this.categoriasQualidade,
  });

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
        _ItemCategoria(
          nome: 'Favoritos',
          quantidade: context.watch<IptvProvider>().favoritos.length,
          icone: Icons.star_rounded,
          onTap: () => Navigator.of(context).push(
            MaterialPageRoute(builder: (_) => const TelaFavoritos()),
          ),
        ),
        // Pseudo-categorias de qualidade — abrem TelaCategoria filtrada.
        ...categoriasQualidade.entries.map(
          (e) => _ItemCategoria(
            nome: e.key,
            quantidade: e.value.length,
            icone: Icons.high_quality_rounded,
            onTap: () => Navigator.of(context).push(
              MaterialPageRoute(
                builder: (_) => TelaCategoria(
                  nomeCategoria: e.key,
                  canais: e.value,
                  tipo: TipoCanal.aoVivo,
                ),
              ),
            ),
          ),
        ),
        if (personalizadas.isEmpty)
          Padding(
            padding: const EdgeInsets.fromLTRB(
              AppSpacing.lg,
              AppSpacing.sm,
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
  final Map<String, List<Canal>> categoriasQualidade;
  final String? categoriaAtiva;
  final List<Canal>? canaisOverride;
  final void Function(String nome, {List<Canal>? canaisOverride}) onCategoriaSelecionada;

  const _LayoutTabletCanais({
    required this.categorias,
    required this.categoriasQualidade,
    required this.categoriaAtiva,
    required this.onCategoriaSelecionada,
    this.canaisOverride,
  });

  @override
  State<_LayoutTabletCanais> createState() => _LayoutTabletCanaisState();
}

class _LayoutTabletCanaisState extends State<_LayoutTabletCanais> {
  final _buscaController = TextEditingController();
  late List<Canal> _canaisFiltrados;
  late final List<Canal> _todosOsCanais;

  @override
  void initState() {
    super.initState();
    _todosOsCanais = widget.categorias.values.expand((l) => l).toList()
      ..sort((a, b) => a.nome.toLowerCase().compareTo(b.nome.toLowerCase()));
    _canaisFiltrados = _canaisAtivos;
  }

  @override
  void didUpdateWidget(_LayoutTabletCanais old) {
    super.didUpdateWidget(old);
    if (old.categoriaAtiva != widget.categoriaAtiva ||
        old.canaisOverride != widget.canaisOverride) {
      _buscaController.clear();
      _canaisFiltrados = _canaisAtivos;
    }
  }

  @override
  void dispose() {
    _buscaController.dispose();
    super.dispose();
  }

  List<Canal> get _canaisAtivos {
    if (widget.canaisOverride != null) return widget.canaisOverride!;
    if (widget.categoriaAtiva == null) return [];
    return widget.categorias[widget.categoriaAtiva] ??
        widget.categoriasQualidade[widget.categoriaAtiva] ??
        [];
  }

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
    final ordem = context.watch<PreferenciasProvider>().ordemCategorias;
    final nomes = _ordenarCategorias(widget.categorias.keys, ordem);
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
              Padding(
                padding:
                    const EdgeInsets.symmetric(horizontal: AppSpacing.sm),
                child: _ItemCategoriaTablet(
                  nome: 'Favoritos',
                  quantidade:
                      context.watch<IptvProvider>().favoritos.length,
                  ativo: widget.categoriaAtiva == 'Favoritos' &&
                      widget.canaisOverride != null,
                  leadingIcon: Icons.star_rounded,
                  leadingIconColor: AppColors.accent,
                  onTap: () => widget.onCategoriaSelecionada(
                    'Favoritos',
                    canaisOverride: context.read<IptvProvider>().favoritos,
                  ),
                ),
              ),
              // Pseudo-categorias de qualidade — mostram canais na coluna.
              ...widget.categoriasQualidade.entries.map(
                (e) => Padding(
                  padding:
                      const EdgeInsets.symmetric(horizontal: AppSpacing.sm),
                  child: _ItemCategoriaTablet(
                    nome: e.key,
                    quantidade: e.value.length,
                    ativo: e.key == widget.categoriaAtiva &&
                        widget.canaisOverride == null,
                    leadingIcon: Icons.high_quality_rounded,
                    leadingIconColor: AppColors.accent,
                    onTap: () => widget.onCategoriaSelecionada(e.key),
                  ),
                ),
              ),
              if (personalizadas.isEmpty)
                Padding(
                  padding: const EdgeInsets.fromLTRB(
                    AppSpacing.base,
                    AppSpacing.sm,
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
                      ativo: widget.categoriaAtiva == cat.nome &&
                          widget.canaisOverride != null,
                      onTap: () => widget.onCategoriaSelecionada(
                        cat.nome,
                        canaisOverride: cat.canais,
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
                  AppSpacing.xs,
                  AppSpacing.xs,
                ),
                child: Row(
                  children: [
                    Expanded(
                      child: Text(
                        'CATEGORIAS',
                        style: Theme.of(context).textTheme.labelSmall?.copyWith(
                              color: AppColors.textTertiary,
                              letterSpacing: 0.6,
                            ),
                      ),
                    ),
                    const _BotaoOrdenarCategorias(),
                  ],
                ),
              ),
              // "Todos" — agrega todos os canais, sempre no topo das categorias.
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: AppSpacing.sm),
                child: _ItemCategoriaTablet(
                  nome: 'Todos',
                  quantidade: _todosOsCanais.length,
                  ativo: widget.categoriaAtiva == 'Todos' &&
                      widget.canaisOverride != null,
                  leadingIcon: Icons.grid_view_rounded,
                  onTap: () => widget.onCategoriaSelecionada(
                    'Todos',
                    canaisOverride: _todosOsCanais,
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
  final IconData? leadingIcon;
  final Color? leadingIconColor;

  const _ItemCategoriaTablet({
    required this.nome,
    required this.quantidade,
    required this.ativo,
    required this.onTap,
    this.leadingIcon,
    this.leadingIconColor,
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
              if (leadingIcon != null) ...[
                Icon(
                  leadingIcon,
                  size: 16,
                  color: leadingIconColor ?? AppColors.textSecondary,
                ),
                const SizedBox(width: AppSpacing.sm),
              ],
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
  /// Callback opcional para troca de canal — quando informado, e chamado
  /// no lugar do push padrao para TelaPlayer. Usado pelo layout desktop
  /// para abrir o canal no player embutido.
  final void Function(Canal canal)? onCanalTap;
  /// Id do canal atualmente em destaque (selecionado). Usado pelo desktop.
  final String? idCanalSelecionado;
  final ScrollController? scrollController;

  const _PainelCanaisTablet({
    required this.nomeCategoria,
    required this.canais,
    required this.canaisFiltrados,
    required this.buscaController,
    required this.onFiltrar,
    this.onCanalTap,
    this.idCanalSelecionado,
    this.scrollController,
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
                  controller: scrollController,
                  itemExtent: 64,
                  itemCount: canaisFiltrados.length,
                  padding: const EdgeInsets.only(bottom: AppSpacing.lg),
                  itemBuilder: (_, i) {
                    final c = canaisFiltrados[i];
                    return ItemCanal(
                      canal: c,
                      ehFavorito: provider.ehFavorito(c),
                      selecionado: idCanalSelecionado == c.id,
                      onTap: () {
                        provider.registrarVisualizacao(c);
                        if (onCanalTap != null) {
                          onCanalTap!(c);
                        } else {
                          Navigator.of(context).push(
                            MaterialPageRoute(
                                builder: (_) => TelaPlayer(canal: c)),
                          );
                        }
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
  /// Quando fornecido, e chamado no lugar da navegacao padrao.
  /// Permite que o layout 3-colunas encaminhe o toque para o player embutido.
  final void Function(Canal)? onCanalTap;
  final ScrollController? scrollController;

  const _ListaResultados({
    required this.canais,
    this.onCanalTap,
    this.scrollController,
  });

  @override
  Widget build(BuildContext context) {
    final provider = context.watch<IptvProvider>();
    final idSelecionado = provider.canalSelecionadoDesktop?.id;

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
      controller: scrollController,
      itemCount: canais.length,
      itemExtent: 64,
      itemBuilder: (_, i) {
        final c = canais[i];
        return ItemCanal(
          canal: c,
          ehFavorito: provider.ehFavorito(c),
          mostrarGrupo: true,
          selecionado: onCanalTap != null ? idSelecionado == c.id : false,
          onTap: () {
            provider.registrarVisualizacao(c);
            if (onCanalTap != null) {
              onCanalTap!(c);
            } else {
              Navigator.of(context).push(
                MaterialPageRoute(builder: (_) => TelaPlayer(canal: c)),
              );
            }
          },
          onToggleFavorito: () => provider.alternarFavorito(c),
        );
      },
    );
  }
}

// ─── Layout desktop: 3 colunas (categorias + canais + player embutido) ────────

class _LayoutDesktopCanais extends StatefulWidget {
  final Map<String, List<Canal>> categorias;
  final Map<String, List<Canal>> categoriasQualidade;
  final String? categoriaAtiva;
  final List<Canal>? canaisOverride;
  final void Function(String nome, {List<Canal>? canaisOverride}) onCategoriaSelecionada;
  /// Quando nao-null, a coluna de canais exibe esses resultados de busca global
  /// em vez do painel de categoria selecionada.
  final List<Canal>? resultadosBuscaGlobal;

  const _LayoutDesktopCanais({
    required this.categorias,
    required this.categoriasQualidade,
    required this.categoriaAtiva,
    required this.onCategoriaSelecionada,
    this.canaisOverride,
    this.resultadosBuscaGlobal,
  });

  @override
  State<_LayoutDesktopCanais> createState() => _LayoutDesktopCanaisState();
}

class _LayoutDesktopCanaisState extends State<_LayoutDesktopCanais> {
  final _buscaController = TextEditingController();
  final _col1Ctrl = ScrollController();
  final _col2Ctrl = ScrollController();
  late List<Canal> _canaisFiltrados;
  late final List<Canal> _todosOsCanais;
  double _col1Width = 260.0;
  double _col3Width = 420.0;

  @override
  void initState() {
    super.initState();
    _todosOsCanais = widget.categorias.values.expand((l) => l).toList()
      ..sort((a, b) => a.nome.toLowerCase().compareTo(b.nome.toLowerCase()));
    _canaisFiltrados = _canaisAtivos;
  }

  @override
  void didUpdateWidget(_LayoutDesktopCanais old) {
    super.didUpdateWidget(old);
    if (old.categoriaAtiva != widget.categoriaAtiva ||
        old.canaisOverride != widget.canaisOverride) {
      _buscaController.clear();
      _canaisFiltrados = _canaisAtivos;
    }
  }

  @override
  void dispose() {
    _buscaController.dispose();
    _col1Ctrl.dispose();
    _col2Ctrl.dispose();
    super.dispose();
  }

  List<Canal> get _canaisAtivos {
    if (widget.canaisOverride != null) return widget.canaisOverride!;
    if (widget.categoriaAtiva == null) return [];
    return widget.categorias[widget.categoriaAtiva] ??
        widget.categoriasQualidade[widget.categoriaAtiva] ??
        [];
  }

  void _filtrar(String texto) {
    final q = texto.trim().toLowerCase();
    setState(() {
      _canaisFiltrados = q.isEmpty
          ? _canaisAtivos
          : _canaisAtivos
              .where((c) => c.nome.toLowerCase().contains(q))
              .toList();
    });
  }

  void _ajustarCol1(double dx) {
    setState(() => _col1Width = (_col1Width + dx).clamp(120.0, 480.0));
  }

  void _ajustarCol3(double dx) {
    setState(() => _col3Width = (_col3Width - dx).clamp(260.0, 720.0));
  }

  /// Tap em canal no desktop: ao vivo vai para o player embutido; filme/VOD
  /// segue empilhando TelaPlayer (nao faz sentido embutir filmes).
  void _onCanalTap(Canal canal) {
    final provider = context.read<IptvProvider>();
    provider.registrarVisualizacao(canal);
    if (canal.tipo == TipoCanal.aoVivo) {
      provider.selecionarCanalDesktop(canal);
    } else {
      Navigator.of(context).push(
        MaterialPageRoute(builder: (_) => TelaPlayer(canal: canal)),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    final ordem = context.watch<PreferenciasProvider>().ordemCategorias;
    final nomes = _ordenarCategorias(widget.categorias.keys, ordem);
    final provider = context.watch<IptvProvider>();
    final personalizadas = provider.categoriasPersonalizadas;
    final idCanalSelecionado = provider.canalSelecionadoDesktop?.id;

    return Row(
      children: [
        // ── Coluna 1: sidebar de categorias ─────────────────────────────────
        SizedBox(
          width: _col1Width,
          child: ListView(
            controller: _col1Ctrl,
            padding: const EdgeInsets.only(bottom: AppSpacing.lg),
            children: [
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
              Padding(
                padding:
                    const EdgeInsets.symmetric(horizontal: AppSpacing.sm),
                child: _ItemCategoriaTablet(
                  nome: 'Favoritos',
                  quantidade: provider.favoritos.length,
                  ativo: widget.categoriaAtiva == 'Favoritos' &&
                      widget.canaisOverride != null,
                  leadingIcon: Icons.star_rounded,
                  leadingIconColor: AppColors.accent,
                  onTap: () => widget.onCategoriaSelecionada(
                    'Favoritos',
                    canaisOverride: provider.favoritos,
                  ),
                ),
              ),
              ...widget.categoriasQualidade.entries.map(
                (e) => Padding(
                  padding:
                      const EdgeInsets.symmetric(horizontal: AppSpacing.sm),
                  child: _ItemCategoriaTablet(
                    nome: e.key,
                    quantidade: e.value.length,
                    ativo: e.key == widget.categoriaAtiva &&
                        widget.canaisOverride == null,
                    leadingIcon: Icons.high_quality_rounded,
                    leadingIconColor: AppColors.accent,
                    onTap: () => widget.onCategoriaSelecionada(e.key),
                  ),
                ),
              ),
              if (personalizadas.isEmpty)
                Padding(
                  padding: const EdgeInsets.fromLTRB(
                    AppSpacing.base,
                    AppSpacing.sm,
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
                      ativo: widget.categoriaAtiva == cat.nome &&
                          widget.canaisOverride != null,
                      onTap: () => widget.onCategoriaSelecionada(
                        cat.nome,
                        canaisOverride: cat.canais,
                      ),
                    ),
                  ),
                ),
              const SizedBox(height: AppSpacing.sm),
              const Padding(
                padding: EdgeInsets.symmetric(horizontal: AppSpacing.base),
                child: Divider(height: 1, color: AppColors.divider),
              ),
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
                        'CATEGORIAS',
                        style: Theme.of(context).textTheme.labelSmall?.copyWith(
                              color: AppColors.textTertiary,
                              letterSpacing: 0.6,
                            ),
                      ),
                    ),
                    const _BotaoOrdenarCategorias(),
                  ],
                ),
              ),
              // "Todos" — agrega todos os canais, sempre no topo das categorias.
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: AppSpacing.sm),
                child: _ItemCategoriaTablet(
                  nome: 'Todos',
                  quantidade: _todosOsCanais.length,
                  ativo: widget.categoriaAtiva == 'Todos' &&
                      widget.canaisOverride != null,
                  leadingIcon: Icons.grid_view_rounded,
                  onTap: () => widget.onCategoriaSelecionada(
                    'Todos',
                    canaisOverride: _todosOsCanais,
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
        _DivisorRedimensionavel(onDrag: _ajustarCol1),

        // ── Coluna 2: painel de canais ───────────────────────────────────────
        Expanded(
          child: widget.resultadosBuscaGlobal != null
              ? _ListaResultados(
                  canais: widget.resultadosBuscaGlobal!,
                  onCanalTap: _onCanalTap,
                  scrollController: _col2Ctrl,
                )
              : widget.categoriaAtiva == null
                  ? _EmptyPainel()
                  : _PainelCanaisTablet(
                      nomeCategoria: widget.categoriaAtiva!,
                      canais: _canaisAtivos,
                      canaisFiltrados: _canaisFiltrados,
                      buscaController: _buscaController,
                      onFiltrar: _filtrar,
                      onCanalTap: _onCanalTap,
                      idCanalSelecionado: idCanalSelecionado,
                      scrollController: _col2Ctrl,
                    ),
        ),
        _DivisorRedimensionavel(onDrag: _ajustarCol3),

        // ── Coluna 3: player embutido + EPG ─────────────────────────────────
        SizedBox(
          width: _col3Width,
          child: const PlayerEmbutidoDesktop(),
        ),
      ],
    );
  }
}

// ─── Divisor arrastavel entre colunas (somente desktop) ──────────────────────

class _DivisorRedimensionavel extends StatefulWidget {
  final void Function(double dx) onDrag;
  const _DivisorRedimensionavel({required this.onDrag});

  @override
  State<_DivisorRedimensionavel> createState() =>
      _DivisorRedimensionavelState();
}

class _DivisorRedimensionavelState extends State<_DivisorRedimensionavel> {
  bool _hover = false;

  @override
  Widget build(BuildContext context) {
    // Em tablet nao ha mouse — usa divisor simples sem interacao de drag.
    if (!isDesktop(context)) {
      return const VerticalDivider(
          width: 1, thickness: 1, color: AppColors.divider);
    }
    return MouseRegion(
      cursor: SystemMouseCursors.resizeColumn,
      onEnter: (_) => setState(() => _hover = true),
      onExit: (_) => setState(() => _hover = false),
      child: GestureDetector(
        behavior: HitTestBehavior.opaque,
        onHorizontalDragUpdate: (d) => widget.onDrag(d.delta.dx),
        child: SizedBox(
          width: 8,
          child: Center(
            child: AnimatedContainer(
              duration: const Duration(milliseconds: 120),
              width: _hover ? 3 : 1,
              color: _hover
                  ? AppColors.accent.withValues(alpha: 0.65)
                  : AppColors.divider,
            ),
          ),
        ),
      ),
    );
  }
}