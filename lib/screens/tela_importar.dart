import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../state/iptv_provider.dart';
import '../theme/app_theme.dart';
import '../utils/layout.dart';

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

  // Tipo de formato não suportado detectado ('hls', 'epg', ou null).
  String? _formatoErro;

  @override
  void dispose() {
    _nomeController.dispose();
    _urlController.dispose();
    super.dispose();
  }

  Future<void> _importar() async {
    setState(() => _formatoErro = null);
    if (!_formKey.currentState!.validate()) return;
    final provider = context.read<IptvProvider>();
    final messenger = ScaffoldMessenger.of(context);
    final navigator = Navigator.of(context);

    await provider.importarPorUrl(
      nome: _nomeController.text.trim(),
      url: _urlController.text.trim(),
    );

    if (!mounted) return;

    if (provider.formatoNaoSuportado != null) {
      // Formato incompatível — mostra banner inline detalhado no lugar do SnackBar.
      setState(() => _formatoErro = provider.formatoNaoSuportado);
      provider.limparErro();
    } else if (provider.erro != null) {
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
        child: tabletBody(
          context,
          SingleChildScrollView(
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
                    // Limpa o banner de erro ao editar a URL.
                    onChanged: (_) {
                      if (_formatoErro != null) {
                        setState(() => _formatoErro = null);
                      }
                    },
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

                  // Banner de formato não suportado — aparece abaixo do botão
                  // quando o servidor retorna um formato incompatível (HLS ou EPG).
                  if (_formatoErro != null) ...[
                    const SizedBox(height: AppSpacing.lg),
                    _BannerFormatoInvalido(formato: _formatoErro!),
                  ],

                  const SizedBox(height: AppSpacing.xxl),
                  const _DisclaimerLegal(),
                ],
              ),
            ),
          ),
          maxWidth: kTabletFormWidth,
        ),
      ),
    );
  }
}

// ─── Banner de formato incompatível ──────────────────────────────────────────

/// Banner inline exibido quando a URL aponta para um formato não importável
/// (manifesto HLS ou EPG/XMLTV). Orienta o usuário sobre o que fazer.
///
/// Layout adapta conforme a tela:
/// - Phone: coluna única compacta — espaço reduzido, informação essencial
/// - Tablet / Desktop: duas colunas — explicação à esquerda, guia de
///   formatos à direita — aproveita o espaço horizontal disponível
class _BannerFormatoInvalido extends StatelessWidget {
  final String formato; // 'hls' | 'epg'

  const _BannerFormatoInvalido({required this.formato});

  @override
  Widget build(BuildContext context) {
    final phone = isPhone(context);

    return AnimatedSize(
      duration: AppMotion.base,
      curve: Curves.easeOutQuart,
      alignment: Alignment.topCenter,
      child: Container(
        padding: EdgeInsets.all(phone ? AppSpacing.base : AppSpacing.lg),
        decoration: BoxDecoration(
          color: AppColors.warn.withValues(alpha: 0.08),
          borderRadius: BorderRadius.circular(AppRadius.base),
          border: Border.all(
            color: AppColors.warn.withValues(alpha: 0.35),
          ),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // ── Cabeçalho ────────────────────────────────────────────────
            Row(
              children: [
                const Icon(
                  Icons.warning_amber_rounded,
                  color: AppColors.warn,
                  size: 18,
                ),
                const SizedBox(width: AppSpacing.sm),
                Text(
                  'Formato não suportado',
                  style: Theme.of(context).textTheme.titleSmall?.copyWith(
                        color: AppColors.warn,
                      ),
                ),
              ],
            ),
            const SizedBox(height: AppSpacing.md),

            // ── Corpo: coluna única (phone) ou duas colunas (tablet/desktop)
            if (phone)
              _CorpoPhone(formato: formato)
            else
              _CorpoLargo(formato: formato),
          ],
        ),
      ),
    );
  }
}

// ─── Corpo para phones ────────────────────────────────────────────────────────

class _CorpoPhone extends StatelessWidget {
  final String formato;
  const _CorpoPhone({required this.formato});

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _TextoExplicacao(formato: formato),
        const SizedBox(height: AppSpacing.base),
        _TextoComoResolver(formato: formato),
        const SizedBox(height: AppSpacing.base),
        _GuiaFormatos(),
      ],
    );
  }
}

// ─── Corpo para tablet / desktop ─────────────────────────────────────────────

