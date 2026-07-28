import 'package:flutter/foundation.dart';

import '../services/dispositivo.dart';

/// Estado da ATIVACAO deste aparelho (MAC + Key), no lugar do antigo login por
/// e-mail. Substitui o `ContaProvider`.
///
/// O app nao tem conta: a identidade e o proprio aparelho e a "ativacao" e uma
/// flag que a nuvem devolve. Enquanto nao houver playlist vinculada, o app abre
/// no estado neutro (ver `TelaAtivacao`) — exigencia das lojas.
class DispositivoProvider extends ChangeNotifier {
  final Dispositivo dispositivo;

  DispositivoProvider(this.dispositivo);

  bool _pronto = false;
  bool _consultando = false;

  /// `true` depois que a identidade foi resolvida e a nuvem consultada uma vez.
  bool get pronto => _pronto;

  /// `true` durante uma consulta a nuvem (boot ou "Ja ativei").
  bool get consultando => _consultando;

  String get mac => dispositivo.mac;
  String get chave => dispositivo.key;
  String get status => dispositivo.status;
  bool get temLista => dispositivo.temLista;

  /// Teste/ativacao venceram: a lista do aparelho para de valer (a manual nao).
  bool get expirado => dispositivo.expirado;
  bool get emTeste => dispositivo.emTeste;
  int get diasTeste => dispositivo.diasTeste;
  String get urlAtivacao => dispositivo.urlAtivacao;

  /// Resolve a identidade e consulta a nuvem uma vez. Best-effort: qualquer
  /// falha deixa o app seguir com o snapshot local (offline-first).
  Future<void> inicializar() async {
    await dispositivo.inicializar();
    _consultando = true;
    notifyListeners();
    await dispositivo.consultar();
    _consultando = false;
    _pronto = true;
    notifyListeners();
  }

  /// Re-consulta a nuvem (botao "Ja ativei" / "Verificar ativacao").
  /// Devolve `true` se o aparelho passou a ter uma playlist vinculada.
  Future<bool> reconsultar() async {
    _consultando = true;
    notifyListeners();
    await dispositivo.consultar();
    _consultando = false;
    notifyListeners();
    return dispositivo.temLista;
  }
}
