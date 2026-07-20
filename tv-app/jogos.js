/* ============================================================================
   Hero Play TV — Jogos do dia (agenda de futebol, estilo GTV).
   Abas de DATA · ligas à esquerda · jogos ao centro (escudo+times+horário+rodada)
   · "Onde assistir" = canais DA PLAYLIST do usuário que passam o jogo.

   FONTE DE DADOS: por trás de `Jogos.porData(iso)` — hoje um STUB embutido; trocar
   por API-Football (proxy Vercel) depois é só reescrever essa função. O resto (UI +
   casamento com os canais do M3U) não muda. Ver cofre: "Tela de Jogos (Agenda…)".
   Usa globais de app.js/i18n.js: LISTA, normBusca, gradiente, iniciais, escapar,
   hhmm, abrirLive, SpatialNav, t.
   ============================================================================ */

const IC_JG_REFRESH = '<svg viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="2" stroke-linecap="round" stroke-linejoin="round"><path d="M21 12a9 9 0 1 1-2.6-6.4"/><path d="M21 3v6h-6"/></svg>';
const IC_JG_TV = '<svg viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="2" stroke-linecap="round" stroke-linejoin="round"><rect x="2" y="7" width="20" height="13" rx="2"/><path d="m8 3 4 4 4-4"/></svg>';

// ── Util de data ────────────────────────────────────────────────────────────
function _hoje0() { const d = new Date(); d.setHours(0, 0, 0, 0); return d; }
function _isoData(d) { return `${d.getFullYear()}-${String(d.getMonth() + 1).padStart(2, '0')}-${String(d.getDate()).padStart(2, '0')}`; }
function _addDias(d, n) { const x = new Date(d); x.setDate(x.getDate() + n); return x; }

// Abas de data: Ontem / Hoje / Amanhã (índice 1 = Hoje).
// O plano GRÁTIS da API só libera a janela [ontem..amanhã] ("try from ... to ...").
// Em plano pago / proxy com histórico dá p/ ampliar (i até +5).
function datasJogos() {
  const hoje = _hoje0(); const out = [];
  for (let i = -1; i <= 1; i++) {
    const d = _addDias(hoje, i);
    let rot;
    if (i === -1) rot = t('Ontem'); else if (i === 0) rot = t('Hoje'); else if (i === 1) rot = t('Amanhã');
    else rot = String(d.getDate()).padStart(2, '0') + '/' + String(d.getMonth() + 1).padStart(2, '0');
    out.push({ iso: _isoData(d), rot });
  }
  return out;
}

// ── Ligas + STUB de jogos (trocar por API depois) ───────────────────────────
const _LIGAS = {
  'br-c': { id: 'br-c', nome: 'Brasileirão Série C', pais: 'Brasil' },
  'br-b': { id: 'br-b', nome: 'Brasileirão Série B', pais: 'Brasil' },
  'cdm': { id: 'cdm', nome: 'Copa do Mundo', pais: 'Mundo' },
};
// `dia` = offset a partir de hoje. `emissoras` = nomes que casam com a playlist.
const _STUB = [
  { dia: 0, liga: 'br-c', rodada: 11, hora: '17:00', casa: 'Ypiranga', fora: 'Náutico', emissoras: ['SporTV'] },
  { dia: 0, liga: 'br-c', rodada: 11, hora: '19:30', casa: 'Confiança', fora: 'Guarani', emissoras: ['SporTV', 'DAZN'] },
  { dia: 0, liga: 'br-b', rodada: 15, hora: '20:00', casa: 'Sport', fora: 'Goiás', emissoras: ['Premiere', 'ESPN'] },
  { dia: 0, liga: 'br-b', rodada: 15, hora: '21:00', casa: 'Santos', fora: 'Novorizontino', emissoras: ['SporTV', 'Premiere'] },
  { dia: 0, liga: 'cdm', rodada: 0, hora: '16:00', casa: 'Brasil', fora: 'Argentina', emissoras: ['Globo', 'SporTV'] },
  { dia: -1, liga: 'br-b', rodada: 14, hora: '19:00', casa: 'Vila Nova', fora: 'Coritiba', emissoras: ['SporTV', 'Premiere'] },
  { dia: -1, liga: 'br-c', rodada: 10, hora: '16:30', casa: 'Londrina', fora: 'Floresta', emissoras: ['DAZN'] },
  { dia: 1, liga: 'br-c', rodada: 12, hora: '19:30', casa: 'Botafogo-PB', fora: 'São Bernardo', emissoras: ['DAZN', 'SporTV'] },
  { dia: 1, liga: 'br-b', rodada: 16, hora: '16:30', casa: 'Cruzeiro', fora: 'Athletico', emissoras: ['Premiere', 'Globo'] },
  { dia: 2, liga: 'cdm', rodada: 0, hora: '15:00', casa: 'França', fora: 'Alemanha', emissoras: ['SporTV', 'TNT Sports'] },
];

