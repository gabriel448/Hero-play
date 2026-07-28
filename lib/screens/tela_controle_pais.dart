import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../state/iptv_provider.dart';
import '../state/preferencias_provider.dart';
import '../theme/app_theme.dart';
import '../utils/layout.dart';
import '../widgets/dialogo_pin.dart';

/// Controle dos pais: PIN de 4 digitos + categorias bloqueadas, por PERFIL.
///
/// As categorias sao as REAIS da lista ativa (canais ao vivo e VOD), nao uma
/// classificacao indicativa — e o que o app consegue saber sem depender de
/// metadados que a lista nao traz.
class TelaControlePais extends StatefulWidget {
  const TelaControlePais({super.key});

  @override
  State<TelaControlePais> createState() => _TelaControlePaisState();
}

class _TelaControlePaisState extends State<TelaControlePais> {
  String _busca = '';

  Future<void> _definirPin() async {
    final prefs = context.read<PreferenciasProvider>();
    final messenger = ScaffoldMessenger.of(context);

    // Ja existe PIN: exige o ATUAL antes de trocar (senao qualquer um troca).
    if (prefs.controleParentalAtivo) {
      final ok = await pedirPin(
        context,
        titulo: 'Alterar PIN',
        mensagem: 'Digite o PIN atual.',
      );
      if (!ok || !mounted) return;
    }

    final novo = await criarPin(context);
    if (!mounted) return;
    if (novo == null) {
      messenger.showSnackBar(
        const SnackBar(content: Text('PIN não alterado (os dois não batem).')),
      );
      return;
    }
    await prefs.definirPin(novo);
    if (!mounted) return;
    messenger.showSnackBar(const SnackBar(content: Text('PIN salvo')));
  }

  Future<void> _desligar() async {
    final prefs = context.read<PreferenciasProvider>();
    final ok = await pedirPin(
      context,
      titulo: 'Desligar controle',
      mensagem: 'Digite o PIN para desligar o controle dos pais.',
    );
    if (!ok || !mounted) return;
    await prefs.definirPin(null);
  }

  Future<void> _alternarCategoria(String categoria, bool bloquear) async {
    final prefs = context.read<PreferenciasProvider>();
    final atual = [...prefs.categoriasBloqueadas];
    if (bloquear) {
      if (!atual.contains(categoria)) atual.add(categoria);
    } else {
      atual.remove(categoria);
    }
    await prefs.definirCategoriasBloqueadas(atual);
  }

  /// Categorias da lista ativa (ao vivo + VOD).
  ///
  /// As BLOQUEADAS vem primeiro (e so depois o resto, em A-Z): numa lista com
  /// centenas de categorias, rever/desfazer o que esta bloqueado seria cacar
  /// agulha no palheiro.
  List<String> _categorias(BuildContext context, List<String> bloqueadas) {
    final lista = context.watch<IptvProvider>().listaAtiva;
    if (lista == null) return const [];
    final nomes = <String>{for (final c in lista.canais) c.grupo};
    var ordenadas = nomes.toList()
      ..sort((a, b) => a.toLowerCase().compareTo(b.toLowerCase()));
    final q = _busca.trim().toLowerCase();
    if (q.isNotEmpty) {
      ordenadas = ordenadas.where((n) => n.toLowerCase().contains(q)).toList();
    }
    final bloq = {for (final b in bloqueadas) b.toLowerCase()};
    return [
      ...ordenadas.where((n) => bloq.contains(n.toLowerCase())),
      ...ordenadas.where((n) => !bloq.contains(n.toLowerCase())),
    ];
  }

  /// Quantos canais/itens cada categoria tem — ajuda a reconhecer a categoria.
  int _quantos(BuildContext context, String categoria) {
    final lista = context.read<IptvProvider>().listaAtiva;
    if (lista == null) return 0;
    var n = 0;
    for (final c in lista.canais) {
      if (c.grupo == categoria) n++;
    }
    return n;
  }

  @override
  Widget build(BuildContext context) {
    final prefs = context.watch<PreferenciasProvider>();
    final ativo = prefs.controleParentalAtivo;
    final bloqueadas = prefs.categoriasBloqueadas;
    final categorias = _categorias(context, bloqueadas);

    return Scaffold(
      appBar: AppBar(title: const Text('Controle dos pais')),
      body: tabletBody(
        context,
        Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Padding(
              padding: const EdgeInsets.all(AppSpacing.lg),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    ativo
                        ? 'Ativo neste perfil. As categorias marcadas pedem o '
                            'PIN para abrir.'
                        : 'Defina um PIN para bloquear categorias neste perfil.',
                    style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                          color: AppColors.textSecondary,
                        ),
                  ),
                  const SizedBox(height: AppSpacing.base),
                  Row(
                    children: [
                      FilledButton.icon(
                        onPressed: _definirPin,
                        icon: const Icon(Icons.password_rounded, size: 18),
                        label: Text(ativo ? 'Alterar PIN' : 'Definir PIN'),
                      ),
                      if (ativo) ...[
                        const SizedBox(width: AppSpacing.sm),
                        OutlinedButton(
                          onPressed: _desligar,
                          style: OutlinedButton.styleFrom(
                            foregroundColor: AppColors.error,
                            side: const BorderSide(color: AppColors.error),
                          ),
                          child: const Text('Desligar'),
                        ),
                      ],
                    ],
                  ),
                ],
              ),
            ),
            if (ativo) ...[
              Padding(
                padding: const EdgeInsets.symmetric(
                  horizontal: AppSpacing.lg,
                  vertical: AppSpacing.sm,
                ),
                child: TextField(
                  decoration: const InputDecoration(
                    hintText: 'Buscar categoria',
                    prefixIcon: Icon(Icons.search_rounded, size: 20),
                  ),
                  onChanged: (v) => setState(() => _busca = v),
                ),
              ),
              Expanded(
                child: categorias.isEmpty
                    ? const Center(child: Text('Nenhuma categoria na lista'))
                    : ListView.builder(
                        // Espaco extra p/ a barra de gestos do Android nao
                        // cobrir o ultimo item.
                        padding: EdgeInsets.only(
                          bottom: AppSpacing.xl +
                              MediaQuery.viewPaddingOf(context).bottom,
                        ),
                        itemCount: categorias.length,
                        itemBuilder: (_, i) {
                          final nome = categorias[i];
                          return SwitchListTile(
                            value: bloqueadas.contains(nome),
                            onChanged: (v) => _alternarCategoria(nome, v),
                            title: Text(nome),
                            subtitle: Text(
                              '${_quantos(context, nome)} itens',
                              style: Theme.of(context).textTheme.bodySmall,
                            ),
                          );
                        },
                      ),
              ),
            ] else
              const Spacer(),
          ],
        ),
      ),
    );
  }
}
