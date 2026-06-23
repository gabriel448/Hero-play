/* ============================================================================
   Hero Play TV — app principal (prototipo).
   Renderiza a sidebar e as secoes. Inicio/Filmes/Series usam o MESMO formato:
   banner de destaque no topo + trilhos horizontais (referencia: "Inicio" do GTV),
   com a identidade do Hero Play. Navegacao por D-pad via spatial-nav.js.
   ============================================================================ */

// ── Icones (SVG inline, stroke) ─────────────────────────────────────────────
const ICO = {
  inicio: '<path d="M3 10.5 12 3l9 7.5"/><path d="M5 9.5V21h14V9.5"/>',
  tv: '<rect x="2" y="4" width="20" height="14" rx="2"/><path d="M8 21h8"/>',
  filme: '<rect x="3" y="3" width="18" height="18" rx="2"/><path d="M7 3v18M17 3v18M3 8h4M17 8h4M3 16h4M17 16h4"/>',
  serie: '<rect x="2" y="3" width="20" height="14" rx="2"/><path d="m7 21 5-4 5 4"/>',
  playlist: '<path d="M3 6h13M3 12h13M3 18h9"/><path d="m18 12 4 3-4 3z"/>',
  busca: '<circle cx="11" cy="11" r="7"/><path d="m21 21-4.3-4.3"/>',
  jogos: '<path d="M6 4h12v3a6 6 0 0 1-12 0z"/><path d="M9 14h6M12 14v4M8 21h8"/>',
  config: '<circle cx="12" cy="12" r="3"/><path d="M19.4 15a1.65 1.65 0 0 0 .33 1.82l.06.06a2 2 0 1 1-2.83 2.83l-.06-.06a1.65 1.65 0 0 0-1.82-.33 1.65 1.65 0 0 0-1 1.51V21a2 2 0 0 1-4 0v-.09A1.65 1.65 0 0 0 9 19.4a1.65 1.65 0 0 0-1.82.33l-.06.06a2 2 0 1 1-2.83-2.83l.06-.06a1.65 1.65 0 0 0 .33-1.82 1.65 1.65 0 0 0-1.51-1H3a2 2 0 0 1 0-4h.09A1.65 1.65 0 0 0 4.6 9a1.65 1.65 0 0 0-.33-1.82l-.06-.06a2 2 0 1 1 2.83-2.83l.06.06a1.65 1.65 0 0 0 1.82.33H9a1.65 1.65 0 0 0 1-1.51V3a2 2 0 0 1 4 0v.09a1.65 1.65 0 0 0 1 1.51 1.65 1.65 0 0 0 1.82-.33l.06-.06a2 2 0 1 1 2.83 2.83l-.06.06a1.65 1.65 0 0 0-.33 1.82V9a1.65 1.65 0 0 0 1.51 1H21a2 2 0 0 1 0 4h-.09a1.65 1.65 0 0 0-1.51 1z"/>',
};
const svg = (k) => `<svg viewBox="0 0 24 24">${ICO[k]}</svg>`;

const MENU = [
  { id: 'inicio', rotulo: 'Início', ico: 'inicio' },
  { id: 'tvaovivo', rotulo: 'TV ao vivo', ico: 'tv' },
  { id: 'filmes', rotulo: 'Filmes', ico: 'filme' },
  { id: 'series', rotulo: 'Séries', ico: 'serie' },
  { id: 'playlists', rotulo: 'Playlists', ico: 'playlist' },
  { id: 'buscar', rotulo: 'Buscar', ico: 'busca' },
  { id: 'jogos', rotulo: 'Jogos do dia', ico: 'jogos' },
];