const _cacheJogos = {};   // iso -> grupos (cache p/ não re-buscar a cada foco)

// ── API-Football (via proxy Vercel) ─────────────────────────────────────────
// A chave NÃO fica aqui: o proxy (API/api/futebol.js) a injeta como secret de
// servidor. Antes ela estava neste arquivo — legível por qualquer um que abrisse
// o app ou descompactasse o .ipk. O proxy também cacheia no edge, o que economiza
// a cota diária do plano grátis (N TVs pedindo a mesma data = ~1 ida à API).
const API_BASE = 'https://iptv-zeta-navy.vercel.app/api/futebol';
// Ligas exibidas (id → nome PT). A ordem aqui é a ordem na coluna de ligas.
const LIGAS_PT = {
  71: 'Brasileirão Série A', 72: 'Brasileirão Série B', 75: 'Brasileirão Série C',
  76: 'Brasileirão Série D', 73: 'Copa do Brasil', 13: 'Libertadores',
  11: 'Sul-Americana', 1: 'Copa do Mundo',
};
const LIGAS_ORDEM = [71, 72, 75, 76, 73, 13, 11, 1];
// Emissoras por competição (direitos BR ~2026, aproximado). Casam com os canais
// da playlist via normBusca — nome extra que não existir na lista só é ignorado.
const EMISSORAS = {
  71: ['Premiere', 'Globo', 'SporTV', 'CazéTV'],
  72: ['SporTV', 'Premiere'],
  75: ['SporTV', 'DAZN', 'Premiere', 'Nosso Futebol'],
  76: ['DAZN', 'Nosso Futebol'],
  73: ['Globo', 'SporTV', 'Premiere', 'Amazon'],
  13: ['Paramount', 'SporTV', 'Globo'],
  11: ['Paramount', 'ESPN'],
  1: ['Globo', 'SporTV'],
};
const _rodadaNum = (r) => { const m = String(r || '').match(/(\d+)\s*$/); return m ? +m[1] : 0; };

// Provedor de dados (async): 1 requisição por data (todas as ligas do dia) →
// filtra p/ as ligas monitoradas. Fallback p/ o STUB se a rede falhar (offline).
async function porDataJogos(iso) {
  if (_cacheJogos[iso]) return _cacheJogos[iso];
  let grupos;
  try {
    const u = `${API_BASE}?p=/fixtures&date=${iso}&timezone=${encodeURIComponent('America/Sao_Paulo')}`;
    const r = await fetch(u);
    if (!r.ok) throw new Error('futebol ' + r.status);   // proxy sem chave / cota → stub
    const j = await r.json();
    grupos = _montarGrupos(j && j.response ? j.response : []);
  } catch (_) {
    grupos = _montarGruposStub(iso);   // offline / erro → exemplo
  }
  _cacheJogos[iso] = grupos;
  return grupos;
}

// Fixtures da API → grupos {liga, rodada, jogos[]}, só das ligas monitoradas.
function _montarGrupos(fixtures) {
  const grupos = {};
  for (const f of fixtures) {
    const lid = f.league && f.league.id;
    if (!(lid in LIGAS_PT)) continue;   // só as ligas que exibimos
    if (!grupos[lid]) grupos[lid] = {
      liga: { id: String(lid), nome: LIGAS_PT[lid], pais: f.league.country || '', logo: f.league.logo },
      rodada: _rodadaNum(f.league.round), jogos: [],
    };
    grupos[lid].jogos.push({
      id: 'fx' + f.fixture.id, ts: new Date(f.fixture.date),
      casa: { nome: f.teams.home.name, escudo: f.teams.home.logo },
      fora: { nome: f.teams.away.name, escudo: f.teams.away.logo },
      emissoras: EMISSORAS[lid] || [],
    });
  }
  const arr = Object.values(grupos);
  arr.forEach((g) => g.jogos.sort((a, b) => a.ts - b.ts));
  arr.sort((a, b) => LIGAS_ORDEM.indexOf(+a.liga.id) - LIGAS_ORDEM.indexOf(+b.liga.id));
  return arr;
}

