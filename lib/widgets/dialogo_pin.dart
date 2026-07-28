import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:provider/provider.dart';

import '../state/preferencias_provider.dart';
import '../theme/app_theme.dart';

/// Dialogos do controle dos pais. Iguais nos 3 form factors: um AlertDialog
/// centralizado, campo de 4 digitos com teclado numerico e foco automatico —
/// funciona com toque (phone/tablet) e com teclado fisico (desktop).

/// Pede o PIN atual. Devolve `true` se o usuario acertou.
Future<bool> pedirPin(
  BuildContext context, {
  String titulo = 'Conteúdo bloqueado',
  String mensagem = 'Digite o PIN para continuar.',
}) async {
  final prefs = context.read<PreferenciasProvider>();
  if (!prefs.controleParentalAtivo) return true;

  final ok = await showDialog<bool>(
    context: context,
    barrierDismissible: false,
    builder: (dialogContext) => _DialogoPin(
      titulo: titulo,
      mensagem: mensagem,
      validar: prefs.pinConfere,
    ),
  );
  return ok ?? false;
}

/// Pede um PIN NOVO (com confirmacao). Devolve o PIN ou null se cancelado.
Future<String?> criarPin(BuildContext context) async {
  final primeiro = await showDialog<String>(
    context: context,
    builder: (_) => const _DialogoNovoPin(titulo: 'Criar PIN'),
  );
  if (primeiro == null) return null;
  if (!context.mounted) return null;
  final confirmacao = await showDialog<String>(
    context: context,
    builder: (_) => const _DialogoNovoPin(
      titulo: 'Confirme o PIN',
      mensagem: 'Digite o mesmo PIN outra vez.',
    ),
  );
  if (confirmacao == null) return null;
  return confirmacao == primeiro ? primeiro : null;
}

class _DialogoPin extends StatefulWidget {
  final String titulo;
  final String mensagem;
  final bool Function(String) validar;

  const _DialogoPin({
    required this.titulo,
    required this.mensagem,
    required this.validar,
  });

  @override
  State<_DialogoPin> createState() => _DialogoPinState();
}

class _DialogoPinState extends State<_DialogoPin> {
  final _controller = TextEditingController();
  bool _errou = false;

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  void _confirmar() {
    if (widget.validar(_controller.text)) {
      Navigator.of(context).pop(true);
    } else {
      setState(() => _errou = true);
      _controller.clear();
    }
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: Text(widget.titulo),
      content: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(widget.mensagem,
              style: Theme.of(context).textTheme.bodyMedium),
          const SizedBox(height: AppSpacing.base),
          _CampoPin(
            controller: _controller,
            onSubmit: _confirmar,
            erro: _errou ? 'PIN incorreto' : null,
          ),
        ],
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(context).pop(false),
          child: const Text('Cancelar'),
        ),
        FilledButton(onPressed: _confirmar, child: const Text('Confirmar')),
      ],
    );
  }
}

class _DialogoNovoPin extends StatefulWidget {
  final String titulo;
  final String mensagem;

  const _DialogoNovoPin({
    required this.titulo,
    this.mensagem = 'Escolha 4 dígitos. Ele será pedido para abrir o conteúdo '
        'das categorias bloqueadas.',
  });

  @override
  State<_DialogoNovoPin> createState() => _DialogoNovoPinState();
}

class _DialogoNovoPinState extends State<_DialogoNovoPin> {
  final _controller = TextEditingController();
  String? _erro;

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  void _confirmar() {
    final v = _controller.text.trim();
    if (v.length != 4) {
      setState(() => _erro = 'Use exatamente 4 dígitos');
      return;
    }
    Navigator.of(context).pop(v);
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: Text(widget.titulo),
      content: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(widget.mensagem,
              style: Theme.of(context).textTheme.bodyMedium),
          const SizedBox(height: AppSpacing.base),
          _CampoPin(
            controller: _controller,
            onSubmit: _confirmar,
            erro: _erro,
          ),
        ],
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(context).pop(),
          child: const Text('Cancelar'),
        ),
        FilledButton(onPressed: _confirmar, child: const Text('Salvar')),
      ],
    );
  }
}

class _CampoPin extends StatelessWidget {
  final TextEditingController controller;
  final VoidCallback onSubmit;
  final String? erro;

  const _CampoPin({
    required this.controller,
    required this.onSubmit,
    this.erro,
  });

  @override
  Widget build(BuildContext context) {
    return TextField(
      controller: controller,
      autofocus: true,
      obscureText: true,
      maxLength: 4,
      keyboardType: TextInputType.number,
      inputFormatters: [FilteringTextInputFormatter.digitsOnly],
      textAlign: TextAlign.center,
      style: const TextStyle(fontSize: 28, letterSpacing: 12),
      decoration: InputDecoration(
        counterText: '',
        errorText: erro,
        hintText: '••••',
      ),
      onSubmitted: (_) => onSubmit(),
    );
  }
}
