import 'dart:convert';
import 'dart:math';

import 'package:device_info_plus/device_info_plus.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:http/http.dart' as http;

import 'armazenamento.dart';

/// Identidade do aparelho (MAC + Key) + consulta de ativacao/lista na nuvem.
///
/// PORTE de `tv-app/device.js`. O contrato com a Edge Function `ativacao` e o
/// mesmo do app de TV — o painel de revenda nao distingue TV de celular, so
/// enxerga um dispositivo com MAC, Key e modelo:
///
///   GET  {ATIVACAO_API}?mac=..&key=..&modelo=..
///        -> { status, lista_url, epg_url, trial_expira_em }
///        (status = sem_lista | trial | ativo | expirado; lista_url ja decifrada)
///   POST {ATIVACAO_API}  body { mac, key, acao: adicionar|listar|selecionar|excluir, ... }
///
/// O app NUNCA acessa a tabela direto.
class Dispositivo {
  /// Canal de distribuicao. A build de LOJA nao pode mostrar QR/link de
  /// ativacao (seria lido como venda/compra externa pela Apple/Google); a build
  /// distribuida pelo proprio site pode. Ver "Conformidade nas Lojas".
  ///   flutter build apk --dart-define=HP_CANAL=direto
  static const canal = String.fromEnvironment('HP_CANAL', defaultValue: 'loja');

  /// `true` quando esta build pode exibir QR + link do site na tela de ativacao.
  static bool get mostraAtivacaoNoApp => canal == 'direto';

  /// Endpoint da Edge Function de ativacao (projeto Supabase do TV).
  /// Vazio = nao configurado -> o app funciona so com listas manuais.
  static const _apiPadrao =
      'https://cfwmeeksnwampfdkicye.supabase.co/functions/v1/ativacao';
  static const _anonPadrao =
      'eyJhbGciOiJIUzI1NiIsInR5cCI6IkpXVCJ9.eyJpc3MiOiJzdXBhYmFzZSIsInJlZiI6ImNmd21lZWtzbndhbXBmZGtpY3llIiwicm9sZSI6ImFub24iLCJpYXQiOjE3ODQ5MDIwMjksImV4cCI6MjEwMDQ3ODAyOX0.oFd0yNhE4I0uqrGzkmetVQllZs6loUrpsoXzvY9C2Tg';

  /// Pagina web onde o cliente ativa (alvo do QR na build direta).
  static const paginaAtivacao = 'https://heroplaytv.com/upload.html';

  static const _canalNativo = MethodChannel('heroplay/dispositivo');

  final Armazenamento _armazenamento;
  final String api;
  final String anonKey;

  Dispositivo(
    this._armazenamento, {
    String? api,
    String? anonKey,
  })  : api = (api == null || api.isEmpty) ? _apiPadrao : api,
        anonKey = (anonKey == null || anonKey.isEmpty) ? _anonPadrao : anonKey;

  String? _mac;
  String? _key;

  String get mac => _mac ?? '';
  String get key => _key ?? '';

  // ── Identidade ESTAVEL ─────────────────────────────────────────────────────
  //
  // Igual ao app de TV: derivamos MAC/Key de um ID de HARDWARE, entao o MESMO
  // aparelho gera SEMPRE o mesmo par — reinstalar o app nao perde a ativacao.
  // Sem ID de hardware (fallback), sorteamos e persistimos no Hive.

  /// Resolve a identidade UMA vez, no boot, antes de consultar a nuvem.
  Future<void> inicializar() async {
    if (_mac != null) return;
    final id = await _idPlataforma();
    if (id != null) {
      _mac = _macDe(id);
      _key = _keyDe(id);
    } else {
      _mac = _armazenamento.obterIdentidadeDispositivo('mac') ?? _sortearMac();
      _key = _armazenamento.obterIdentidadeDispositivo('key') ?? _sortearKey();
    }
    await _armazenamento.salvarIdentidadeDispositivo('mac', _mac!);
    await _armazenamento.salvarIdentidadeDispositivo('key', _key!);
  }