// Fallback offline (STUB) — mesma forma de dados.
function _montarGruposStub(iso) {
  const hoje = _hoje0(); const grupos = {};
  for (const m of _STUB) {
    if (_isoData(_addDias(hoje, m.dia)) !== iso) continue;
    const [H, Min] = m.hora.split(':').map(Number);
    const ts = _addDias(hoje, m.dia); ts.setHours(H, Min, 0, 0);
    if (!grupos[m.liga]) grupos[m.liga] = { liga: _LIGAS[m.liga], rodada: m.rodada, jogos: [] };
    grupos[m.liga].jogos.push({
      id: `${iso}-${m.liga}-${grupos[m.liga].jogos.length}`, ts,
      casa: { nome: m.casa }, fora: { nome: m.fora }, emissoras: m.emissoras,
    });
  }
  const arr = Object.values(grupos);
  arr.forEach((g) => g.jogos.sort((a, b) => a.ts - b.ts));
  return arr;
}

// ── "Onde assistir": casa emissora → canais da PLAYLIST (M3U já carregado) ───
function canaisDaEmissora(nome) {
  if (!nome || !LISTA || !LISTA.canais) return [];
  const alvo = normBusca(nome);
  if (!alvo) return [];
  return LISTA.canais.filter((c) => normBusca(c.nome).includes(alvo));
}
function canaisDoJogo(j) {
  const vistos = new Set(); const out = [];
  for (const em of (j.emissoras || [])) {
    for (const c of canaisDaEmissora(em)) {
      if (!vistos.has(c.id)) { vistos.add(c.id); out.push(c); if (out.length >= 40) return out; }
    }
  }
  return out;
}

// ── Render ──────────────────────────────────────────────────────────────────
let _jogoData = null, _jogoLiga = null;

function renderJogos() {
  _jogoData = null; _jogoLiga = null;
  const datas = datasJogos();
  const tabs = datas.map((d, i) =>
    `<button class="jogos-data focusable${i === 1 ? ' ativa' : ''}" data-iso="${d.iso}">${escapar(d.rot)}</button>`).join('');
  return `<div class="jogos">
    <div class="jogos-topo">
      <div class="jogos-datas">${tabs}</div>
      <button class="jogos-att focusable" id="jogos-att" title="${escapar(t('Atualizar'))}">${IC_JG_REFRESH}</button>
    </div>
    <div class="jogos-corpo">
      <div class="jogos-ligas" id="jogos-ligas"><div class="jogos-vazio">${escapar(t('Carregando jogos…'))}</div></div>
      <div class="jogos-jogos" id="jogos-jogos"></div>
    </div>
  </div>`;
}

function ligarJogos() {
  const att = document.getElementById('jogos-att');
  if (att) att.addEventListener('click', () => { delete _cacheJogos[_jogoData]; const iso = _jogoData; _jogoData = null; selecionarDataJogos(iso, false); });
  // Carrega HOJE (índice 1) e foca a aba Hoje (o .then roda após o setFocus do navegar).
  selecionarDataJogos(datasJogos()[1].iso, true);
}

// Seleciona uma DATA: renderiza as ligas + a 1ª liga. `focar` foca a aba (só no boot).
async function selecionarDataJogos(iso, focar) {
  if (iso === _jogoData) return;
  _jogoData = iso; _jogoLiga = null;
  document.querySelectorAll('.jogos-data').forEach((b) => b.classList.toggle('ativa', b.dataset.iso === iso));
  const ligasEl = document.getElementById('jogos-ligas');
  const jogosEl = document.getElementById('jogos-jogos');
  if (ligasEl) ligasEl.innerHTML = `<div class="jogos-vazio">${escapar(t('Carregando jogos…'))}</div>`;
  if (jogosEl) jogosEl.innerHTML = '';
  const grupos = await porDataJogos(iso);
  if (_jogoData !== iso || !document.getElementById('jogos-ligas')) return; // trocou/saiu
  if (!grupos.length) {
    document.getElementById('jogos-ligas').innerHTML = `<div class="jogos-vazio">${escapar(t('Nenhum jogo nesta data'))}</div>`;
    document.getElementById('jogos-jogos').innerHTML = `<div class="jogos-vazio-centro">${escapar(t('Nenhum jogo nesta data'))}</div>`;
    return;
  }
  renderLigasJogos(grupos);
  mostrarJogosLiga(grupos[0].liga.id, grupos);   // 1ª liga (sem mover o foco)
  if (focar) { const tab = document.querySelector(`.jogos-data[data-iso="${iso}"]`); if (tab) SpatialNav.setFocus(tab); }
}

