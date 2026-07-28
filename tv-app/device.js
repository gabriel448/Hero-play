/* ============================================================================
   Identidade do dispositivo (MAC + Key) + consulta de ativacao/lista na nuvem.

   Contrato (plano §9): o app de TV NUNCA acessa a tabela direto — so via Edge
   Function `ativacao` do projeto Supabase do TV:
     GET {ATIVACAO_API}?mac=..&key=..  ->  { status, lista_url, epg_url, trial_expira_em }
   (lista_url ja vem DECIFRADA; status = sem_lista | trial | ativo | expirado)

   No protótipo o MAC/Key sao gerados e guardados em localStorage. Em Tizen/webOS
   reais, trocar por APIs da plataforma:
     - Tizen:  tizen.systeminfo.getPropertyValue('ETHERNET_NETWORK' / 'WIFI_NETWORK')  -> MAC
     - webOS:  luna://com.webos.service.connectionmanager getinfo                       -> MAC
   ============================================================================ */
const Dispositivo = (() => {
  // Endpoint da Edge Function de ativacao (projeto Supabase do TV).
  // Vazio = ainda nao configurado (protótipo) -> usa só o cache local.
  const ATIVACAO_API = 'https://cfwmeeksnwampfdkicye.supabase.co/functions/v1/ativacao';
  const ANON = 'eyJhbGciOiJIUzI1NiIsInR5cCI6IkpXVCJ9.eyJpc3MiOiJzdXBhYmFzZSIsInJlZiI6ImNmd21lZWtzbndhbXBmZGtpY3llIiwicm9sZSI6ImFub24iLCJpYXQiOjE3ODQ5MDIwMjksImV4cCI6MjEwMDQ3ODAyOX0.oFd0yNhE4I0uqrGzkmetVQllZs6loUrpsoXzvY9C2Tg'; // chave publica (anon)
  // Pagina web onde o cliente adiciona a lista / ativa (alvo do QR Code).
  const PAGINA_ATIVACAO = 'https://heroplaytv.com/upload.html';

  const LS = { mac: 'hp_mac', key: 'hp_key', reg: 'hp_lista' };

  const geraMac = () => {
    const h = () => Math.floor(Math.random() * 256).toString(16).padStart(2, '0').toUpperCase();
    return [h(), h(), h(), h(), h(), h()].join(':');
  };
  const geraKey = () => String(Math.floor(100000 + Math.random() * 900000));

  // localStorage protegido: em alguns contextos de app de TV o acesso LANÇA
  // (SecurityError) — sem o try/catch o módulo inteiro morre e o app nem inicia.
  function persistente(chave, gerar) {
    let v = null;
    try { v = localStorage.getItem(chave); } catch (_) {}
    if (!v) { v = gerar(); try { localStorage.setItem(chave, v); } catch (_) {} }
    return v;
  }
  // ── Identidade ESTÁVEL (sobrevive a reinstalar / limpar dados) ─────────────
  // Antes o MAC/Key eram aleatórios em localStorage → mudavam ao reinstalar (o
  // `--remove` apaga os dados). Agora, no webOS, derivamos de um ID de HARDWARE
  // (LGUDID): o MESMO aparelho gera SEMPRE o mesmo mac/key. Navegador/dev cai no
  // aleatório persistido (como antes).
  function _luna(uri, params, ms) {
    return new Promise((resolve) => {
      try {
        if (typeof PalmServiceBridge === 'undefined') return resolve(null);
        const b = new PalmServiceBridge();
        let feito = false;
        const fim = (v) => { if (!feito) { feito = true; resolve(v); } };
        b.onservicecallback = (msg) => { try { fim(JSON.parse(msg)); } catch (_) { fim(null); } };
        b.call(uri, JSON.stringify(params || {}));
        setTimeout(() => fim(null), ms || 3000);
      } catch (_) { resolve(null); }
    });
  }
  const _hash = (s) => { let h = 5381; for (let i = 0; i < s.length; i++) h = ((h * 33) ^ s.charCodeAt(i)) >>> 0; return h; };
  function _macDe(id) {
    const a = _hash(id), b = _hash('mac|' + id);
    const oct = [(a & 0xFC) | 0x02, (a >>> 8) & 0xFF, (a >>> 16) & 0xFF, b & 0xFF, (b >>> 8) & 0xFF, (b >>> 16) & 0xFF];
    return oct.map((x) => x.toString(16).padStart(2, '0').toUpperCase()).join(':');
  }
  const _keyDe = (id) => String(100000 + (_hash('key|' + id) % 900000));

  // ── Samsung (Tizen) ────────────────────────────────────────────────────────
  // Sem isto, numa Samsung a identidade caía no sorteio guardado em
  // localStorage: o MAC/Key MUDAVA ao reinstalar o app ou limpar os dados, e a
  // ativação se perdia. Duas fontes, em ordem de confiabilidade:
  //   1. webapis.productinfo.getDuid() — id único do aparelho (API de TV Samsung),
  //      o equivalente do LGUDID.
  //   2. tizen.systeminfo -> macAddress da placa de rede (cabo, depois Wi-Fi).
  // ⚠️ Escrito a partir da doc da Samsung — ainda NÃO testado em TV real.
  function _tizenDuid() {
    try {
      if (typeof webapis !== 'undefined' && webapis.productinfo && webapis.productinfo.getDuid) {
        const d = webapis.productinfo.getDuid();
        if (d) return String(d);
      }
    } catch (_) {}
    return null;
  }
  function _tizenMac(tipo, ms) {
    return new Promise((resolve) => {
      try {
        if (typeof tizen === 'undefined' || !tizen.systeminfo) return resolve(null);
        let feito = false;
        const fim = (v) => { if (!feito) { feito = true; resolve(v); } };
        tizen.systeminfo.getPropertyValue(
          tipo,
          (net) => fim((net && net.macAddress) ? String(net.macAddress) : null),
          () => fim(null),
        );
        setTimeout(() => fim(null), ms || 2000);
      } catch (_) { resolve(null); }
    });
  }

  async function _idPlataforma() {
    // Android TV / Fire TV / TV Box (casca WebView): ANDROID_ID.
    // Vem PRIMEIRO por ser síncrono e por ser o único caso em que o fallback
    // (MAC sorteado no localStorage) causava dano de verdade: o WebView perde o
    // localStorage ao DESINSTALAR, então reinstalar trocava o MAC e obrigava a
    // reativar. O ANDROID_ID sobrevive a reinstalar o mesmo APK assinado.
    try {
      if (window.HeroPlayAndroid && HeroPlayAndroid.idDispositivo) {
        const aid = HeroPlayAndroid.idDispositivo();
        if (aid) return 'aid:' + aid;
      }
    } catch (_) {}
    // LGUDID: UUID único e estável por aparelho (recomendado da LG).
    const r = await _luna('luna://com.webos.service.sm/deviceid/getIDs', { idType: ['LGUDID'] });
    if (r && r.idList) { const u = r.idList.filter((x) => x && x.idValue)[0]; if (u) return 'udid:' + u.idValue; }
    // fallback: MAC real da placa de rede.
    const c = await _luna('luna://com.webos.service.connectionmanager/getStatus', {});
    if (c) {
      const m = (c.wired && c.wired.info && c.wired.info.macAddress) || (c.wifi && c.wifi.info && c.wifi.info.macAddress);
      if (m) return 'mac:' + m;
    }
    // Samsung (Tizen).
    const duid = _tizenDuid();
    if (duid) return 'duid:' + duid;
    const macT = (await _tizenMac('ETHERNET_NETWORK')) || (await _tizenMac('WIFI_NETWORK'));
    if (macT) return 'mac:' + macT;
    return null;
  }

  let _macFixo = null, _keyFixo = null;
  // Resolve a identidade UMA vez, no boot (antes de mostrar o QR / consultar).
  async function init() {
    if (_macFixo) return;
    try {
      const id = await _idPlataforma();
      if (id) {
        _macFixo = _macDe(id); _keyFixo = _keyDe(id);
        try { localStorage.setItem(LS.mac, _macFixo); localStorage.setItem(LS.key, _keyFixo); } catch (_) {}
        return;
      }
    } catch (_) {}
    _macFixo = persistente(LS.mac, geraMac);   // navegador/dev: aleatório persistido
    _keyFixo = persistente(LS.key, geraKey);
  }
  const mac = () => _macFixo || persistente(LS.mac, geraMac);
  const key = () => _keyFixo || persistente(LS.key, geraKey);

  // Plataforma do aparelho (p/ o painel mostrar "LG / Samsung / Roku"). Deriva do
  // userAgent: webOS (LG), Tizen (Samsung), Roku. 'web' = navegador/dev. Futuro:
  // Android TV / TV Box entram aqui. O painel traduz o código p/ nome amigável.
  function plataforma() {
    const ua = (navigator.userAgent || '').toLowerCase();
    if (/web[0o]s|webos/.test(ua)) return 'webos';
    if (/tizen/.test(ua)) return 'tizen';
    if (/roku/.test(ua)) return 'roku';
    if (/android\s*tv|googletv|aft[a-z]|bravia/.test(ua)) return 'androidtv';
    return 'web';
  }

  // Snapshot local do que a nuvem retornou (lista + status).
  function registro() {
    try { return JSON.parse(localStorage.getItem(LS.reg) || 'null'); } catch (_) { return null; }
  }
  function salvar(reg) { try { localStorage.setItem(LS.reg, JSON.stringify(reg || {})); } catch (_) {} }

  const temLista = () => { const r = registro(); return !!(r && r.lista_url); };
  const status = () => { const r = registro(); return (r && r.status) || 'sem_lista'; };

  function diasTeste() {
    const r = registro();
    if (!r || !r.trial_expira_em) return 7;
    const ms = new Date(r.trial_expira_em) - new Date();
    return Math.max(0, Math.ceil(ms / 864e5));
  }

  // URL do QR: leva o cliente para a pagina ja com o device preenchido.
  const urlAtivacao = () =>
    `${PAGINA_ATIVACAO}?mac=${encodeURIComponent(mac())}&key=${encodeURIComponent(key())}`;

  // Consulta a nuvem (best-effort). Atualiza o cache local. Se a API nao estiver
  // configurada ou a rede falhar, mantem o cache atual (offline-first).
  async function consultar() {
    if (!ATIVACAO_API) return registro();
    let to = null;
    try {
      const u = `${ATIVACAO_API}?mac=${encodeURIComponent(mac())}&key=${encodeURIComponent(key())}&modelo=${encodeURIComponent(plataforma())}`;
      // TIMEOUT (8s): o boot ESPERA por isso. Na TV a rede pode pendurar e, sem
      // cortar, o app trava antes de renderizar (tela vazia). Offline-first: no
      // estouro, seguimos com o cache local.
      const ctrl = (typeof AbortController !== 'undefined') ? new AbortController() : null;
      if (ctrl) to = setTimeout(() => ctrl.abort(), 8000);
      const r = await fetch(u, {
        headers: { accept: 'application/json', apikey: ANON, authorization: 'Bearer ' + ANON },
        signal: ctrl ? ctrl.signal : undefined,
      });
      if (to) { clearTimeout(to); to = null; }
      if (!r.ok) return registro();
      const j = await r.json();
      salvar(j);
      return j;
    } catch (_) {
      return registro();
    } finally {
      if (to) clearTimeout(to);
    }
  }

  // POST genérico p/ a Edge Function (best-effort). Sempre injeta mac+key.
  async function _post(payload) {
    if (!ATIVACAO_API) return null;
    try {
      const r = await fetch(ATIVACAO_API, {
        method: 'POST',
        headers: { 'content-type': 'application/json', apikey: ANON, authorization: 'Bearer ' + ANON },
        body: JSON.stringify({ mac: mac(), key: key(), ...payload }),
      });
      return await r.json().catch(() => ({ ok: r.ok }));
    } catch (_) { return null; }
  }

  // Adiciona uma playlist DESTE device (nome opcional): registra na nuvem
  // (best-effort) e grava local (offline-first). Vira a lista ATIVA.
  async function adicionar(lista_url, epg_url, nome) {
    const local = {
      status: 'trial', lista_url, epg_url,
      trial_expira_em: new Date(Date.now() + 7 * 864e5).toISOString(),
    };
    const j = await _post({ acao: 'adicionar', lista_url, epg_url, nome: nome || '', modelo: plataforma() });
    if (j && j.ok !== false) {
      local.status = j.status || local.status;
      local.trial_expira_em = j.trial_expira_em || local.trial_expira_em;
    }
    salvar(local);
    return local;
  }

  // Playlists vinculadas a este device (via Edge Function). [] se offline/sem API.
  async function listarPlaylists() {
    const j = await _post({ acao: 'listar' });
    return (j && Array.isArray(j.playlists)) ? j.playlists : [];
  }
  // Define a playlist ATIVA do device.
  async function selecionarPlaylist(id) {
    const j = await _post({ acao: 'selecionar', id });
    return !!(j && j.ok !== false);
  }
  // Remove a playlist deste device (apaga do Supabase se ficar órfã).
  async function excluirPlaylist(id) {
    const j = await _post({ acao: 'excluir', id });
    return !!(j && j.ok !== false);
  }

  return { init, mac, key, plataforma, temLista, status, diasTeste, registro, salvar, consultar, adicionar, listarPlaylists, selecionarPlaylist, excluirPlaylist, urlAtivacao };
})();

