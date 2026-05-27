import 'package:flutter/material.dart';
import '../models/canal.dart';
import 'tela_filmes.dart';

/// Tela de séries — mesmo layout de [TelaFilmes] filtrando apenas séries.
class TelaSeries extends StatelessWidget {
  final Map<String, List<Canal>> categorias;
  const TelaSeries({super.key, required this.categorias});

  @override
  Widget build(BuildContext context) {
    return TelaFilmes(categorias: categorias, tipo: TipoVod.series);
  }
}