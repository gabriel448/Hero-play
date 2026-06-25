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
  const ATIVACAO_API = 'https://mlafyphpntjssmxagyhc.supabase.co/functions/v1/ativacao';
  const ANON = 'sb_publishable_MlxtdbBT4UJWhBVJ5Krtww_AvZHXa3I'; // chave publica
  // Pagina web onde o cliente adiciona a lista / ativa (alvo do QR Code).
  const PAGINA_ATIVACAO = 'https://heroplaytv.com/upload.html';

  const LS = { mac: 'hp_mac', key: 'hp_key', reg: 'hp_lista' };

  const geraMac = () => {
    const h = () => Math.floor(Math.random() * 256).toString(16).padStart(2, '0').toUpperCase();
    return [h(), h(), h(), h(), h(), h()].join(':');
  };
  const geraKey = () => String(Math.floor(100000 + Math.random() * 900000));

  function persistente(chave, gerar) {
    let v = localStorage.getItem(chave);
    if (!v) { v = gerar(); localStorage.setItem(chave, v); }
    return v;
  }
  const mac = () => persistente(LS.mac, geraMac);
  const key = () => persistente(LS.key, geraKey);

  // Snapshot local do que a nuvem retornou (lista + status).
  function registro() {
    try { return JSON.parse(localStorage.getItem(LS.reg) || 'null'); } catch (_) { return null; }
  }
  function salvar(reg) { localStorage.setItem(LS.reg, JSON.stringify(reg || {})); }

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
    try {
      const u = `${ATIVACAO_API}?mac=${encodeURIComponent(mac())}&key=${encodeURIComponent(key())}`;
      const r = await fetch(u, { headers: { accept: 'application/json', apikey: ANON, authorization: 'Bearer ' + ANON } });
      if (!r.ok) return registro();
      const j = await r.json();
      salvar(j);
      return j;
    } catch (_) {
      return registro();
    }
  }

  // Adiciona a lista DESTE device: registra na nuvem (best-effort) e grava local
  // (offline-first). Assim o site (gerenciar) também enxerga o dispositivo.
  async function adicionar(lista_url, epg_url) {
    const local = {
      status: 'trial', lista_url, epg_url,
      trial_expira_em: new Date(Date.now() + 7 * 864e5).toISOString(),
    };
    if (ATIVACAO_API) {
      try {
        const r = await fetch(ATIVACAO_API, {
          method: 'POST',
          headers: { 'content-type': 'application/json', apikey: ANON, authorization: 'Bearer ' + ANON },
          body: JSON.stringify({ acao: 'adicionar', mac: mac(), key: key(), lista_url, epg_url, modelo: 'web' }),
        });
        const j = await r.json().catch(() => ({}));
        if (r.ok && j.ok !== false) {
          local.status = j.status || local.status;
          local.trial_expira_em = j.trial_expira_em || local.trial_expira_em;
        }
      } catch (_) { /* sem rede: segue só com o local */ }
    }
    salvar(local);
    return local;
  }

  return { mac, key, temLista, status, diasTeste, registro, salvar, consultar, adicionar, urlAtivacao };
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
  derivarEpg(m3uUrl) {
    try {
      const u = new URL(m3uUrl.trim());
      const user = u.searchParams.get('username');
      const pass = u.searchParams.get('password');
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
