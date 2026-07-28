import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:provider/provider.dart';
import 'package:qr_flutter/qr_flutter.dart';
import 'package:url_launcher/url_launcher.dart';

import '../services/dispositivo.dart';
import '../state/dispositivo_provider.dart';
import '../state/iptv_provider.dart';
import '../theme/app_theme.dart';
import '../utils/layout.dart';
import 'tela_importar.dart';

/// Tela de entrada quando o aparelho ainda nao tem lista para tocar — seja
/// porque nunca foi vinculado, seja porque o periodo de teste/ativacao venceu.
///
/// ⚠️ CONFORMIDADE DE LOJA (REGRA ABSOLUTA do CLAUDE.md)
/// Nesta build (padrao, `HP_CANAL=loja`) a tela e NEUTRA: mostra o
/// identificador do aparelho e manda falar com o provedor. **Nao** existe
/// preco, contagem de teste, botao de comprar, QR nem link para o site — para
/// a Apple e o Google, direcionar o usuario a uma compra fora do app e motivo
/// de reprovacao (Apple 3.1.1 / Google Play Payments).
/// A build distribuida pelo proprio site (`--dart-define=HP_CANAL=direto`)
/// acrescenta o QR e o link de ativacao.
class TelaAtivacao extends StatelessWidget {
  const TelaAtivacao({super.key});

  @override
  Widget build(BuildContext context) {
    final largo = !isPhone(context);
    return Scaffold(
      body: SafeArea(
        child: Center(
          child: SingleChildScrollView(
            padding: EdgeInsets.fromLTRB(
              AppSpacing.xl,
              AppSpacing.xl,
              AppSpacing.xl,
              AppSpacing.xl + MediaQuery.viewPaddingOf(context).bottom,
            ),
            child: ConstrainedBox(
              constraints: BoxConstraints(maxWidth: largo ? 760 : 440),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  const _Cabecalho(),
                  const SizedBox(height: AppSpacing.xxl),
                  if (largo)
                    IntrinsicHeight(
                      child: Row(
                        crossAxisAlignment: CrossAxisAlignment.stretch,
                        children: const [
                          Expanded(child: _CartaoAparelho()),
                          SizedBox(width: AppSpacing.base),
                          Expanded(child: _BlocoAtivacao()),
                        ],
                      ),
                    )
                  else ...[
                    const _CartaoAparelho(),
                    const SizedBox(height: AppSpacing.base),
                    const _BlocoAtivacao(),
                  ],
                  const SizedBox(height: AppSpacing.xl),
                  const _Acoes(),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}

/// Logo "H" + titulo. O titulo muda quando o acesso VENCEU (so na build
/// direta; na de loja a mensagem e sempre a neutra).
class _Cabecalho extends StatelessWidget {
  const _Cabecalho();

  @override
  Widget build(BuildContext context) {
    final t = Theme.of(context).textTheme;
    final expirado = context.select<DispositivoProvider, bool>((d) => d.expirado);
    final mostrarExpirado = expirado && Dispositivo.mostraAtivacaoNoApp;

    return Column(
      children: [
        // Logo oficial (quadrado vermelho com o H). Sombra suave para nao
        // parecer colada no fundo preto.
        Container(
          width: 92,
          height: 92,
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(22),
            boxShadow: [
              BoxShadow(
                color: AppColors.accent.withValues(alpha: 0.35),
                blurRadius: 28,
                spreadRadius: -6,
                offset: const Offset(0, 10),
              ),
            ],
          ),
          child: ClipRRect(
            borderRadius: BorderRadius.circular(22),
            child: Image.asset(
              'assets/heroplay-icon-192.png',
              width: 92,
              height: 92,
              fit: BoxFit.cover,
            ),
          ),
        ),
        const SizedBox(height: AppSpacing.base),
        Text('Hero Play', style: t.headlineMedium, textAlign: TextAlign.center),
        const SizedBox(height: AppSpacing.sm),
        Text(
          mostrarExpirado
              ? 'Seu acesso venceu. Ative o aparelho para continuar assistindo.'
              : 'Nenhuma lista configurada neste aparelho.',
          style: t.bodyLarge?.copyWith(color: AppColors.textSecondary),
          textAlign: TextAlign.center,
        ),
      ],
    );
  }
}

/// Identificador do aparelho — o que o provedor precisa para liberar o acesso.
class _CartaoAparelho extends StatelessWidget {
  const _CartaoAparelho();

  @override
  Widget build(BuildContext context) {
    final d = context.watch<DispositivoProvider>();
    final t = Theme.of(context).textTheme;
    return Container(
      padding: const EdgeInsets.all(AppSpacing.lg),
      decoration: BoxDecoration(
        color: AppColors.surface2,
        borderRadius: BorderRadius.circular(AppRadius.lg),
        border: Border.all(color: AppColors.outlineSubtle),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisSize: MainAxisSize.min,
        children: [
          Row(
            children: [
              const Icon(Icons.smartphone_rounded,
                  size: 16, color: AppColors.textTertiary),
              const SizedBox(width: AppSpacing.sm),
              Text('Este aparelho',
                  style: t.labelLarge?.copyWith(color: AppColors.textTertiary)),
            ],
          ),
          const SizedBox(height: AppSpacing.base),
          // "ID (MAC)": o painel e o provedor chamam de MAC — deixar os dois
          // nomes juntos evita a duvida na hora de informar.
          _LinhaId(rotulo: 'ID (MAC)', valor: d.mac),
          const SizedBox(height: AppSpacing.md),
          _LinhaId(rotulo: 'Chave', valor: d.chave),
        ],
      ),
    );
  }
}

class _LinhaId extends StatelessWidget {
  final String rotulo;
  final String valor;
  const _LinhaId({required this.rotulo, required this.valor});

  @override
  Widget build(BuildContext context) {
    final t = Theme.of(context).textTheme;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(rotulo,
            style: t.bodySmall?.copyWith(color: AppColors.textSecondary)),
        const SizedBox(height: 2),
        Row(
          children: [
            Expanded(
              child: SelectableText(
                valor.isEmpty ? '—' : valor,
                style: t.titleMedium?.copyWith(
                  fontFeatures: const [FontFeature.tabularFigures()],
                  letterSpacing: 1.4,
                ),
              ),
            ),
            IconButton(
              tooltip: 'Copiar',
              visualDensity: VisualDensity.compact,
              icon: const Icon(Icons.copy_rounded, size: 18),
              onPressed: valor.isEmpty
                  ? null
                  : () {
                      Clipboard.setData(ClipboardData(text: valor));
                      ScaffoldMessenger.of(context).showSnackBar(
                        SnackBar(content: Text('$rotulo copiado')),
                      );
                    },
            ),
          ],
        ),
      ],
    );
  }
}

/// O que fazer com o identificador. Muda por canal de distribuicao.
class _BlocoAtivacao extends StatelessWidget {
  const _BlocoAtivacao();

  @override
  Widget build(BuildContext context) {
    final t = Theme.of(context).textTheme;
    final caixa = BoxDecoration(
      color: AppColors.surface1,
      borderRadius: BorderRadius.circular(AppRadius.lg),
      border: Border.all(color: AppColors.divider),
    );

    if (!Dispositivo.mostraAtivacaoNoApp) {
      // Build de LOJA: estado neutro. Sem QR, sem link, sem preco, sem
      // contagem de teste — o app e so um player de "traga a sua lista".
      return Container(
        padding: const EdgeInsets.all(AppSpacing.lg),
        decoration: caixa,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text('Como liberar o acesso', style: t.titleSmall),
            const SizedBox(height: AppSpacing.sm),
            Text(
              'Informe o ID (MAC) e a Chave acima ao seu provedor de conteúdo. '
              'Assim que ele liberar, toque em "Verificar" — ou adicione a sua '
              'própria lista a qualquer momento.',
              style: t.bodyMedium?.copyWith(color: AppColors.textSecondary),
            ),
          ],
        ),
      );
    }

    // Build DIRETA (APK do site): QR + link, como no app de TV.
    final d = context.watch<DispositivoProvider>();
    return Container(
      padding: const EdgeInsets.all(AppSpacing.lg),
      decoration: caixa,
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Container(
            padding: const EdgeInsets.all(AppSpacing.md),
            decoration: BoxDecoration(
              color: Colors.white,
              borderRadius: BorderRadius.circular(AppRadius.base),
            ),
            child: QrImageView(
              data: d.urlAtivacao,
              size: 150,
              backgroundColor: Colors.white,
            ),
          ),
          const SizedBox(height: AppSpacing.base),
          Text(
            'Aponte a câmera do celular para o código, ou abra o endereço '
            'abaixo para ativar este aparelho.',
            style: t.bodySmall?.copyWith(color: AppColors.textSecondary),
            textAlign: TextAlign.center,
          ),
          const SizedBox(height: AppSpacing.sm),
          TextButton(
            onPressed: () => launchUrl(
              Uri.parse(d.urlAtivacao),
              mode: LaunchMode.externalApplication,
            ),
            child: const Text('Abrir página de ativação'),
          ),
        ],
      ),
    );
  }
}