class _CorpoLargo extends StatelessWidget {
  final String formato;
  const _CorpoLargo({required this.formato});

  @override
  Widget build(BuildContext context) {
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        // Coluna esquerda: explicação + o que fazer (3/5 do espaço)
        Expanded(
          flex: 3,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              _TextoExplicacao(formato: formato),
              const SizedBox(height: AppSpacing.base),
              _TextoComoResolver(formato: formato),
            ],
          ),
        ),
        const SizedBox(width: AppSpacing.xl),
        // Coluna direita: guia de formatos aceitos / não aceitos (2/5)
        Expanded(
          flex: 2,
          child: _GuiaFormatos(),
        ),
      ],
    );
  }
}

// ─── Componentes de conteúdo ──────────────────────────────────────────────────

class _TextoExplicacao extends StatelessWidget {
  final String formato;
  const _TextoExplicacao({required this.formato});

  @override
  Widget build(BuildContext context) {
    final texto = formato == 'epg'
        ? 'Esta URL aponta para um guia de programação eletrônico (EPG/XMLTV) '
            '— dados de grade de TV, não uma lista de canais.'
        : 'Esta URL aponta para um manifesto HLS — um protocolo de streaming '
            'adaptativo, não uma lista de canais IPTV.';

    return Text(
      texto,
      style: Theme.of(context).textTheme.bodySmall?.copyWith(
            color: AppColors.textSecondary,
            height: 1.55,
          ),
    );
  }
}

class _TextoComoResolver extends StatelessWidget {
  final String formato;
  const _TextoComoResolver({required this.formato});

  @override
  Widget build(BuildContext context) {
    final texto = formato == 'epg'
        ? 'No seu provedor, procure pelo link da lista de canais — '
            'normalmente chamado de "Lista M3U" ou "M3U Playlist".'
        : 'No seu provedor, procure por um link chamado "Lista M3U", '
            '"M3U Playlist" ou similar. O arquivo normalmente tem extensão '
            '.m3u ou .m3u8 e contém os canais, não um stream único.';

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          'O QUE FAZER',
          style: Theme.of(context).textTheme.labelSmall?.copyWith(
                color: AppColors.textTertiary,
                letterSpacing: 0.5,
              ),
        ),
        const SizedBox(height: AppSpacing.xs),
        Text(
          texto,
          style: Theme.of(context).textTheme.bodySmall?.copyWith(
                color: AppColors.textSecondary,
                height: 1.55,
              ),
        ),
      ],
    );
  }
}

class _GuiaFormatos extends StatelessWidget {
  const _GuiaFormatos();

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          'FORMATOS ACEITOS',
          style: Theme.of(context).textTheme.labelSmall?.copyWith(
                color: AppColors.textTertiary,
                letterSpacing: 0.5,
              ),
        ),
        const SizedBox(height: AppSpacing.xs),
        const _LinhaFormato(texto: '.m3u  —  Lista M3U padrão', aceito: true),
        const _LinhaFormato(texto: '.m3u8  —  Lista de canais IPTV', aceito: true),
        const SizedBox(height: AppSpacing.sm),
        Text(
          'NÃO ACEITOS',
          style: Theme.of(context).textTheme.labelSmall?.copyWith(
                color: AppColors.textTertiary,
                letterSpacing: 0.5,
              ),
        ),
        const SizedBox(height: AppSpacing.xs),
        const _LinhaFormato(texto: '.m3u8  —  Manifesto HLS', aceito: false),
        const _LinhaFormato(texto: '.xml  —  EPG / XMLTV', aceito: false),
      ],
    );
  }
}

class _LinhaFormato extends StatelessWidget {
  final String texto;
  final bool aceito;

  const _LinhaFormato({required this.texto, required this.aceito});

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 4),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Padding(
            padding: const EdgeInsets.only(top: 1),
            child: Icon(
              aceito ? Icons.check_rounded : Icons.close_rounded,
              size: 13,
              color: aceito ? AppColors.success : AppColors.error,
            ),
          ),
          const SizedBox(width: AppSpacing.sm),
          Expanded(
            child: Text(
              texto,
              style: Theme.of(context).textTheme.bodySmall?.copyWith(
                    color: AppColors.textSecondary,
                  ),
            ),
          ),
        ],
      ),
    );
  }
}

// ─── Widgets auxiliares ───────────────────────────────────────────────────────

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