  /// ID de hardware por plataforma. Android: `Settings.Secure.ANDROID_ID`
  /// (via MethodChannel na MainActivity). iOS: UUID guardado no Keychain,
  /// semeado pelo `identifierForVendor` (ver AppDelegate.swift) — o Keychain
  /// sobrevive a desinstalar o app, o identifierForVendor sozinho nao.
  /// Windows: `MachineGuid` do registro, exposto pelo device_info_plus.
  /// null quando nao for possivel.
  Future<String?> _idPlataforma() async {
    try {
      if (defaultTargetPlatform == TargetPlatform.android) {
        final id = await _canalNativo.invokeMethod<String>('androidId');
        if (id != null && id.isNotEmpty) return 'aid:$id';
      } else if (defaultTargetPlatform == TargetPlatform.iOS) {
        final id = await _canalNativo.invokeMethod<String>('iosId');
        if (id != null && id.isNotEmpty) return 'ios:$id';
      } else if (defaultTargetPlatform == TargetPlatform.windows) {
        final info = await DeviceInfoPlugin().windowsInfo;
        if (info.deviceId.isNotEmpty) return 'win:${info.deviceId}';
      }
    } catch (e) {
      debugPrint('[DISPOSITIVO] sem id de hardware: $e');
    }
    return null;
  }

  /// djb2 — o MESMO hash do `device.js`, para o formato do MAC/Key bater com o
  /// que o painel ja conhece.
  static int _hash(String s) {
    var h = 5381;
    for (var i = 0; i < s.length; i++) {
      h = ((h * 33) ^ s.codeUnitAt(i)) & 0xFFFFFFFF;
    }
    return h;
  }

  static String _macDe(String id) {
    final a = _hash(id), b = _hash('mac|$id');
    // 1o octeto com o bit "locally administered" (0x02) e unicast.
    final octetos = <int>[
      (a & 0xFC) | 0x02,
      (a >> 8) & 0xFF,
      (a >> 16) & 0xFF,
      b & 0xFF,
      (b >> 8) & 0xFF,
      (b >> 16) & 0xFF,
    ];
    return octetos
        .map((x) => x.toRadixString(16).padLeft(2, '0').toUpperCase())
        .join(':');
  }

  static String _keyDe(String id) => '${100000 + (_hash('key|$id') % 900000)}';

  static String _sortearMac() {
    final r = Random.secure();
    return List.generate(
      6,
      (_) => r.nextInt(256).toRadixString(16).padLeft(2, '0').toUpperCase(),
    ).join(':');
  }

  static String _sortearKey() => '${100000 + Random.secure().nextInt(900000)}';

  /// Tela com lado menor >= 600dp — a mesma regra de `utils/layout.dart` para
  /// separar tablet de celular. Aqui NAO ha BuildContext (isto roda no boot,
  /// antes do runApp), entao medimos pela view da plataforma.
  static bool get _telaDeTablet {
    try {
      final v = PlatformDispatcher.instance.implicitView ??
          PlatformDispatcher.instance.views.first;
      final logica = v.physicalSize / v.devicePixelRatio;
      return logica.shortestSide >= 600;
    } catch (_) {
      return false;
    }
  }

  /// Plataforma do aparelho — o painel traduz o codigo para nome amigavel e
  /// icone (ver `MODELO_INFO` em `painel/painel.js`). Celular e tablet sao
  /// codigos DIFERENTES para o revendedor saber o que o cliente tem em maos.
  String plataforma() {
    switch (defaultTargetPlatform) {
      case TargetPlatform.android:
        return _telaDeTablet ? 'androidtablet' : 'android';
      case TargetPlatform.iOS:
        return _telaDeTablet ? 'ipados' : 'ios';
      case TargetPlatform.windows:
        return 'windows';
      case TargetPlatform.macOS:
        return 'macos';
      case TargetPlatform.linux:
        return 'linux';
      default:
        return 'web';
    }
  }

  // ── Registro local (snapshot do que a nuvem devolveu) ──────────────────────

  Map? get registro => _armazenamento.obterRegistroDispositivo();