// Utilitarios de lista: montar a URL a partir do Xtream e DERIVAR o EPG da M3U.
const ListaUtil = {
  // Xtream (host + usuario + senha) -> URL M3U (get.php) + EPG (xmltv.php).
  montarXtream(host, user, pass) {
    let base = (host || '').trim();
    if (!/^https?:\/\//i.test(base)) base = 'http://' + base; // assume http se omitido
    base = base.replace(/\/+$/, '').replace(/\/(get|player_api|xmltv)\.php.*$/i, '');
    const q = `username=${encodeURIComponent(user.trim())}&password=${encodeURIComponent(pass.trim())}`;
    return {
      lista_url: `${base}/get.php?${q}&type=m3u_plus&output=ts`,
      epg_url: `${base}/xmltv.php?${q}`,
    };
  },
  // Deriva a URL do EPG a partir da M3U. Para Xtream (.../get.php?username&password)
  // o EPG e .../xmltv.php com as mesmas credenciais. M3U avulsa -> sem EPG.
  // Dois formatos de Xtream sao cobertos:
  //   .../get.php?username=U&password=P   (querystring, o mais comum)
  //   .../playlist/U/P/m3u_plus           (caminho, usado por alguns paineis)
  // Mesma regra do site (website/upload.html) e do app Flutter.
  derivarEpg(m3uUrl) {
    try {
      const u = new URL(m3uUrl.trim());
      let user = u.searchParams.get('username');
      let pass = u.searchParams.get('password');
      if (!user || !pass) {
        const seg = u.pathname.split('/').filter(Boolean);
        const i = seg.findIndex((x) => /^(playlist|get|m3u)$/i.test(x));
        if (i !== -1 && seg.length >= i + 3) { user = seg[i + 1]; pass = seg[i + 2]; }
      }
      if (user && pass) {
        return `${u.protocol}//${u.host}/xmltv.php?username=${encodeURIComponent(user)}&password=${encodeURIComponent(pass)}`;
      }
    } catch (_) {}
    return '';
  },
};

// DEV (protótipo, sem backend): simular estados pelo console. Remover em produção.
//   HP_DEV.simularLista()  -> adiciona lista em TESTE (trial 7d)
//   HP_DEV.simularAtivo()  -> marca como ATIVO
//   HP_DEV.limpar()        -> volta ao onboarding (sem lista)
window.HP_DEV = {
  simularLista: () => {
    Dispositivo.salvar({
      status: 'trial',
      lista_url: 'https://exemplo.com/get.php?username=demo&password=demo&type=m3u_plus',
      epg_url: 'https://exemplo.com/xmltv.php?username=demo&password=demo',
      trial_expira_em: new Date(Date.now() + 7 * 864e5).toISOString(),
    });
    location.reload();
  },
  simularAtivo: () => {
    const r = Dispositivo.registro() || {};
    r.status = 'ativo';
    r.lista_url = r.lista_url || 'https://exemplo.com/get.php?username=demo&password=demo';
    Dispositivo.salvar(r);
    location.reload();
  },
  limpar: () => { localStorage.removeItem('hp_lista'); location.reload(); },
};
