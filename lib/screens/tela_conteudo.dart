import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../models/canal.dart';
import '../models/lista_m3u.dart';
import '../state/iptv_provider.dart';
import '../theme/app_theme.dart';
import '../widgets/item_canal.dart';
import 'tela_categoria.dart';
import 'tela_player.dart';

/// Tela principal de navegacao da lista ativa.
///
/// TabBar slim Ao Vivo / Filmes. Cada aba mostra a LISTA de categorias
/// (nao os canais). Categoria abre [TelaCategoria] que renderiza canais
/// de forma lazy (ListView.builder).
class TelaConteudo extends StatefulWidget {
  const TelaConteudo({super.key});

  @override
  State<TelaConteudo> createState() => _TelaConteudoState();
}

class _TelaConteudoState extends State<TelaConteudo>
    with SingleTickerProviderStateMixin {
  late final TabController _tabController;
  final _buscaController = TextEditingController();
  bool _buscando = false;

  Map<String, List<Canal>>? _cacheAoVivo;
  Map<String, List<Canal>>? _cacheFilmes;
  String? _idListaCacheada;

  @override
  void initState() {
    super.initState();
    _tabController = TabController(length: 2, vsync: this);
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) context.read<IptvProvider>().definirBusca('');
    });
  }

  @override
  void dispose() {
    _tabController.dispose();
    _buscaController.dispose();
    super.dispose();
  }

  void _atualizarCache(ListaM3U lista) {
    if (_idListaCacheada == lista.id) return;
    _cacheAoVivo = lista.agruparPorCategoria(TipoCanal.aoVivo);
    _cacheFilmes = lista.agruparPorCategoria(TipoCanal.filme);
    _idListaCacheada = lista.id;
  }

  @override
  Widget build(BuildContext context) {
    final provider = context.watch<IptvProvider>();
    final lista = provider.listaAtiva;

    if (lista == null) {
      return Scaffold(
        appBar: AppBar(title: const Text('Canais')),
        body: const Center(child: Text('Nenhuma lista selecionada')),
      );
    }

    _atualizarCache(lista);
    final categoriasAoVivo = _cacheAoVivo!;
    final categoriasFilmes = _cacheFilmes!;
    final totalLive = lista.canaisAoVivo.length;
    final totalFilmes = lista.filmes.length;

    return Scaffold(
      appBar: AppBar(
        titleSpacing: 0,
        title: _buscando
            ? _BarraBusca(
                controller: _buscaController,
                onChanged: provider.definirBusca,
              )
            : Text(lista.nome),
        actions: [
          IconButton(
            icon: Icon(
              _buscando ? Icons.close_rounded : Icons.search_rounded,
              size: 22,
            ),
            tooltip: _buscando ? 'Fechar busca' : 'Buscar',
            onPressed: () {
              setState(() {
                _buscando = !_buscando;
                if (!_buscando) {
                  _buscaController.clear();
                  provider.definirBusca('');
                }
              });
            },
          ),
        ],
        bottom: _buscando
            ? null
            : PreferredSize(
                preferredSize: const Size.fromHeight(44),
                child: TabBar(
                  controller: _tabController,
                  padding: const EdgeInsets.symmetric(
                    horizontal: AppSpacing.lg,
                  ),
                  isScrollable: true,
                  tabAlignment: TabAlignment.start,
                  tabs: [
                    _TabLabel(
                      titulo: 'Ao vivo',
                      contagem: totalLive,
                    ),
                    _TabLabel(
                      titulo: 'Filmes e Séries',
                      contagem: totalFilmes,
                    ),
                  ],
                ),
              ),
      ),
      body: _buscando
          ? _ListaBusca(canais: provider.canaisFiltrados)
          : TabBarView(
              controller: _tabController,
              children: [
                _ListaCategorias(
                  categorias: categoriasAoVivo,
                  tipo: TipoCanal.aoVivo,
                ),
                _ListaCategorias(
                  categorias: categoriasFilmes,
                  tipo: TipoCanal.filme,
                ),
              ],
            ),
    );
  }
}

