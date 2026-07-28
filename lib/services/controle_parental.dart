import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../state/preferencias_provider.dart';
import '../widgets/dialogo_pin.dart';

/// Porta de entrada do controle dos pais.
///
/// Regra: se a CATEGORIA do conteudo (o `group-title` da lista) esta bloqueada
/// no perfil ativo, pedimos o PIN antes de abrir. Um acerto libera aquela
/// categoria pelo resto da SESSAO — senao o usuario digitaria o PIN a cada
/// episodio. Trocar de perfil ou fechar o app zera as liberacoes.
///
/// Os pontos de checagem sao poucos de proposito (menos chance de esquecer um
/// caminho): a tela de player, a tela de detalhes e o player embutido do
/// desktop. Todo caminho — favoritos, historico, busca, categoria — passa por
/// um desses tres.
class ControleParental {
  ControleParental._();

  static final Set<String> _liberadasNaSessao = {};

  /// Chamado ao trocar de perfil: o que o adulto liberou nao vale para o
  /// proximo perfil.
  static void limparSessao() => _liberadasNaSessao.clear();

  static String _chave(String categoria) => categoria.trim().toLowerCase();

  /// `true` se este conteudo exige PIN agora (bloqueado e ainda nao liberado).
  static bool exigePin(BuildContext context, String categoria) {
    if (_liberadasNaSessao.contains(_chave(categoria))) return false;
    return context.read<PreferenciasProvider>().categoriaBloqueada(categoria);
  }

  /// Libera o acesso, pedindo o PIN se necessario. Devolve `false` quando o
  /// usuario cancela ou erra — nesse caso o chamador NAO deve abrir o conteudo.
  static Future<bool> liberar(BuildContext context, String categoria) async {
    if (!exigePin(context, categoria)) return true;
    final ok = await pedirPin(
      context,
      mensagem: 'A categoria "$categoria" está bloqueada neste perfil. '
          'Digite o PIN para continuar.',
    );
    if (ok) _liberadasNaSessao.add(_chave(categoria));
    return ok;
  }
}
