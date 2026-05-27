import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../models/lista_m3u.dart';
import '../state/iptv_provider.dart';
import '../theme/app_theme.dart';

/// Dialog para editar uma lista existente: nome, URL da fonte (M3U) e URL
/// do EPG. Para listas importadas por arquivo, apenas nome e EPG sao editaveis.
///
/// As alteracoes sao aplicadas em ordem (nome -> M3U -> EPG) e cada uma
/// dispara seu proprio reload quando necessario.
Future<void> dialogoEditarLista(BuildContext context, ListaM3U lista) async {
  final provider = context.read<IptvProvider>();
  final messenger = ScaffoldMessenger.of(context);
  final nomeCtrl = TextEditingController(text: lista.nome);
  final urlCtrl = TextEditingController(text: lista.fonte);
  final epgCtrl = TextEditingController(text: lista.epgUrl ?? '');
  final formKey = GlobalKey<FormState>();
  final ehUrl = lista.origem == OrigemLista.url;

  final result = await showDialog<_AcaoEditar>(
    context: context,
    builder: (ctx) {
      return AlertDialog(
        title: Row(
          children: [
            const Icon(
              Icons.edit_rounded,
              color: AppColors.accent,
              size: 20,
            ),
            const SizedBox(width: AppSpacing.sm),
            const Text('Editar lista'),
          ],
        ),
        content: SizedBox(
          width: 520,
          child: SingleChildScrollView(
            child: Form(
              key: formKey,
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisSize: MainAxisSize.min,
                children: [
                  _Label('Nome da lista'),
                  const SizedBox(height: AppSpacing.xs),
                  TextFormField(
                    controller: nomeCtrl,
                    decoration: const InputDecoration(
                      hintText: 'Ex: Minha lista pessoal',
                    ),
                    validator: (v) => (v == null || v.trim().isEmpty)
                        ? 'Informe um nome'
                        : null,
                  ),
                  const SizedBox(height: AppSpacing.lg),
                  if (ehUrl) ...[
                    _Label('URL M3U'),
                    const SizedBox(height: AppSpacing.xs),
                    TextFormField(
                      controller: urlCtrl,
                      decoration: const InputDecoration(
                        hintText: 'https://exemplo.com/minha-lista.m3u',
                      ),
                      keyboardType: TextInputType.url,
                      validator: (v) {
                        if (v == null || v.trim().isEmpty) {
                          return 'Informe a URL';
                        }
                        final uri = Uri.tryParse(v.trim());
                        if (uri == null ||
                            !uri.hasScheme ||
                            !uri.hasAuthority) {
                          return 'URL invalida';
                        }
                        return null;
                      },
                    ),
                    const SizedBox(height: AppSpacing.xs),
                    Text(
                      'Alterar a URL reimporta os canais.',
                      style: Theme.of(ctx).textTheme.bodySmall?.copyWith(
                            color: AppColors.textTertiary,
                          ),
                    ),
                    const SizedBox(height: AppSpacing.lg),
                  ] else ...[
                    _Label('Origem'),
                    const SizedBox(height: AppSpacing.xs),
                    Container(
                      padding: const EdgeInsets.symmetric(
                        horizontal: AppSpacing.md,
                        vertical: AppSpacing.sm,
                      ),
                      decoration: BoxDecoration(
                        color: AppColors.surface2,
                        borderRadius: BorderRadius.circular(AppRadius.sm),
                      ),
                      child: Row(
                        children: [
                          const Icon(
                            Icons.attach_file_rounded,
                            size: 16,
                            color: AppColors.textTertiary,
                          ),
                          const SizedBox(width: AppSpacing.sm),
                          Expanded(
                            child: Text(
                              lista.fonte,
                              style:
                                  Theme.of(ctx).textTheme.bodySmall?.copyWith(
                                        color: AppColors.textSecondary,
                                      ),
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                            ),
                          ),
                        ],
                      ),
                    ),
                    const SizedBox(height: AppSpacing.lg),
                  ],
                  _Label('URL DO EPG (opcional)'),
                  const SizedBox(height: AppSpacing.xs),
                  TextFormField(
                    controller: epgCtrl,
                    decoration: const InputDecoration(
                      hintText: 'https://exemplo.com/epg.xml ou .xml.gz',
                    ),
                    keyboardType: TextInputType.url,
                    validator: (v) {
                      final t = v?.trim() ?? '';
                      if (t.isEmpty) return null;
                      final uri = Uri.tryParse(t);
                      if (uri == null ||
                          !uri.hasScheme ||
                          !uri.hasAuthority) {
                        return 'URL invalida';
                      }
                      return null;
                    },
                  ),
                  const SizedBox(height: AppSpacing.xs),
                  Text(
                    'Grade XMLTV (.xml ou .xml.gz). Deixe vazio para remover.',
                    style: Theme.of(ctx).textTheme.bodySmall?.copyWith(
                          color: AppColors.textTertiary,
                        ),
                  ),
                ],
              ),
            ),
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(_AcaoEditar.cancelar),
            child: const Text('Cancelar'),
          ),
          FilledButton(
            onPressed: () {
              if (formKey.currentState!.validate()) {
                Navigator.of(ctx).pop(_AcaoEditar.salvar);
              }
            },
            child: const Text('Salvar'),
          ),
        ],
      );
    },
  );

  if (result != _AcaoEditar.salvar) {
    nomeCtrl.dispose();
    urlCtrl.dispose();
    epgCtrl.dispose();
    return;
  }

  final novoNome = nomeCtrl.text.trim();
  final novaUrl = urlCtrl.text.trim();
  final novoEpgRaw = epgCtrl.text.trim();
  final novoEpg = novoEpgRaw.isEmpty ? null : novoEpgRaw;
  nomeCtrl.dispose();
  urlCtrl.dispose();
  epgCtrl.dispose();

  // 1) Renomeia se mudou.
  if (novoNome != lista.nome) {
    await provider.renomearLista(lista, novoNome);
  }

  // Pega o estado mais recente da lista (com nome atualizado, mesma fonte).
  var listaAtual = provider.listas.firstWhere(
    (l) => l.id == lista.id,
    orElse: () => lista,
  );

  // 2) Troca URL M3U se mudou (so faz sentido pra origem URL).
  if (ehUrl && novaUrl != lista.fonte) {
    await provider.atualizarUrlLista(listaAtual, novaUrl);
    if (provider.erro != null) {
      messenger.showSnackBar(SnackBar(content: Text(provider.erro!)));
      provider.limparErro();
      return;
    }
    // Apos trocar a URL, o id mudou — procura pelo nome.
    listaAtual = provider.listas.firstWhere(
      (l) => l.fonte == novaUrl,
      orElse: () => listaAtual,
    );
  }

  // 3) Atualiza EPG se mudou.
  final epgAtual = listaAtual.epgUrl;
  if (novoEpg != epgAtual) {
    await provider.atualizarEpgUrl(listaAtual, novoEpg);
  }

  if (!context.mounted) return;
  messenger.showSnackBar(
    const SnackBar(content: Text('Lista atualizada')),
  );
}

enum _AcaoEditar { salvar, cancelar }

class _Label extends StatelessWidget {
  final String texto;
  const _Label(this.texto);

  @override
  Widget build(BuildContext context) {
    return Text(
      texto.toUpperCase(),
      style: TextStyle(
        fontSize: 11,
        fontWeight: FontWeight.w600,
        color: AppColors.textTertiary,
        letterSpacing: 0.5,
      ),
    );
  }
}