// Logo (time/liga/canal): imagem REAL da API SOBRE gradiente + iniciais. As
// iniciais só somem quando a imagem CARREGA (com-img); se a imagem falhar, ela é
// removida e as iniciais ficam (nunca vazio). `referrerpolicy=no-referrer` dribla
// o bloqueio de hotlink do CDN da API-Football no app empacotado.
// Proxy de imagem do nosso domínio (o mesmo host do proxy TMDB, que comprovadamente
// carrega nessas TVs). Só entra como 2ª tentativa — ver _logoFalhou.
const IMG_PROXY = 'https://iptv-zeta-navy.vercel.app/api/img';
// A imagem falhou direto do host original. Em TVs antigas (webOS 5/Chromium 68)
// isso acontece com media.api-sports.io — provavelmente cadeia de certificado.
// Tenta de novo pelo nosso proxy; se falhar também, fica só a inicial.
function _logoFalhou(img) {
  if (img.dataset.viaProxy) { img.remove(); return; }
  img.dataset.viaProxy = '1';
  img.src = IMG_PROXY + '?u=' + encodeURIComponent(img.dataset.orig || '');
}
function _logoBox(cls, nome, url) {
  const img = url ? `<img src="${escapar(url)}" alt="" referrerpolicy="no-referrer" data-orig="${escapar(url)}" onload="this.parentNode.classList.add('com-img')" onerror="_logoFalhou(this)">` : '';
  return `<span class="${cls}" style="background:${gradiente(nome, true)}">${img}<b class="logo-ini">${escapar(iniciais(nome))}</b></span>`;
}
function _ligaLogoHTML(liga, cls) { return _logoBox(cls, liga.nome, liga.logo); }
function renderLigasJogos(grupos) {
  const el = document.getElementById('jogos-ligas'); if (!el) return;
  el.innerHTML = grupos.map((g, i) => `
    <button class="jogos-liga focusable${i === 0 ? ' ativa' : ''}" data-liga="${escapar(g.liga.id)}">
      ${_ligaLogoHTML(g.liga, 'jogos-liga-logo')}
      <span class="jogos-liga-txt">
        <span class="jogos-liga-nome">${escapar(g.liga.nome)}</span>
        <span class="jogos-liga-pais">${escapar(g.liga.pais)}</span>
      </span>
    </button>`).join('');
}

// Mostra os jogos de uma liga (reage ao foco na liga). Não move o foco.
async function mostrarJogosLiga(ligaId, grupos) {
  if (ligaId === _jogoLiga) return;
  _jogoLiga = ligaId;
  document.querySelectorAll('.jogos-liga').forEach((b) => b.classList.toggle('ativa', b.dataset.liga === ligaId));
  if (!grupos) grupos = await porDataJogos(_jogoData);
  const el = document.getElementById('jogos-jogos'); if (!el) return;
  const g = grupos.find((x) => x.liga.id === ligaId);
  if (!g) { el.innerHTML = ''; return; }
  el.innerHTML = `
    <div class="jogos-cab">
      <div class="jogos-cab-esq">${_ligaLogoHTML(g.liga, 'jogos-cab-logo')}<span class="jogos-cab-liga">${escapar(g.liga.nome)}</span><span class="jogos-cab-pais">${escapar(g.liga.pais)}</span></div>
      ${g.rodada ? `<div class="jogos-cab-rodada">${escapar(t('Rodada'))} ${g.rodada}</div>` : '<div></div>'}
      <div class="jogos-cab-onde">${escapar(t('Onde assistir'))}</div>
    </div>
    ${g.jogos.map(jogoHTML).join('')}`;
  el.querySelectorAll('.jg-onde').forEach((b) => {
    const jogo = g.jogos.find((x) => x.id === b.dataset.id);
    if (jogo) b.addEventListener('click', () => abrirOndeAssistir(jogo));
  });
}

