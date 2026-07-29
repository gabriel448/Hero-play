import Flutter
import UIKit
import Security

@main
@objc class AppDelegate: FlutterAppDelegate, FlutterImplicitEngineDelegate {
  /// Mesmo canal da MainActivity do Android — ver `lib/services/dispositivo.dart`.
  private let canalDispositivo = "heroplay/dispositivo"

  override func application(
    _ application: UIApplication,
    didFinishLaunchingWithOptions launchOptions: [UIApplication.LaunchOptionsKey: Any]?
  ) -> Bool {
    return super.application(application, didFinishLaunchingWithOptions: launchOptions)
  }

  /// Canais e plugins nascem AQUI (não mais em didFinishLaunching) desde o
  /// Flutter 3.35 / UISceneDelegate. O messenger vem do `applicationRegistrar`.
  func didInitializeImplicitFlutterEngine(_ engineBridge: FlutterImplicitEngineBridge) {
    GeneratedPluginRegistrant.register(with: engineBridge.pluginRegistry)
    ligarCanalDoDispositivo(engineBridge.applicationRegistrar.messenger)
  }

  private func ligarCanalDoDispositivo(_ messenger: FlutterBinaryMessenger) {
    FlutterMethodChannel(name: canalDispositivo, binaryMessenger: messenger)
      .setMethodCallHandler { chamada, resultado in
        if chamada.method == "iosId" {
          resultado(self.idDoAparelho())
        } else {
          resultado(FlutterMethodNotImplemented)
        }
      }
  }

  /**
   ID ESTAVEL do aparelho — o MAC/Key da ativacao sao derivados dele.

   No Android isto e o ANDROID_ID. No iOS o analogo seria o
   `identifierForVendor`, MAS ele tem uma pegadinha: some quando o usuario
   desinstala TODOS os apps do mesmo desenvolvedor, e ai o aparelho pediria
   ativacao de novo (foi exatamente o bug que apareceu no TV Box quando o MAC
   era sorteado). O KEYCHAIN, ao contrario, sobrevive a desinstalacao.

   Entao: guardamos no Keychain, semeado pelo identifierForVendor na primeira
   vez. Reinstalar o app devolve o MESMO id. So muda em reset de fabrica ou se
   o usuario apagar o backup/keychain — que e o comportamento esperado
   ("aparelho novo"). Nao exige permissao nem identificador de publicidade.
   */
  private func idDoAparelho() -> String {
    let conta = "heroplay.dispositivo.id"
    if let existente = lerDoKeychain(conta) { return existente }
    let novo = UIDevice.current.identifierForVendor?.uuidString ?? UUID().uuidString
    gravarNoKeychain(conta, novo)
    return novo
  }

  private func lerDoKeychain(_ conta: String) -> String? {
    let busca: [String: Any] = [
      kSecClass as String: kSecClassGenericPassword,
      kSecAttrAccount as String: conta,
      kSecReturnData as String: true,
      kSecMatchLimit as String: kSecMatchLimitOne,
    ]
    var item: CFTypeRef?
    guard SecItemCopyMatching(busca as CFDictionary, &item) == errSecSuccess,
          let dados = item as? Data,
          let texto = String(data: dados, encoding: .utf8),
          !texto.isEmpty
    else { return nil }
    return texto
  }

  private func gravarNoKeychain(_ conta: String, _ valor: String) {
    let chave: [String: Any] = [
      kSecClass as String: kSecClassGenericPassword,
      kSecAttrAccount as String: conta,
    ]
    SecItemDelete(chave as CFDictionary)
    var novo = chave
    novo[kSecValueData as String] = Data(valor.utf8)
    // AfterFirstUnlock: legivel no boot mesmo antes de o usuario desbloquear —
    // o app pode consultar a ativacao ao ser aberto por um atalho/automacao.
    // ThisDeviceOnly: NAO vai junto no backup/restore pra outro aparelho, senao
    // dois iPhones nasceriam com a mesma identidade.
    novo[kSecAttrAccessible as String] = kSecAttrAccessibleAfterFirstUnlockThisDeviceOnly
    SecItemAdd(novo as CFDictionary, nil)
  }
}