  /// URL da lista que o painel definiu para este aparelho (null se nenhuma).
  String? get listaUrl {
    final u = registro?['lista_url'] as String?;
    return (u == null || u.trim().isEmpty) ? null : u.trim();
  }

  String? get epgUrl {
    final u = registro?['epg_url'] as String?;
    return (u == null || u.trim().isEmpty) ? null : u.trim();
  }

  /// sem_lista | trial | ativo | expirado
  String get status => (registro?['status'] as String?) ?? 'sem_lista';

  /// Aparelho em periodo de teste (ainda dentro do prazo).
  bool get emTeste => status == 'trial';

  /// Teste terminou (ou a ativacao venceu) — a lista do aparelho para de valer.
  /// A lista que o usuario adicionou A MAO continua funcionando: o app segue
  /// sendo um player de "traga a sua lista".
  bool get expirado => status == 'expirado';

  /// So ha lista utilizavel vinda da nuvem se ela existe E nao expirou.
  bool get temLista => listaUrl != null && !expirado;

  /// Dias de teste que a nuvem concede a um aparelho novo. A fonte da verdade e
  /// a Edge Function `ativacao`; isto e so o espelho local.
  static const diasDeTeste = 3;

  /// Dias restantes de teste (0 quando ja venceu).
  int get diasTeste {
    final iso = registro?['trial_expira_em'] as String?;
    if (iso == null) return diasDeTeste;
    final fim = DateTime.tryParse(iso);
    if (fim == null) return diasDeTeste;
    final ms = fim.difference(DateTime.now()).inMilliseconds;
    return ms <= 0 ? 0 : (ms / 86400000).ceil();
  }

  /// URL do QR: leva o cliente a pagina de ativacao ja com o aparelho preenchido.
  String get urlAtivacao =>
      '$paginaAtivacao?mac=${Uri.encodeComponent(mac)}&key=${Uri.encodeComponent(key)}';

  // ── Nuvem ──────────────────────────────────────────────────────────────────

  /// Consulta a nuvem (best-effort) e atualiza o snapshot local.
  ///
  /// Offline-first: timeout curto e, em qualquer falha, mantem o cache atual —
  /// o boot NUNCA fica preso esperando a rede (o mesmo cuidado do app de TV).
  Future<Map?> consultar() async {
    if (api.isEmpty) return registro;
    try {
      final uri = Uri.parse(
        '$api?mac=${Uri.encodeComponent(mac)}&key=${Uri.encodeComponent(key)}'
        '&modelo=${Uri.encodeComponent(plataforma())}',
      );
      final r = await http.get(uri, headers: {
        'accept': 'application/json',
        'apikey': anonKey,
        'authorization': 'Bearer $anonKey',
      }).timeout(const Duration(seconds: 8));
      if (r.statusCode < 200 || r.statusCode >= 300) return registro;
      final j = jsonDecode(utf8.decode(r.bodyBytes));
      if (j is! Map) return registro;
      await _armazenamento.salvarRegistroDispositivo(j);
      return j;
    } catch (e) {
      debugPrint('[DISPOSITIVO] consultar falhou: $e');
      return registro;
    }
  }

  /// POST generico na Edge Function (best-effort). Sempre injeta mac+key.
  Future<Map?> _post(Map<String, dynamic> corpo) async {
    if (api.isEmpty) return null;
    try {
      final r = await http
          .post(
            Uri.parse(api),
            headers: {
              'content-type': 'application/json',
              'apikey': anonKey,
              'authorization': 'Bearer $anonKey',
            },
            body: jsonEncode({'mac': mac, 'key': key, ...corpo}),
          )
          .timeout(const Duration(seconds: 15));
      final j = jsonDecode(utf8.decode(r.bodyBytes));
      return j is Map ? j : null;
    } catch (e) {
      debugPrint('[DISPOSITIVO] post falhou: $e');
      return null;
    }
  }