// Modal "Onde assistir": 2 times no topo (centralizado) + lista de canais da
// playlist (ícone + nome). Clicar num canal abre o player ao vivo.
function abrirOndeAssistir(j) {
  const canais = canaisDoJogo(j);
  const ov = document.createElement('div');
  ov.className = 'nav-modal jg-modal';
  ov.innerHTML = `${htmlVoltar()}<div class="jg-modal-card">
    <div class="jg-modal-topo">
      <div class="jg-modal-time">${_badgeHTML(j.casa)}<span class="jg-modal-nome">${escapar(j.casa.nome)}</span></div>
      <span class="jg-modal-vs">VS</span>
      <div class="jg-modal-time">${_badgeHTML(j.fora)}<span class="jg-modal-nome">${escapar(j.fora.nome)}</span></div>
    </div>
    <div class="jg-modal-sub">${escapar(t('Onde assistir'))}</div>
    <div class="jg-modal-lista">
      ${canais.length
        ? canais.map((c, i) => `<button class="jg-modal-canal focusable${i === 0 ? ' cfg-scroll-topo' : ''}" data-canal="${escapar(c.id)}">${_canalLogoHTML(c)}<span class="jg-modal-canal-nome">${escapar(c.nome)}</span></button>`).join('')
        : `<div class="jogos-vazio">${escapar(t('Não disponível na sua lista'))}</div>`}
    </div>
  </div>`;
  document.body.appendChild(ov);
  const anterior = SpatialNav.atual;
  ov._onVoltar = () => { ov.remove(); if (anterior && document.contains(anterior)) SpatialNav.setFocus(anterior); };
  ov.querySelectorAll('.jg-modal-canal').forEach((b) => b.addEventListener('click', () => {
    const c = LISTA.canais.find((x) => x.id === b.dataset.canal);
    if (c) { ov.remove(); abrirLive(c); }
  }));
  const primeiro = ov.querySelector('.jg-modal-canal') || ov.querySelector('.jg-modal-card');
  if (primeiro && primeiro.classList.contains('focusable')) SpatialNav.setFocus(primeiro);
}

function _badgeHTML(time) { return _logoBox('jogo-badge', time.nome, time.escudo); }
function _canalLogoHTML(c) { return _logoBox('jg-canal-logo', c.nome, c.logo); }
function jogoHTML(j) {
  const n = canaisDoJogo(j).length;
  const label = n > 9 ? t('9+ canais') : (n === 1 ? t('1 canal') : t('{n} canais').replace('{n}', n));
  const onde = n
    ? `<button class="jg-onde focusable" data-id="${escapar(j.id)}"><span class="jg-onde-ico">${IC_JG_TV}</span><span class="jg-onde-txt">${escapar(label)}</span></button>`
    : `<span class="jogo-sem">${escapar(t('Não disponível na sua lista'))}</span>`;
  return `<div class="jogo">
    <div class="jogo-hora">${hhmm(j.ts)}</div>
    <div class="jogo-time jogo-casa">${_badgeHTML(j.casa)}<span class="jogo-nome">${escapar(j.casa.nome)}</span></div>
    <div class="jogo-vs">VS</div>
    <div class="jogo-time jogo-fora"><span class="jogo-nome">${escapar(j.fora.nome)}</span>${_badgeHTML(j.fora)}</div>
    <div class="jogo-onde">${onde}</div>
  </div>`;
}

// ── Navegação D-pad entre abas de data ↔ ligas (cross-área) ─────────────────
window.addEventListener('keydown', (e) => {
  if (!document.querySelector('.jogos')) return;                 // só na tela de jogos
  if (document.querySelector('.nav-modal, .player-modal')) return; // não interfere em modal/player
  const at = SpatialNav.atual; if (!at || !at.classList) return;
  const parar = () => { e.preventDefault(); e.stopPropagation(); };
  if (e.key === 'ArrowDown' && at.classList.contains('jogos-data')) {
    const lg = document.querySelector('.jogos-liga.ativa') || document.querySelector('.jogos-liga');
    if (lg) { parar(); SpatialNav.setFocus(lg); }
  } else if (e.key === 'ArrowUp' && at.classList.contains('jogos-liga')) {
    const ligas = [...document.querySelectorAll('.jogos-liga')];
    if (ligas.indexOf(at) === 0) {                                // só a 1ª liga sobe p/ as abas
      const tab = document.querySelector('.jogos-data.ativa') || document.querySelector('.jogos-data');
      if (tab) { parar(); SpatialNav.setFocus(tab); }
    }                                                             // demais ligas: deixa o engine subir (mesma coluna)
  } else if (e.key === 'ArrowRight' && at.classList.contains('jogos-liga')) {
    const btn = document.querySelector('#jogos-jogos .jg-onde');  // → entra nos jogos (botão "N canais")
    if (btn) { parar(); SpatialNav.setFocus(btn); }
    else parar();                                                 // sem jogos: não faz nada (não vaza)
  } else if (e.key === 'ArrowLeft' && at.closest('#jogos-jogos')) {
    const lg = document.querySelector('.jogos-liga.ativa') || document.querySelector('.jogos-liga');
    if (lg) { parar(); SpatialNav.setFocus(lg); }                 // ← volta p/ a liga selecionada
  } else if ((e.key === 'ArrowRight') && at.closest('#jogos-jogos')) {
    parar();                                                      // já no botão: → não vaza p/ fora
  }
}, true);