class _Acoes extends StatefulWidget {
  const _Acoes();

  @override
  State<_Acoes> createState() => _AcoesState();
}

class _AcoesState extends State<_Acoes> {
  bool _verificando = false;

  Future<void> _verificar() async {
    setState(() => _verificando = true);
    final dispositivo = context.read<DispositivoProvider>();
    final iptv = context.read<IptvProvider>();
    final messenger = ScaffoldMessenger.of(context);
    final achou = await dispositivo.reconsultar();
    if (achou) {
      // O gate (app.dart) troca de tela sozinho quando a lista chega.
      await iptv.sincronizarComDispositivo();
    }
    if (!mounted) return;
    setState(() => _verificando = false);
    if (!achou) {
      messenger.showSnackBar(const SnackBar(
        content: Text('Ainda não há lista liberada para este aparelho.'),
      ));
    }
  }

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        FilledButton(
          onPressed: _verificando ? null : _verificar,
          child: _verificando
              ? const SizedBox(
                  height: 18,
                  width: 18,
                  child: CircularProgressIndicator(strokeWidth: 2),
                )
              : const Text('Verificar'),
        ),
        const SizedBox(height: AppSpacing.sm),
        OutlinedButton(
          onPressed: () => Navigator.of(context).push(
            MaterialPageRoute<void>(builder: (_) => const TelaImportar()),
          ),
          child: const Text('Adicionar minha lista'),
        ),
      ],
    );
  }
}
