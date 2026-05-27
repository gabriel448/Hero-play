import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../models/lista_m3u.dart';
import '../state/iptv_provider.dart';
import '../theme/app_theme.dart';

/// Dialog para editar a URL do EPG de uma lista existente.
///
/// O usuario pode adicionar uma URL nova (se a lista nao tem EPG),
/// trocar a URL atual, ou limpar (botao "Remover EPG").
Future<void> dialogoEditarEpg(BuildContext context, ListaM3U lista) async {
  final provider = context.read<IptvProvider>();
  final messenger = ScaffoldMessenger.of(context);
  final controller = TextEditingController(text: lista.epgUrl ?? '');
  final formKey = GlobalKey<FormState>();

  final result = await showDialog<_AcaoEpg>(
    context: context,
    builder: (ctx) {
      return AlertDialog(
        title: Row(
          children: [
            const Icon(
              Icons.event_note_rounded,
              color: AppColors.accent,
              size: 20,
            ),
            const SizedBox(width: AppSpacing.sm),
            const Text('Editar EPG'),
          ],
        ),
        content: SizedBox(
          width: 480,
          child: Form(
            key: formKey,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(
                  'Lista: ${lista.nome}',
                  style: Theme.of(ctx).textTheme.bodySmall?.copyWith(
                        color: AppColors.textSecondary,
                      ),
                ),
                const SizedBox(height: AppSpacing.md),
                Text(
                  'URL DO EPG',
                  style: Theme.of(ctx).textTheme.labelSmall?.copyWith(
                        color: AppColors.textTertiary,
                      ),
                ),
                const SizedBox(height: AppSpacing.xs),
                TextFormField(
                  controller: controller,
                  autofocus: true,
                  decoration: const InputDecoration(
                    hintText: 'https://exemplo.com/epg.xml ou .xml.gz',
                  ),
                  keyboardType: TextInputType.url,
                  validator: (v) {
                    final t = v?.trim() ?? '';
                    if (t.isEmpty) return null;
                    final uri = Uri.tryParse(t);
                    if (uri == null || !uri.hasScheme || !uri.hasAuthority) {
                      return 'URL invalida';
                    }
                    return null;
                  },
                ),
                const SizedBox(height: AppSpacing.sm),
                Text(
                  'A grade vai baixar em segundo plano apos salvar. Aceita XMLTV e .xml.gz.',
                  style: Theme.of(ctx).textTheme.bodySmall?.copyWith(
                        color: AppColors.textTertiary,
                      ),
                ),
              ],
            ),
          ),
        ),
        actions: [
          if (lista.epgUrl != null && lista.epgUrl!.isNotEmpty)
            TextButton.icon(
              onPressed: () => Navigator.of(ctx).pop(_AcaoEpg.remover),
              icon: const Icon(Icons.delete_outline_rounded, size: 16),
              label: const Text('Remover EPG'),
              style: TextButton.styleFrom(
                foregroundColor: AppColors.error,
              ),
            ),
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(_AcaoEpg.cancelar),
            child: const Text('Cancelar'),
          ),
          FilledButton(
            onPressed: () {
              if (formKey.currentState!.validate()) {
                Navigator.of(ctx).pop(_AcaoEpg.salvar);
              }
            },
            child: const Text('Salvar'),
          ),
        ],
      );
    },
  );

  if (result == null || result == _AcaoEpg.cancelar) {
    controller.dispose();
    return;
  }

  String? novoEpg;
  if (result == _AcaoEpg.salvar) {
    novoEpg = controller.text.trim();
    if (novoEpg.isEmpty) novoEpg = null;
  } else {
    novoEpg = null; // remover
  }
  controller.dispose();

  await provider.atualizarEpgUrl(lista, novoEpg);
  if (!context.mounted) return;
  messenger.showSnackBar(
    SnackBar(
      content: Text(
        novoEpg == null
            ? 'EPG removido da lista'
            : 'EPG atualizado — baixando programacao...',
      ),
    ),
  );
}

enum _AcaoEpg { salvar, remover, cancelar }