  /// Registra uma playlist DESTE aparelho na nuvem (best-effort) e devolve o
  /// registro local atualizado. Usado quando o usuario adiciona a lista pelo
  /// proprio app (caminho manual continua valendo).
  Future<Map> adicionarPlaylist({
    required String listaUrl,
    String? epgUrl,
    String nome = '',
  }) async {
    final local = <String, dynamic>{
      'status': 'trial',
      'lista_url': listaUrl,
      'epg_url': epgUrl,
      'trial_expira_em': DateTime.now()
          .add(const Duration(days: diasDeTeste))
          .toIso8601String(),
    };
    final j = await _post({
      'acao': 'adicionar',
      'lista_url': listaUrl,
      'epg_url': epgUrl ?? '',
      'nome': nome,
      'modelo': plataforma(),
    });
    if (j != null && j['ok'] != false) {
      local['status'] = j['status'] ?? local['status'];
      local['trial_expira_em'] =
          j['trial_expira_em'] ?? local['trial_expira_em'];
    }
    await _armazenamento.salvarRegistroDispositivo(local);
    return local;
  }

  /// Playlists vinculadas a este aparelho ([] se offline/sem API).
  Future<List<Map>> listarPlaylists() async {
    final j = await _post({'acao': 'listar'});
    final l = j?['playlists'];
    return l is List ? l.whereType<Map>().toList() : const [];
  }

  /// Define a playlist ATIVA do aparelho.
  Future<bool> selecionarPlaylist(String id) async {
    final j = await _post({'acao': 'selecionar', 'id': id});
    return j != null && j['ok'] != false;
  }

  /// Remove o vinculo desta playlist com o aparelho.
  Future<bool> excluirPlaylist(String id) async {
    final j = await _post({'acao': 'excluir', 'id': id});
    return j != null && j['ok'] != false;
  }
}

/// Utilitarios de lista: montar a URL a partir do Xtream e DERIVAR o EPG da M3U.
/// Porte de `ListaUtil` (`tv-app/device.js`) — mesma regra nos dois apps.
class ListaUtil {
  /// Xtream (host + usuario + senha) -> URL M3U (get.php) + EPG (xmltv.php).
  static ({String listaUrl, String epgUrl}) montarXtream(
    String host,
    String usuario,
    String senha,
  ) {
    var base = host.trim();
    if (!RegExp(r'^https?://', caseSensitive: false).hasMatch(base)) {
      base = 'http://$base'; // assume http se omitido
    }
    base = base
        .replaceAll(RegExp(r'/+$'), '')
        .replaceAll(RegExp(r'/(get|player_api|xmltv)\.php.*$', caseSensitive: false), '');
    final q = 'username=${Uri.encodeComponent(usuario.trim())}'
        '&password=${Uri.encodeComponent(senha.trim())}';
    return (
      listaUrl: '$base/get.php?$q&type=m3u_plus&output=ts',
      epgUrl: '$base/xmltv.php?$q',
    );
  }

  /// Deriva a URL do EPG a partir da M3U (Xtream). Vazio para M3U avulsa.
  ///
  /// Dois formatos sao cobertos:
  ///   `.../get.php?username=U&password=P`  (querystring, o mais comum)
  ///   `.../playlist/U/P/m3u_plus`          (caminho, usado por alguns paineis)
  /// Mesma regra do site (`website/upload.html`) e do app de TV.
  static String derivarEpg(String m3uUrl) {
    try {
      final u = Uri.parse(m3uUrl.trim());
      var user = u.queryParameters['username'];
      var pass = u.queryParameters['password'];
      if (user == null || pass == null) {
        final seg = u.pathSegments.where((s) => s.isNotEmpty).toList();
        final i = seg.indexWhere(
          (s) => RegExp(r'^(playlist|get|m3u)$', caseSensitive: false)
              .hasMatch(s),
        );
        if (i != -1 && seg.length >= i + 3) {
          user = seg[i + 1];
          pass = seg[i + 2];
        }
      }
      if (user != null && pass != null) {
        return '${u.scheme}://${u.authority}/xmltv.php'
            '?username=${Uri.encodeComponent(user)}'
            '&password=${Uri.encodeComponent(pass)}';
      }
    } catch (_) {}
    return '';
  }
}
