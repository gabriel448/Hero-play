import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../state/iptv_provider.dart';
import '../theme/app_theme.dart';

/// Importacao de listas M3U por URL.
class TelaImportar extends StatefulWidget {
  const TelaImportar({super.key});

  @override
  State<TelaImportar> createState() => _TelaImportarState();
}

class _TelaImportarState extends State<TelaImportar> {
  final _formKey = GlobalKey<FormState>();
  final _nomeController = TextEditingController();
  final _urlController = TextEditingController();

  @override
  void dispose() {
    _nomeController.dispose();
    _urlController.dispose();
    super.dispose();
  }

  Future<void> _importar() async {
    if (!_formKey.currentState!.validate()) return;
    final provider = context.read<IptvProvider>();
    final messenger = ScaffoldMessenger.of(context);
    final navigator = Navigator.of(context);

    await provider.importarPorUrl(
      nome: _nomeController.text.trim(),
      url: _urlController.text.trim(),
    );

    if (!mounted) return;

    if (provider.erro != null) {
      messenger.showSnackBar(SnackBar(content: Text(provider.erro!)));
      provider.limparErro();
    } else {
      navigator.pop();
      messenger.showSnackBar(
        const SnackBar(content: Text('Lista importada com sucesso')),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    final carregando = context.watch<IptvProvider>().carregando;

    return Scaffold(
      appBar: AppBar(title: const Text('Importar lista')),
      body: AbsorbPointer(
        absorbing: carregando,
        child: SingleChildScrollView(
          padding: const EdgeInsets.fromLTRB(
            AppSpacing.lg,
            AppSpacing.sm,
            AppSpacing.lg,
            AppSpacing.xl,
          ),
          child: Form(
            key: _formKey,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Text(
                  'Nova lista IPTV',
                  style: Theme.of(context).textTheme.headlineMedium,
                ),
                const SizedBox(height: AppSpacing.sm),
                Text(
                  'Cole a URL de uma lista M3U para importar os canais.',
                  style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                        color: AppColors.textSecondary,
                      ),
                ),
                const SizedBox(height: AppSpacing.xl),
                _Label('Nome da lista'),
                const SizedBox(height: AppSpacing.sm),
                TextFormField(
                  controller: _nomeController,
                  decoration: const InputDecoration(
                    hintText: 'Ex: Minha lista pessoal',
                  ),
                  validator: (v) =>
                      (v == null || v.trim().isEmpty) ? 'Informe um nome' : null,
                ),
                const SizedBox(height: AppSpacing.lg),
                _Label('URL'),
                const SizedBox(height: AppSpacing.sm),
                TextFormField(
                  controller: _urlController,
                  decoration: const InputDecoration(
                    hintText: 'https://exemplo.com/minha-lista.m3u',
                  ),
                  keyboardType: TextInputType.url,
                  validator: (v) {
                    if (v == null || v.trim().isEmpty) return 'Informe a URL';
                    final uri = Uri.tryParse(v.trim());
                    if (uri == null || !uri.hasScheme || !uri.hasAuthority) {
                      return 'URL invalida';
                    }
                    return null;
                  },
                ),
                const SizedBox(height: AppSpacing.xl),
                FilledButton.icon(
                  onPressed: carregando ? null : _importar,
                  icon: carregando
                      ? const SizedBox(
                          width: 14,
                          height: 14,
                          child: CircularProgressIndicator(
                            strokeWidth: 2,
                            color: AppColors.accentOn,
                          ),
                        )
                      : const Icon(Icons.download_rounded, size: 18),
                  label: Text(carregando ? 'Importando...' : 'Importar'),
                ),
                const SizedBox(height: AppSpacing.xxl),
                const _DisclaimerLegal(),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _Label extends StatelessWidget {
  final String texto;
  const _Label(this.texto);

  @override
  Widget build(BuildContext context) {
    return Text(
      texto.toUpperCase(),
      style: Theme.of(context).textTheme.labelSmall?.copyWith(
            color: AppColors.textTertiary,
          ),
    );
  }
}

class _DisclaimerLegal extends StatelessWidget {
  const _DisclaimerLegal();

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(AppSpacing.base),
      decoration: BoxDecoration(
        color: AppColors.surface1,
        borderRadius: BorderRadius.circular(AppRadius.base),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Icon(
            Icons.info_outline_rounded,
            size: 18,
            color: AppColors.textSecondary,
          ),
          const SizedBox(width: AppSpacing.md),
          Expanded(
            child: Text(
              'Este app nao distribui conteudo. Voce e responsavel pelas listas que importa.',
              style: Theme.of(context).textTheme.bodySmall,
            ),
          ),
        ],
      ),
    );
  }
}