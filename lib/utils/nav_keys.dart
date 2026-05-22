import 'package:flutter/material.dart';

/// Chaves de Navigator compartilhadas.
///
/// O mini player vive no `MaterialApp.builder`, ou seja, FORA da árvore de
/// qualquer Navigator — então `Navigator.of(context)` não acha nada a partir
/// dele. Estas chaves globais dão ao mini player acesso ao Navigator certo
/// para empilhar telas (ex.: o botão "expandir" reabre o canal).

/// Navigator raiz do app (o do `MaterialApp`). Usado no mobile/tablet.
final GlobalKey<NavigatorState> rootNavigatorKey = GlobalKey<NavigatorState>();

/// Navigator da área de conteúdo do `ShellDesktop` (PC) — empilhar nele mantém
/// a sidebar visível ao redor. Usado no desktop.
final GlobalKey<NavigatorState> desktopContentNavigatorKey =
    GlobalKey<NavigatorState>();
