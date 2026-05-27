import 'package:flutter/material.dart';

/// Chave do Navigator raiz do MaterialApp.
///
/// O mini player vive no `MaterialApp.builder`, ou seja, FORA da árvore de
/// qualquer Navigator — então `Navigator.of(context)` não acha nada a partir
/// dele. Esta chave global dá ao mini player acesso ao Navigator certo para
/// empilhar telas (ex.: o botão "expandir" reabre o canal).
final GlobalKey<NavigatorState> rootNavigatorKey = GlobalKey<NavigatorState>();