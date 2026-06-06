import 'package:flutter/material.dart';
import 'package:lottie/lottie.dart';

import '../theme/app_theme.dart';

/// Catalogo de avatares (placeholders) disponiveis para os perfis. Cada chave
/// casa com um arquivo em `assets/avatars/<chave>.json` (ver tool/gerar_avatares.py).
const List<String> avataresDisponiveis = [
  'ember',
  'reef',
  'citrus',
  'grape',
  'fern',
  'tide',
];

/// Chave de avatar padrao quando nada foi escolhido.
const String avatarPadrao = 'ember';

String _caminho(String chave) {
  final ch = avataresDisponiveis.contains(chave) ? chave : avatarPadrao;
  return 'assets/avatars/$ch.json';
}

/// Renderiza o avatar Lottie de um perfil recortado num **circulo perfeito**
/// (`ClipOval`) — a arte e um circulo que preenche o quadrado, entao o recorte
/// circular elimina as quinas.
///
/// O anel de selecao e circular e fica na borda real do icone (strokeAlign
/// externo), sem cobrir a arte. Os avatares sao estaticos; qualquer animacao de
/// crescimento ao selecionar e feita pelo widget pai (ex.: `AnimatedScale`).
class AvatarPerfil extends StatelessWidget {
  final String chave;
  final double tamanho;
  final bool animar;
  final bool selecionado;

  const AvatarPerfil({
    super.key,
    required this.chave,
    this.tamanho = 96,
    this.animar = false,
    this.selecionado = false,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      width: tamanho,
      height: tamanho,
      decoration: BoxDecoration(
        shape: BoxShape.circle,
        border: selecionado
            ? Border.all(
                color: AppColors.accent,
                width: 3,
                strokeAlign: BorderSide.strokeAlignOutside,
              )
            : null,
        boxShadow: selecionado
            ? [
                BoxShadow(
                  color: AppColors.accent.withValues(alpha: 0.35),
                  blurRadius: 16,
                  spreadRadius: 1,
                ),
              ]
            : null,
      ),
      child: ClipOval(
        child: Lottie.asset(
          _caminho(chave),
          width: tamanho,
          height: tamanho,
          fit: BoxFit.cover,
          animate: animar,
          repeat: animar,
        ),
      ),
    );
  }
}
