import 'dart:io';
import 'package:flutter/widgets.dart';

/// Três níveis de form factor — phone / tablet / desktop.
/// Usado como fonte única de verdade para decisões de layout.
enum FormFactor { phone, tablet, desktop }

FormFactor formFactor(BuildContext context) {
  if (Platform.isWindows || Platform.isMacOS || Platform.isLinux) {
    return FormFactor.desktop;
  }
  if (MediaQuery.sizeOf(context).shortestSide >= 600) return FormFactor.tablet;
  return FormFactor.phone;
}

bool isPhone(BuildContext context) => formFactor(context) == FormFactor.phone;

/// Retorna true para tablet E desktop — ambos usam layouts wide-screen.
/// Manter compatibilidade com todo o código existente que chama isTablet().
bool isTablet(BuildContext context) => formFactor(context) != FormFactor.phone;

bool isDesktop(BuildContext context) => formFactor(context) == FormFactor.desktop;

// ─── Constantes de largura ────────────────────────────────────────────────────

const double kTabletListWidth = 720.0;
const double kTabletFormWidth = 560.0;

/// Largura do painel de navegação lateral no shell desktop.
const double kDesktopSidebarWidth = 260.0;

/// Largura da sidebar de categorias dentro do TelaCanais.
const double kDesktopChannelSidebarWidth = 320.0;

// ─── Helpers de layout ────────────────────────────────────────────────────────

/// Centraliza e limita a largura de [child].
/// Phone → sem modificação.
/// Tablet → max [maxWidth] (default 720).
/// Desktop → max 900px (o shell já limita o painel; não queremos colunas
///           de lista absurdamente largas em monitores grandes).
Widget tabletBody(
  BuildContext context,
  Widget child, {
  double maxWidth = kTabletListWidth,
}) {
  if (isPhone(context)) return child;
  return Center(
    child: ConstrainedBox(
      constraints: BoxConstraints(
        maxWidth: isDesktop(context) ? 900.0 : maxWidth,
      ),
      child: child,
    ),
  );
}

/// Número de colunas para grades de poster.
int posterColumns(BuildContext context) {
  switch (formFactor(context)) {
    case FormFactor.desktop:
      return 6;
    case FormFactor.tablet:
      return 4;
    case FormFactor.phone:
      return 3;
  }
}

/// Largura da sidebar de categorias dentro do TelaCanais.
double channelSidebarWidth(BuildContext context) =>
    isDesktop(context) ? kDesktopChannelSidebarWidth : 260.0;

/// Largura minima para o layout de 3 colunas dos canais ao vivo
/// (sidebar de categorias + painel de canais + player embutido) caber sem
/// espremer a coluna do meio.
///
/// Decidir por largura — e nao por orientacao — conserta telas largas porem
/// "quase quadradas" (ex.: Galaxy Z Fold aberto), que contam como landscape mas
/// nao tem largura para 3 colunas legiveis. Constante exposta para calibrar no
/// aparelho real.
const double kLarguraMin3Colunas = 1100.0;

/// Decide se a tela de canais ao vivo deve usar o layout de 3 colunas.
/// Desktop sempre; tablet apenas quando ha LARGURA suficiente (independe da
/// orientacao — um "landscape" quase quadrado nao qualifica). Phone nunca.
bool usaTresColunas(BuildContext context) {
  if (isDesktop(context)) return true;
  if (!isTablet(context)) return false;
  return MediaQuery.sizeOf(context).width >= kLarguraMin3Colunas;
}
