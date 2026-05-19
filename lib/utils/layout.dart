import 'package:flutter/widgets.dart';

bool isTablet(BuildContext context) =>
    MediaQuery.sizeOf(context).shortestSide >= 600;

/// Larguras máximas para tablet.
const double kTabletListWidth = 720.0;
const double kTabletFormWidth = 560.0;

/// Centraliza e limita a largura de [child] no tablet.
/// Em telefone retorna [child] sem modificação.
Widget tabletBody(
  BuildContext context,
  Widget child, {
  double maxWidth = kTabletListWidth,
}) {
  if (!isTablet(context)) return child;
  return Center(
    child: ConstrainedBox(
      constraints: BoxConstraints(maxWidth: maxWidth),
      child: child,
    ),
  );
}

/// Número de colunas para grades de poster.
int posterColumns(BuildContext context) => isTablet(context) ? 4 : 3;