class _TabLabel extends StatelessWidget {
  final String titulo;
  final int contagem;
  const _TabLabel({required this.titulo, required this.contagem});

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: AppSpacing.xs),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Text(titulo),
          const SizedBox(width: AppSpacing.sm),
          Container(
            padding: const EdgeInsets.symmetric(
              horizontal: AppSpacing.sm,
              vertical: 2,
            ),
            decoration: BoxDecoration(
              color: AppColors.surface2,
              borderRadius: BorderRadius.circular(AppRadius.pill),
            ),
            child: Text(
              _formatar(contagem),
              style: tabular(
                Theme.of(context).textTheme.labelSmall?.copyWith(
                      color: AppColors.textSecondary,
                    ),
              ),
            ),
          ),
        ],
      ),
    );
  }

  String _formatar(int n) {
    if (n >= 1000) {
      final mil = (n / 1000).toStringAsFixed(n % 1000 == 0 ? 0 : 1);
      return '${mil}k';
    }
    return '$n';
  }
}

class _BarraBusca extends StatelessWidget {
  final TextEditingController controller;
  final ValueChanged<String> onChanged;
  const _BarraBusca({required this.controller, required this.onChanged});

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(right: AppSpacing.sm),
      child: TextField(
        controller: controller,
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
        onChanged: onChanged,
      ),
    );
  }
}

class _ListaCategorias extends StatelessWidget {
  final Map<String, List<Canal>> categorias;
  final TipoCanal tipo;
  const _ListaCategorias({required this.categorias, required this.tipo});

  @override
  Widget build(BuildContext context) {
    if (categorias.isEmpty) {
      return Center(
        child: Padding(
          padding: const EdgeInsets.all(AppSpacing.xxl),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(
                tipo == TipoCanal.aoVivo
                    ? Icons.live_tv_rounded
                    : Icons.movie_creation_outlined,
                size: 36,
                color: AppColors.textTertiary,
              ),
              const SizedBox(height: AppSpacing.base),
              Text(
                tipo == TipoCanal.aoVivo
                    ? 'Sem canais ao vivo nesta lista'
                    : 'Sem filmes ou séries nesta lista',
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

    final nomes = categorias.keys.toList()..sort();

    return ListView.separated(
      itemCount: nomes.length,
      padding: const EdgeInsets.only(bottom: AppSpacing.lg),
      separatorBuilder: (_, _) => const Padding(
        padding: EdgeInsets.symmetric(horizontal: AppSpacing.lg),
        child: Divider(height: 1),
      ),
      itemBuilder: (_, i) {
        final nome = nomes[i];
        final canais = categorias[nome]!;
        return _ItemCategoria(
          nome: nome,
          quantidade: canais.length,
          tipo: tipo,
          onTap: () => Navigator.of(context).push(
            MaterialPageRoute(
              builder: (_) => TelaCategoria(
                nomeCategoria: nome,
                canais: canais,
                tipo: tipo,
              ),
            ),
          ),
        );
      },
    );
  }
}

class _ItemCategoria extends StatelessWidget {
  final String nome;
  final int quantidade;
  final TipoCanal tipo;
  final VoidCallback onTap;

  const _ItemCategoria({
    required this.nome,
    required this.quantidade,
    required this.tipo,
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
              width: 36,
              height: 36,
              decoration: BoxDecoration(
                color: tipo == TipoCanal.aoVivo
                    ? AppColors.accentDim
                    : AppColors.surface2,
                borderRadius: BorderRadius.circular(AppRadius.sm),
              ),
              alignment: Alignment.center,
              child: Icon(
                tipo == TipoCanal.aoVivo
                    ? Icons.live_tv_rounded
                    : Icons.movie_creation_outlined,
                size: 18,
                color: tipo == TipoCanal.aoVivo
                    ? AppColors.accent
                    : AppColors.textSecondary,
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
                    tabularLabel(quantidade, tipo),
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

  static String tabularLabel(int n, TipoCanal tipo) {
    final unidade = tipo == TipoCanal.aoVivo
        ? (n == 1 ? 'canal' : 'canais')
        : (n == 1 ? 'filme' : 'itens');
    return '$n $unidade';
  }
}

class _ListaBusca extends StatelessWidget {
  final List<Canal> canais;
  const _ListaBusca({required this.canais});

  @override
  Widget build(BuildContext context) {
    final provider = context.watch<IptvProvider>();
    if (canais.isEmpty) {
      return Center(
        child: Padding(
          padding: const EdgeInsets.all(AppSpacing.xl),
          child: Text(
            'Nenhum canal encontrado',
            style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                  color: AppColors.textSecondary,
                ),
          ),
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