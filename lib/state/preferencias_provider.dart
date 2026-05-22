import 'package:flutter/foundation.dart';
import '../models/idioma_app.dart';
import '../services/armazenamento.dart';

/// Preferencias do usuario — hoje so o idioma, mas e o ponto de extensao
/// natural para futuras opcoes de configuracao.
///
/// Persistidas via [Armazenamento]. As telas que dependem do idioma
/// (onboarding, configuracoes, busca TMDB) escutam este provider.
class PreferenciasProvider extends ChangeNotifier {
  final Armazenamento _armazenamento;
  IdiomaApp? _idioma;

  PreferenciasProvider(this._armazenamento)
      : _idioma = IdiomaApp.porCodigo(_armazenamento.obterIdioma());

  /// Idioma escolhido pelo usuario. `null` enquanto ele ainda nao passou
  /// pelo onboarding inicial — e o que dispara a tela de boas-vindas.
  IdiomaApp? get idioma => _idioma;

  /// `true` depois que o usuario escolheu um idioma ao menos uma vez.
  bool get idiomaDefinido => _idioma != null;

  /// Idioma a usar de fato nas consultas. Cai em portugues enquanto o
  /// usuario nao tiver escolhido nada.
  IdiomaApp get idiomaEfetivo => _idioma ?? IdiomaApp.portugues;

  Future<void> definirIdioma(IdiomaApp idioma) async {
    if (_idioma == idioma) return;
    _idioma = idioma;
    await _armazenamento.salvarIdioma(idioma.codigo);
    notifyListeners();
  }
}
