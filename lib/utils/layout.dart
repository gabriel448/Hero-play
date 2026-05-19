import 'package:flutter/widgets.dart';

bool isTablet(BuildContext context) =>
    MediaQuery.sizeOf(context).shortestSide >= 600;
