import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../models/canal.dart';
import '../state/iptv_provider.dart';
import '../theme/app_theme.dart';
import '../utils/layout.dart';
import '../widgets/item_canal.dart';
import 'tela_player.dart';

/// Tela que mostra os canais de uma categoria especifica.
///
/// ListView.builder com itemExtent fixo - critico para categorias com
/// muitos canais (listas IPTV frequentemente tem 10k+ por categoria).
class TelaCategoria extends StatefulWidget {
  final String nomeCategoria;
  final List<Canal> canais;
  final TipoCanal tipo;

  const TelaCategoria({
    super.key,
    required this.nomeCategoria,
    required this.canais,
    required this.tipo,
  });

  @override
  State<TelaCategoria> createState() => _TelaCategoriaState();
}

class _TelaCategoriaState extends State<TelaCategoria> {
  late List<Canal> _canaisFiltrados;
  final _buscaController = TextEditingController();

  @override
  void initState() {
    super.initState();
    _canaisFiltrados = widget.canais;
  }

  @override
  void dispose() {
    _buscaController.dispose();
    super.dispose();
  }

  void _filtrar(String texto) {
    final q = texto.trim().toLowerCase();
    setState(() {
      _canaisFiltrados = q.isEmpty
          ? widget.canais
          : widget.canais
              .where((c) => c.nome.toLowerCase().contains(q))
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
              '${widget.canais.length} ${widget.tipo == TipoCanal.aoVivo ? "canais" : "itens"}',
              style: tabular(
                Theme.of(context).textTheme.bodySmall,
              ),
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
                suffixIcon: _buscaController.text.isEmpty
                    ? null
                    : IconButton(
                        icon: const Icon(Icons.clear_rounded, size: 18),
                        onPressed: () {
                          _buscaController.clear();
                          _filtrar('');
                        },
                      ),
              ),
              onChanged: _filtrar,
            ),
          ),
        ),
      ),
      body: _canaisFiltrados.isEmpty
          ? Center(
              child: Text(
                'Nenhum canal encontrado',
                style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                      color: AppColors.textSecondary,
                    ),
              ),
            )
          : tabletBody(
              context,
              ListView.builder(
                itemExtent: 64,
                itemCount: _canaisFiltrados.length,
                padding: const EdgeInsets.only(bottom: AppSpacing.lg),
                itemBuilder: (_, i) {
                  final c = _canaisFiltrados[i];
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
    );
  }
}