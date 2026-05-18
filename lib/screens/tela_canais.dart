import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../models/canal.dart';
import '../state/iptv_provider.dart';
import '../theme/app_theme.dart';
import '../widgets/item_canal.dart';
import 'tela_categoria.dart';
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
          : _ListaCategorias(categorias: widget.categorias),
    );
  }
}

class _ListaCategorias extends StatelessWidget {
  final Map<String, List<Canal>> categorias;
  const _ListaCategorias({required this.categorias});

  @override
  Widget build(BuildContext context) {
    if (categorias.isEmpty) {
      return Center(
        child: Padding(
          padding: const EdgeInsets.all(AppSpacing.xxl),
          child: Column(
            mainAxisSize: MainAxisSize.min,
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
    );
  }
}

class _ItemCategoria extends StatelessWidget {
  final String nome;
  final int quantidade;
  final VoidCallback onTap;

  const _ItemCategoria({
    required this.nome,
    required this.quantidade,
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
                color: AppColors.accentDim,
                borderRadius: BorderRadius.circular(AppRadius.sm),
              ),
              alignment: Alignment.center,
              child: const Icon(
                Icons.live_tv_rounded,
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