// ── Util: cor deterministica do "poster" a partir do titulo ─────────────────
function hashStr(s) {
  let h = 0;
  for (let i = 0; i < s.length; i++) h = (h * 31 + s.charCodeAt(i)) | 0;
  return Math.abs(h);
}
function gradiente(titulo, vivido = false) {
  const h = hashStr(titulo) % 360;
  const h2 = (h + 40) % 360;
  if (vivido) {
    return `linear-gradient(135deg, hsl(${h} 60% 30%), hsl(${h2} 65% 16%))`;
  }
  return `linear-gradient(150deg, hsl(${h} 48% 26%), hsl(${h2} 55% 13%))`;
}
const escapar = (s) => s.replace(/[&<>"]/g, (c) =>
  ({ '&': '&amp;', '<': '&lt;', '>': '&gt;', '"': '&quot;' }[c]));
const iniciais = (nome) => {
  const p = nome.trim().split(/\s+/);
  return ((p[0]?.[0] || '') + (p[1]?.[0] || '')).toUpperCase() || nome.slice(0, 2).toUpperCase();
};
const hhmm = (d) => String(d.getHours()).padStart(2, '0') + ':' + String(d.getMinutes()).padStart(2, '0');

// ── Render: poster ──────────────────────────────────────────────────────────
function posterHTML(item) {
  return `<div class="poster focusable" data-id="${item.id}">
    <div class="poster-arte" style="background:${gradiente(item.titulo)}">
      <span>${escapar(item.titulo)}</span>
    </div>
  </div>`;
}

// ── Render: trilho ──────────────────────────────────────────────────────────
function trilhoHTML(t) {
  return `<section class="trilho">
    <h2 class="trilho-titulo">${escapar(t.titulo)}</h2>
    <div class="trilho-fila">${t.itens.map(posterHTML).join('')}</div>
  </section>`;
}

// ── Render: hero (destaque) ─────────────────────────────────────────────────
function heroHTML(item) {
  const meta = [
    `<span>${item.ano}</span>`,
    `<span class="nota">★ ${item.nota.toFixed(1)}</span>`,
    ...item.generos.map((g) => `<span class="selo">${escapar(g)}</span>`),
  ].join('');
  return `<header class="hero">
    <div class="hero-bg" style="background:${gradiente(item.titulo, true)}"></div>
    <div class="hero-conteudo">
      <h1 class="hero-titulo">${escapar(item.titulo)}</h1>
      <div class="hero-meta">${meta}</div>
      <p class="hero-sinopse">${escapar(item.sinopse)}</p>
      <div class="hero-acoes">
        <button class="btn btn-primario focusable" data-id="${item.id}" data-acao="assistir">
          <svg viewBox="0 0 24 24"><path d="M8 5v14l11-7z"/></svg> Assistir
        </button>
        <button class="btn btn-secundario focusable" data-acao="lista">
          <svg viewBox="0 0 24 24"><path d="M12 5v14M5 12h14" stroke="currentColor" stroke-width="2.4" fill="none" stroke-linecap="round"/></svg> Minha Lista
        </button>
      </div>
    </div>
  </header>`;
}

// ── Render: secao de midia (Inicio/Filmes/Series) ───────────────────────────
function renderMidia(cfg) {
  return `<div class="secao">
    ${heroHTML(cfg.destaque)}
    ${cfg.trilhos.map(trilhoHTML).join('')}
  </div>`;
}

// ── TV ao vivo: 2 colunas (categorias↔canais | preview + EPG) ───────────────
let _tvCategoriaAtiva = null;
let _tvCanalPreview = null;
let _hlsPrev = null;

let _favoritos = new Set();
try { _favoritos = new Set(JSON.parse(localStorage.getItem('tv_favoritos') || '[]')); } catch (_) {}
function salvarFavoritos() {
  try { localStorage.setItem('tv_favoritos', JSON.stringify([..._favoritos])); } catch (_) {}
}

const IC_STAR = (on) => on
  ? '<svg viewBox="0 0 24 24"><path d="M12 2l2.9 6.26L22 9.27l-5 4.87 1.18 6.88L12 17.77 5.82 21l1.18-6.88-5-4.87 7.1-1.01z"/></svg>'
  : '<svg viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="1.7" stroke-linejoin="round"><path d="M12 2l2.9 6.26L22 9.27l-5 4.87 1.18 6.88L12 17.77 5.82 21l1.18-6.88-5-4.87 7.1-1.01z"/></svg>';

const CHEV_R = '<svg class="tv-chev" viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="2" stroke-linecap="round" stroke-linejoin="round"><path d="m9 18 6-6-6-6"/></svg>';
const CHEV_L = '<svg class="tv-chev" viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="2" stroke-linecap="round" stroke-linejoin="round"><path d="m15 18-6-6 6-6"/></svg>';

function categorias() {
  const out = [], visto = new Set();
  for (const c of CANAIS) if (!visto.has(c.categoria)) { visto.add(c.categoria); out.push(c.categoria); }
  return out;
}
function canaisDaCategoria(cat) {
  return cat === '__fav'
    ? CANAIS.filter((c) => _favoritos.has(c.id))
    : CANAIS.filter((c) => c.categoria === cat);
}

function htmlCategorias() {
  const itens = [
    `<div class="tv-cat-item focusable" data-cat="__fav"><span class="tv-cat-nome">Favoritos</span>${CHEV_R}</div>`,
    ...categorias().map((cat) =>
      `<div class="tv-cat-item focusable" data-cat="${escapar(cat)}"><span class="tv-cat-nome">${escapar(cat)}</span>${CHEV_R}</div>`),
  ].join('');
  return `<div class="tv-lista tv-anim-esq"><div class="tv-lista-cab">Categorias</div>${itens}</div>`;
}

function htmlCanais(cat) {
  const lista = canaisDaCategoria(cat);
  const nome = cat === '__fav' ? 'Favoritos' : cat;
  const itens = lista.map((c) =>
    `<div class="tv-canal-item focusable" data-canal="${c.id}">
       <div class="tv-canal-logo" style="background:${gradiente(c.nome, true)}"><span>${iniciais(c.nome)}</span></div>
       <div class="tv-canal-txt">
         <div class="tv-canal-nome">${c.num} · ${escapar(c.nome)}</div>
         <div class="tv-canal-agora">${escapar(c.agora)}</div>
       </div>
     </div>`).join('');
  return `<div class="tv-lista tv-anim-dir">
    <div class="tv-lista-cab">${CHEV_L} ${escapar(nome)}</div>
    ${itens}
  </div>`;
}

function htmlPreviewVazio() {
  return `<div class="tv-preview tv-preview-vazio">
    <div class="tv-vazio-logo">▶</div>
    <div class="tv-vazio-titulo">Canais ao vivo</div>
    <div class="tv-vazio-sub">Selecione uma categoria e um canal</div>
  </div>`;
}

function htmlEpg(c) {
  const linhas = [
    { hora: 'AGORA', nome: c.agora, atual: true },
    { hora: c.proxIni, nome: c.prox },
    { hora: '—', nome: 'Programa seguinte' },
    { hora: '—', nome: 'Mais tarde' },
  ];
  return `<div class="tv-prog-lista">${linhas.map((l) =>
    `<div class="tv-prog-row${l.atual ? ' atual' : ''}">
       <span class="tv-prog-hora">${l.hora}</span><span class="tv-prog-nome">${escapar(l.nome)}</span>
     </div>`).join('')}</div>`;
}

// Estrutura FIXA do preview (criada uma vez). O <video> persiste entre canais —
// so trocamos a fonte e os textos; recriar o elemento deixava a tela preta.
function htmlPreviewShell() {
  return `<div class="tv-preview tv-anim-dir">
    <div class="tv-tela focusable" data-acao="tela">
      <video id="tv-prev-video" playsinline muted></video>
      <div class="tv-tela-hint">
        <svg viewBox="0 0 24 24" fill="none" stroke="#fff" stroke-width="2" stroke-linecap="round" stroke-linejoin="round"><path d="M8 3H5a2 2 0 0 0-2 2v3M21 8V5a2 2 0 0 0-2-2h-3M3 16v3a2 2 0 0 0 2 2h3M16 21h3a2 2 0 0 0 2-2v-3"/></svg>
        Abrir em tela cheia
      </div>
    </div>
    <div class="tv-prev-cab">
      <div class="tv-prev-logo" id="tv-prev-logo"><span id="tv-prev-ini"></span></div>
      <div class="tv-prev-titulos">
        <div class="tv-prev-canal" id="tv-prev-canal"></div>
        <div class="tv-prev-agora" id="tv-prev-agora"></div>
      </div>
      <button class="tv-fav-btn focusable" id="tv-fav-btn" data-acao="favoritar"></button>
    </div>
    <div class="tv-prog">
      <div class="tv-prog-titulo">Programação</div>
      <div id="tv-prog-area"></div>
    </div>
  </div>`;
}

function renderTvAoVivo() {
  _tvCategoriaAtiva = null;
  _tvCanalPreview = null;
  return `<div class="tv-vivo">
    <div class="tv-col-esq">
      <div class="tv-panes" id="tv-panes">
        <div class="tv-pane-cat" id="tv-pane-cat">${htmlCategorias()}</div>
        <div class="tv-pane-canais" id="tv-pane-canais"></div>
      </div>
    </div>
    <div class="tv-col-dir" id="tv-col-dir">${htmlPreviewVazio()}</div>
  </div>`;
}

function mostrarCanais(cat) {
  const lista = canaisDaCategoria(cat);
  if (cat === '__fav' && lista.length === 0) { toast('Nenhum canal favoritado ainda'); return; }
  _tvCategoriaAtiva = cat;
  const pane = document.getElementById('tv-pane-canais');
  pane.innerHTML = htmlCanais(cat);
  // As categorias continuam visiveis a esquerda (recuadas + fade); ver CSS.
  document.getElementById('tv-panes').classList.add('com-canais');
  const primeiro = pane.querySelector('.focusable');
  if (primeiro) SpatialNav.setFocus(primeiro);
}

function mostrarCategorias() {
  _tvCategoriaAtiva = null;
  document.getElementById('tv-panes').classList.remove('com-canais');
  const pane = document.getElementById('tv-pane-canais');
  if (pane) pane.innerHTML = ''; // limpa p/ nao deixar canais focaveis escondidos
  const alvo = document.querySelector('#tv-pane-cat .focusable');
  if (alvo) SpatialNav.setFocus(alvo);
}

function pararPreview() {
  if (_hlsPrev) { _hlsPrev.destroy(); _hlsPrev = null; }
}

// (Re)carrega o video do preview (coluna direita). Reusado ao voltar da tela cheia.
function carregarPreviewVideo() {
  const v = document.getElementById('tv-prev-video');
  if (!v) return;
  if (window.Hls && Hls.isSupported()) {
    if (!_hlsPrev) {
      _hlsPrev = new Hls();
      _hlsPrev.on(Hls.Events.MANIFEST_PARSED, () => { v.muted = true; v.play().catch(() => {}); });
      _hlsPrev.attachMedia(v);
    }
    _hlsPrev.loadSource(TEST_HLS); // troca a fonte SEM recriar a instancia
  } else {
    v.src = TEST_HLS; v.muted = true;
    v.addEventListener('loadedmetadata', () => v.play().catch(() => {}), { once: true });
  }
}

function selecionarPreview(canal) {
  _tvCanalPreview = canal;
  const col = document.getElementById('tv-col-dir');
  if (!document.getElementById('tv-prev-video')) col.innerHTML = htmlPreviewShell();

  document.getElementById('tv-prev-logo').style.background = gradiente(canal.nome, true);
  document.getElementById('tv-prev-ini').textContent = iniciais(canal.nome);
  document.getElementById('tv-prev-canal').textContent = `${canal.num} · ${canal.nome}`;
  document.getElementById('tv-prev-agora').textContent = `Agora: ${canal.agora}`;
  const fav = _favoritos.has(canal.id);
  const favBtn = document.getElementById('tv-fav-btn');
  favBtn.innerHTML = IC_STAR(fav);
  favBtn.classList.toggle('ativo', fav);
  document.getElementById('tv-prog-area').innerHTML = htmlEpg(canal);

  carregarPreviewVideo();
  // Mantem o foco na lista de canais (usuario vai pra DIREITA p/ a tela).
}

function alternarFavorito(id) {
  if (_favoritos.has(id)) _favoritos.delete(id); else _favoritos.add(id);
  salvarFavoritos();
  const on = _favoritos.has(id);
  document.querySelectorAll('.tv-fav-btn, .live-fav-btn').forEach((b) => {
    b.innerHTML = IC_STAR(on);
    b.classList.toggle('ativo', on);
  });
  toast(on ? 'Adicionado aos favoritos' : 'Removido dos favoritos');
}

function renderPlaceholder(titulo, msg) {
  return `<div class="placeholder">
    <h2>${escapar(titulo)}</h2>
    <p>${escapar(msg)}</p>
  </div>`;
}

// ── Roteamento entre secoes ─────────────────────────────────────────────────
function navegar(secaoId) {
  pararPreview(); // para o preview da TV ao vivo ao sair da secao
  document.querySelectorAll('.nav-item').forEach((n) =>
    n.classList.toggle('ativo', n.dataset.secao === secaoId));

  const main = document.getElementById('conteudo');
  if (secaoId === 'inicio' || secaoId === 'filmes' || secaoId === 'series') {
    main.innerHTML = renderMidia(CATALOGO[secaoId]);
  } else if (secaoId === 'tvaovivo') {
    main.innerHTML = renderTvAoVivo();
  } else if (secaoId === 'playlists') {
    main.innerHTML = renderPlaceholder('Playlists', 'Gerência de listas — adicionar via site/QR (próxima fase).');
  } else if (secaoId === 'buscar') {
    main.innerHTML = renderPlaceholder('Buscar', 'Busca de filmes, séries e canais (próxima fase).');
  } else if (secaoId === 'jogos') {
    main.innerHTML = renderPlaceholder('Jogos do dia', 'Agenda de jogos + onde assistir (próxima fase).');
  } else if (secaoId === 'config') {
    main.innerHTML = renderPlaceholder('Configurações', 'Idioma, conta, ativação, sobre (próxima fase).');
  }
  main.scrollTop = 0;

  // Foca o 1o elemento do conteudo; se nao houver (placeholder), mantem no menu.
  const primeiro = main.querySelector('.focusable');
  if (primeiro) SpatialNav.setFocus(primeiro);
}

// ── Detalhe (overlay simples ao abrir um poster) ────────────────────────────
function abrirDetalhe(item) {
  const ov = document.createElement('div');
  ov.id = 'detalhe-overlay';
  ov.className = 'nav-modal';
  ov.style.cssText =
    'position:fixed;inset:0;z-index:300;display:flex;align-items:center;' +
    'padding:0 64px;background:' + gradiente(item.titulo, true) + ';';
  ov.innerHTML = `
    <div style="position:absolute;inset:0;background:linear-gradient(90deg,#0F0E0D 20%,rgba(15,14,13,.6) 60%,transparent)"></div>
    <div style="position:relative;max-width:620px">
      <h1 class="hero-titulo">${escapar(item.titulo)}</h1>
      <div class="hero-meta"><span>${item.ano}</span><span class="nota">★ ${item.nota.toFixed(1)}</span>${item.generos.map((g) => `<span class="selo">${escapar(g)}</span>`).join('')}</div>
      <p class="hero-sinopse" style="-webkit-line-clamp:5">${escapar(item.sinopse)}</p>
      <div class="hero-acoes">
        <button class="btn btn-primario focusable" data-acao="play"><svg viewBox="0 0 24 24"><path d="M8 5v14l11-7z"/></svg> Assistir</button>
        <button class="btn btn-secundario focusable" data-acao="fechar">Voltar</button>
      </div>
    </div>`;
  document.body.appendChild(ov);
  ov._onVoltar = fecharDetalhe;
  ov.querySelector('[data-acao="fechar"]').addEventListener('click', fecharDetalhe);
  ov.querySelector('[data-acao="play"]').addEventListener('click', () => {
    ov.remove();
    abrirPlayer(item);
  });
  SpatialNav.setFocus(ov.querySelector('.btn-primario'));
}
function fecharDetalhe() {
  const ov = document.getElementById('detalhe-overlay');
  if (ov) ov.remove();
  const f = document.querySelector('#conteudo .focusable');
  if (f) SpatialNav.setFocus(f);
}

// ── Player (HLS) ────────────────────────────────────────────────────────────
// Stream PUBLICO de teste (Mux/Big Buck Bunny) — player neutro, sem conteudo
// embutido. Depois vem da playlist do dispositivo.
const TEST_HLS = 'https://test-streams.mux.dev/x36xhzz/x36xhzz.m3u8';
const IC_PLAY = '<svg viewBox="0 0 24 24"><path d="M8 5v14l11-7z"/></svg>';
const IC_PAUSE = '<svg viewBox="0 0 24 24"><path d="M6 5h4v14H6zM14 5h4v14h-4z"/></svg>';

let _hls = null;
let _hideTimer = null;
let _scrub = null; // { alvo, holdStart, dir, nivel } durante a busca na barra
let _relogioInt = null; // relogio da TV ao vivo

function fmtTempo(s) {
  if (!isFinite(s) || s < 0) return '0:00';
  s = Math.floor(s);
  const m = Math.floor(s / 60), ss = String(s % 60).padStart(2, '0');
  const h = Math.floor(m / 60);
  return h > 0 ? `${h}:${String(m % 60).padStart(2, '0')}:${ss}` : `${m}:${ss}`;
}

function abrirPlayer(item) {
  const ov = document.createElement('div');
  ov.id = 'player-overlay';
  ov.className = 'nav-modal player-modal';
  ov.innerHTML = `
    <video id="player-video" playsinline></video>
    <div class="player-fade"></div>
    <button class="player-voltar focusable" data-acao="fechar">
      <svg viewBox="0 0 24 24"><path d="M15 18l-6-6 6-6" stroke="currentColor" stroke-width="2.4" fill="none" stroke-linecap="round" stroke-linejoin="round"/></svg> Voltar
    </button>
    <div class="player-titulo">${escapar(item.titulo)}</div>
    <div class="player-controles">
      <div class="pc-tempo">
        <span id="pc-atual">0:00</span>
        <div class="pc-barra-wrap focusable" data-acao="barra">
          <div class="pc-barra"><div class="pc-prog" id="pc-prog"></div></div>
          <div class="pc-preview" id="pc-preview"><span id="pc-preview-tempo">0:00</span></div>
        </div>
        <span id="pc-total">0:00</span>
      </div>
      <div class="pc-botoes">
        <div class="pc-centro">
          <button class="pc-btn focusable" data-acao="retroceder"><svg viewBox="0 0 24 24"><path d="M11 18V6l-8.5 6 8.5 6zM20 18V6l-8.5 6 8.5 6z"/></svg></button>
          <button class="pc-btn pc-play focusable" data-acao="playpause">${IC_PAUSE}</button>
          <button class="pc-btn focusable" data-acao="avancar"><svg viewBox="0 0 24 24"><path d="M13 6v12l8.5-6L13 6zM4 6v12l8.5-6L4 6z"/></svg></button>
        </div>
        <div class="pc-direita">
          <button class="pc-btn pc-btn-sm focusable" data-acao="legendas"><span class="cc">CC</span></button>
          <button class="pc-btn pc-btn-sm focusable" data-acao="audio"><svg viewBox="0 0 24 24"><path d="M3 10v4h4l5 5V5L7 10H3z"/><path d="M16 8.5a4 4 0 0 1 0 7" stroke="#fff" stroke-width="1.8" fill="none"/></svg></button>
        </div>
      </div>
    </div>`;
  document.body.appendChild(ov);
  ov._onVoltar = fecharPlayer;

  const video = document.getElementById('player-video');
  if (video.canPlayType('application/vnd.apple.mpegurl')) {
    video.src = TEST_HLS;                 // HLS nativo (Safari/algumas TVs)
  } else if (window.Hls && Hls.isSupported()) {
    _hls = new Hls();
    _hls.loadSource(TEST_HLS);
    _hls.attachMedia(video);
  } else {
    video.src = TEST_HLS;
  }
  video.play().catch(() => {});

  const q = (a) => ov.querySelector(`[data-acao="${a}"]`);
  q('fechar').addEventListener('click', fecharPlayer);
  q('playpause').addEventListener('click', () => (video.paused ? video.play() : video.pause()));
  q('retroceder').addEventListener('click', () => { video.currentTime = Math.max(0, video.currentTime - 10); revelarControles(); });
  q('avancar').addEventListener('click', () => { video.currentTime = Math.min(video.duration || 1e9, video.currentTime + 10); revelarControles(); });
  q('legendas').addEventListener('click', () => toast('Legendas — em breve'));
  q('audio').addEventListener('click', () => toast('Faixas de áudio — em breve'));

  video.addEventListener('timeupdate', () => {
    if (_scrub) return; // durante a busca, a barra mostra o ALVO (preview)
    const prog = document.getElementById('pc-prog');
    if (!prog) return;
    if (video.duration) prog.style.width = (video.currentTime / video.duration * 100) + '%';
    document.getElementById('pc-atual').textContent = fmtTempo(video.currentTime);
    document.getElementById('pc-total').textContent = fmtTempo(video.duration);
  });
  const sincIcone = () => { q('playpause').innerHTML = video.paused ? IC_PLAY : IC_PAUSE; };
  video.addEventListener('play', sincIcone);
  video.addEventListener('pause', sincIcone);

  revelarControles();
  SpatialNav.setFocus(q('playpause'));
}

// Busca na barra: cada toque avanca/recua; segurar acelera ate 3 niveis.
function scrub(dir) {
  const v = document.getElementById('player-video');
  if (!v || !v.duration) return;
  const agora = performance.now();
  if (!_scrub || _scrub.dir !== dir) _scrub = { alvo: v.currentTime, holdStart: agora, dir };
  const held = agora - _scrub.holdStart;
  const nivel = held < 1200 ? 1 : held < 3000 ? 2 : 3;
  const passo = nivel === 1 ? 5 : nivel === 2 ? 20 : 60;
  _scrub.alvo = Math.max(0, Math.min(v.duration, _scrub.alvo + dir * passo));
  _scrub.nivel = nivel;
  // Preview: move a barra/indicador para o ALVO e mostra o tempo acima dele.
  const pct = (_scrub.alvo / v.duration) * 100;
  const prog = document.getElementById('pc-prog');
  const prev = document.getElementById('pc-preview');
  if (prog) prog.style.width = pct + '%';
  if (prev) {
    prev.style.left = pct + '%';
    prev.classList.add('ativo');
    document.getElementById('pc-preview-tempo').textContent =
      fmtTempo(_scrub.alvo) + (nivel > 1 ? `  ${nivel}x` : '');
  }
}

function commitScrub() {
  if (!_scrub) return;
  const v = document.getElementById('player-video');
  if (v) v.currentTime = _scrub.alvo;
  _scrub = null;
  const prev = document.getElementById('pc-preview');
  if (prev) prev.classList.remove('ativo');
}

function toast(msg) {
  let t = document.getElementById('toast');
  if (!t) { t = document.createElement('div'); t.id = 'toast'; document.body.appendChild(t); }
  t.textContent = msg;
  t.classList.add('ativo');
  clearTimeout(t._timer);
  t._timer = setTimeout(() => t.classList.remove('ativo'), 1800);
}

// Teclas do player (CAPTURE: roda ANTES da navegacao no window/bubble).
// Regra: com os controles ocultos, a 1a tecla so os REVELA (engole o evento).
window.addEventListener('keydown', (e) => {
  const ov = document.querySelector('.player-modal');
  if (!ov) return;
  if (ov.classList.contains('controles-ocultos')) {
    revelarControles();
    e.preventDefault(); e.stopPropagation();
    return;
  }
  revelarControles(); // mantem visivel enquanto interage
  const naBarra = SpatialNav.atual && SpatialNav.atual.dataset &&
                  SpatialNav.atual.dataset.acao === 'barra';
  if (naBarra && e.key === 'ArrowRight') { e.preventDefault(); e.stopPropagation(); scrub(1); return; }
  if (naBarra && e.key === 'ArrowLeft')  { e.preventDefault(); e.stopPropagation(); scrub(-1); return; }
  if (naBarra && e.key === 'Enter')      { e.preventDefault(); e.stopPropagation(); commitScrub(); return; }
  if (_scrub) commitScrub(); // qualquer outra tecla confirma a busca pendente
}, true);

// Soltar a seta confirma a busca (commit do scrub).
window.addEventListener('keyup', (e) => {
  if (_scrub && (e.key === 'ArrowRight' || e.key === 'ArrowLeft')) commitScrub();
}, true);

// TV ao vivo: "direita" numa categoria abre os canais; "esquerda" num canal
// volta para as categorias.
window.addEventListener('keydown', (e) => {
  if (document.querySelector('.player-modal')) return; // nao interfere no player
  const at = SpatialNav.atual;
  if (!at || !at.closest) return;
  if (e.key === 'ArrowRight' && at.classList.contains('tv-cat-item')) {
    e.preventDefault(); e.stopPropagation();
    mostrarCanais(at.dataset.cat);
  } else if (e.key === 'ArrowLeft' && at.classList.contains('tv-canal-item')) {
    e.preventDefault(); e.stopPropagation();
    mostrarCategorias();
  } else if (e.key === 'ArrowLeft' && at.closest('.tv-col-dir')) {
    // Da coluna do player (preview/EPG/estrela) → vai para a LISTA DE CANAIS
    // que esta aparecendo (nao para o sliver de categorias).
    const pane = document.getElementById('tv-pane-canais');
    const alvoCanal = pane && (
      pane.querySelector(`.tv-canal-item[data-canal="${_tvCanalPreview ? _tvCanalPreview.id : ''}"]`) ||
      pane.querySelector('.tv-canal-item')
    );
    if (alvoCanal) {
      e.preventDefault(); e.stopPropagation();
      SpatialNav.setFocus(alvoCanal);
    }
  }
}, true);

function revelarControles() {
  const ov = document.querySelector('.player-modal');
  if (!ov) return;
  ov.classList.remove('controles-ocultos');
  clearTimeout(_hideTimer);
  _hideTimer = setTimeout(() => {
    const o = document.querySelector('.player-modal');
    if (o) o.classList.add('controles-ocultos');
  }, 4000);
}

function fecharPlayer() {
  clearTimeout(_hideTimer);
  if (_hls) { _hls.destroy(); _hls = null; }
  const ov = document.getElementById('player-overlay');
  if (ov) ov.remove();
  const f = document.querySelector('#conteudo .focusable');
  if (f) SpatialNav.setFocus(f);
}

// ── Player de TV AO VIVO (full-screen estilo TV a cabo) ─────────────────────
function abrirLive(canal) {
  clearInterval(_relogioInt); _relogioInt = null; // defensivo: nunca 2 relogios
  const ov = document.createElement('div');
  ov.id = 'live-overlay';
  ov.className = 'nav-modal player-modal';
  ov.innerHTML = `
    <div class="live-video-slot" id="live-video-slot"></div>
    <div class="player-fade"></div>
    <button class="player-voltar focusable" data-acao="fechar">
      <svg viewBox="0 0 24 24"><path d="M15 18l-6-6 6-6" stroke="currentColor" stroke-width="2.4" fill="none" stroke-linecap="round" stroke-linejoin="round"/></svg> Voltar
    </button>
    <div class="live-topdir">
      <button class="live-top-btn live-fav-btn focusable${_favoritos.has(canal.id) ? ' ativo' : ''}" data-acao="favoritar">${IC_STAR(_favoritos.has(canal.id))}</button>
      <button class="live-top-btn focusable" data-acao="qualidade">
        <svg viewBox="0 0 24 24"><path d="M4 7h16M4 12h16M4 17h10" stroke="#fff" stroke-width="2" fill="none" stroke-linecap="round"/></svg> Qualidade
      </button>
      <button class="live-top-btn focusable" data-acao="fontes">
        <svg viewBox="0 0 24 24"><rect x="3" y="4" width="18" height="13" rx="2" stroke="#fff" stroke-width="2" fill="none"/><path d="M8 21h8" stroke="#fff" stroke-width="2" stroke-linecap="round"/></svg> Fontes
      </button>
    </div>
    <div class="live-bar">
      <div class="live-bar-esq">
        <span class="live-num">${canal.num}</span>
        <span class="live-canal-nome">${escapar(canal.nome)}</span>
      </div>
      <div class="live-bar-centro">
        <div class="live-prog-atual">${escapar(canal.agora)}</div>
        <div class="live-prog-prox">A seguir: <b>${escapar(canal.prox)}</b> · ${canal.proxIni}</div>
      </div>
      <div class="live-bar-dir">
        <div class="live-relogio" id="live-relogio">--:--</div>
        <div class="live-logo" style="background:${gradiente(canal.nome, true)}"><span>${iniciais(canal.nome)}</span></div>
        <button class="live-epg-btn focusable" data-acao="epg">
          <svg viewBox="0 0 24 24"><rect x="3" y="4" width="18" height="16" rx="2" stroke="#fff" stroke-width="2" fill="none"/><path d="M3 9h18M8 4v16" stroke="#fff" stroke-width="2"/></svg> Programação
        </button>
      </div>
    </div>`;
  document.body.appendChild(ov);
  ov._onVoltar = fecharLive;

  // Reaproveita o MESMO <video> do preview (ja tocando): move-o para a tela
  // cheia e desmuta. Evita 2 instancias HLS (causa da tela preta).
  const slot = document.getElementById('live-video-slot');
  const pv = document.getElementById('tv-prev-video');
  if (pv && slot) {
    slot.appendChild(pv);
    pv.muted = false;
    pv.play().catch(() => { pv.muted = true; pv.play().catch(() => {}); });
  }

  const q = (a) => ov.querySelector(`[data-acao="${a}"]`);
  q('fechar').addEventListener('click', fecharLive);
  q('favoritar').addEventListener('click', () => alternarFavorito(canal.id));
  q('qualidade').addEventListener('click', () => toast('Qualidade — em breve'));
  q('fontes').addEventListener('click', () => toast('Fontes — em breve'));
  q('epg').addEventListener('click', () => toast('Programação — em breve'));

  const tick = () => { const r = document.getElementById('live-relogio'); if (r) r.textContent = hhmm(new Date()); };
  tick();
  _relogioInt = setInterval(tick, 1000);

  revelarControles();
  SpatialNav.setFocus(q('epg'));
}

function fecharLive() {
  clearTimeout(_hideTimer);
  clearInterval(_relogioInt); _relogioInt = null;
  // Devolve o <video> (ainda tocando) para a tela do preview e remuda.
  const v = document.getElementById('tv-prev-video');
  const tela = document.querySelector('.tv-tela');
  if (v && tela) { v.muted = true; tela.insertBefore(v, tela.firstChild); }
  const ov = document.getElementById('live-overlay');
  if (ov) ov.remove();
  const alvo = document.querySelector('.tv-tela') || document.querySelector('#conteudo .focusable');
  if (alvo) SpatialNav.setFocus(alvo);
}

// ── Boot ────────────────────────────────────────────────────────────────────
function montarSidebar() {
  document.getElementById('nav-itens').innerHTML = MENU.map((m) =>
    `<div class="nav-item focusable" data-secao="${m.id}">
       <span class="ico">${svg(m.ico)}</span><span class="rotulo">${m.rotulo}</span>
     </div>`).join('');
  document.getElementById('nav-config').innerHTML =
    `<div class="nav-item focusable" data-secao="config">
       <span class="ico">${svg('config')}</span><span class="rotulo">Configurações</span>
     </div>`;

  document.querySelectorAll('.nav-item').forEach((n) =>
    n.addEventListener('click', () => navegar(n.dataset.secao)));
}

// Clicks de conteudo (delegado): poster abre detalhe; "Assistir" do hero idem.
document.addEventListener('click', (e) => {
  const cat = e.target.closest('.tv-cat-item');
  if (cat) { mostrarCanais(cat.dataset.cat); return; }
  const canalItem = e.target.closest('.tv-canal-item');
  if (canalItem) {
    const c = CANAIS.find((x) => x.id === canalItem.dataset.canal);
    if (c) selecionarPreview(c);
    return;
  }
  const tela = e.target.closest('.tv-tela');
  if (tela) { if (_tvCanalPreview) abrirLive(_tvCanalPreview); return; }
  const favBtn = e.target.closest('.tv-fav-btn');
  if (favBtn) { if (_tvCanalPreview) alternarFavorito(_tvCanalPreview.id); return; }
  const poster = e.target.closest('.poster');
  if (poster) {
    const item = [...FILMES, ...SERIES].find((x) => x.id === poster.dataset.id);
    if (item) abrirDetalhe(item);
    return;
  }
  const assistir = e.target.closest('[data-acao="assistir"]');
  if (assistir) {
    const item = [...FILMES, ...SERIES].find((x) => x.id === assistir.dataset.id);
    if (item) abrirDetalhe(item);
  }
});

window.addEventListener('DOMContentLoaded', () => {
  montarSidebar();
  navegar('inicio');
});
