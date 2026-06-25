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

// Catálogo ATIVO: stub (data.js) por padrão; substituído pela lista REAL do
// dispositivo assim que ela é baixada/parseada (ver carregarLista()).
let LISTA = { catalogo: CATALOGO, canais: CANAIS, indice: {} };
[...FILMES, ...SERIES].forEach((i) => { LISTA.indice[i.id] = i; });
function aplicarLista(parsed) { LISTA = parsed; }

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
  // Filme: usa o logo/poster da própria lista. Série (sem logo): busca no TMDB
  // de forma lazy (data-serie), ao entrar na viewport.
  const temLogo = !!item.logo;
  const lazy = (item.tipo === 'serie' && !temLogo) ? ` data-serie="${escapar(item.titulo)}"` : '';
  const img = temLogo
    ? `<img class="poster-img" src="${escapar(item.logo)}" alt="" loading="lazy"
         onload="this.closest('.poster-arte').classList.add('tem-img')" onerror="this.remove()">`
    : '';
  return `<div class="poster focusable" data-id="${item.id}"${lazy}>
    <div class="poster-arte" style="background:${gradiente(item.titulo)}">
      ${img}<span>${escapar(item.titulo)}</span>
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
    item.ano ? `<span>${item.ano}</span>` : '',
    (item.nota > 0) ? `<span class="nota">★ ${item.nota.toFixed(1)}</span>` : '',
    ...(item.generos || []).map((g) => `<span class="selo">${escapar(g)}</span>`),
  ].filter(Boolean).join('');
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
// Hero FIXO menor (estilo GTV): reflete o item em foco. Backdrop (2 camadas p/
// crossfade) + poster vertical + título/nota/sinopse, animado ao trocar foco.
function heroFixoHTML() {
  return `<div class="hero2" id="hero2">
    <div class="hero2-bg" id="hero2-bgA"></div>
    <div class="hero2-bg" id="hero2-bgB"></div>
    <div class="hero2-grad"></div>
    <div class="hero2-conteudo" id="hero2-info">
      <div class="hero2-poster" id="hero2-poster"></div>
      <div class="hero2-txt">
        <h1 class="hero2-titulo" id="hero2-titulo"></h1>
        <div class="hero2-meta" id="hero2-meta"></div>
        <p class="hero2-sinopse" id="hero2-sinopse"></p>
      </div>
    </div>
  </div>`;
}
function renderMidia(cfg) {
  if (!cfg.trilhos.length) {
    return `<div class="secao">${renderPlaceholder('Nada por aqui', 'Sua lista não tem itens nesta seção.')}</div>`;
  }
  return `<div class="midia">
    ${heroFixoHTML()}
    <div class="trilhos">${cfg.trilhos.map(trilhoHTML).join('')}</div>
  </div>`;
}

// ── Hero dinâmico (reflete o item em foco; metadados via TMDB) ───────────────
let _heroItem = null, _heroToken = 0, _heroTimer = null, _heroBgAtivo = 'A';

function notaHero(item, inf) {
  const nota = (inf && inf.nota) || (item.nota > 0 ? item.nota : null);
  const ano = (inf && inf.ano) || (item.ano || null);
  const partes = [];
  if (ano) partes.push(`<span>${ano}</span>`);
  if (nota) partes.push(`<span class="nota">★ ${Number(nota).toFixed(1)}</span>`);
  for (const g of (item.generos || [])) partes.push(`<span class="selo">${escapar(g)}</span>`);
  return partes.join('');
}
function setHeroPoster(url, titulo) {
  const el = document.getElementById('hero2-poster');
  if (!el) return;
  if (url) { el.style.background = `#000 center/cover url("${url}")`; el.classList.add('tem'); }
  else { el.style.background = gradiente(titulo, true); el.classList.remove('tem'); }
}
function setHeroBg(url) {
  if (!url) return;
  const aId = _heroBgAtivo === 'A' ? 'hero2-bgA' : 'hero2-bgB';
  const bId = _heroBgAtivo === 'A' ? 'hero2-bgB' : 'hero2-bgA';
  const a = document.getElementById(aId), b = document.getElementById(bId);
  if (!a || !b) return;
  b.style.backgroundImage = `url("${url}")`;
  b.classList.add('on'); a.classList.remove('on');
  _heroBgAtivo = _heroBgAtivo === 'A' ? 'B' : 'A';
}
function atualizarHero(item) {
  const titulo = document.getElementById('hero2-titulo');
  if (!titulo || !item || _heroItem === item.id) return;
  _heroItem = item.id;
  const tok = ++_heroToken;

  titulo.textContent = item.titulo;
  document.getElementById('hero2-meta').innerHTML = notaHero(item, null);
  document.getElementById('hero2-sinopse').textContent = item.sinopse || '';
  setHeroPoster(item.logo || '', item.titulo);

  const info = document.getElementById('hero2-info');
  if (info) { info.classList.remove('hero-anim'); void info.offsetWidth; info.classList.add('hero-anim'); }

  clearTimeout(_heroTimer);
  _heroTimer = setTimeout(async () => {
    const ehSerie = item.tipo === 'serie';
    const inf = await TMDB.info(item.titulo, ehSerie);
    if (tok !== _heroToken) return;
    if (inf && !inf.vazio) {
      if (inf.backdrop) setHeroBg(inf.backdrop);
      document.getElementById('hero2-sinopse').textContent = inf.sinopse || item.sinopse || '';
      document.getElementById('hero2-meta').innerHTML = notaHero(item, inf);
    }
    // Série sem logo: pôster pela busca dedicada (en-US), igual ao mobile.
    if (!item.logo) {
      const pUrl = ehSerie ? await TMDB.poster(item.titulo) : (inf && inf.poster);
      if (tok === _heroToken && pUrl) setHeroPoster(pUrl, item.titulo);
    }
  }, 220);
}

// Lazy: pôster TMDB das séries (que não têm logo na lista) ao entrar na viewport.
let _obsPoster = null;
function ligarPostersSerie(raiz) {
  if (!('IntersectionObserver' in window)) return;
  if (_obsPoster) _obsPoster.disconnect();
  _obsPoster = new IntersectionObserver((ents) => {
    for (const e of ents) {
      if (!e.isIntersecting) continue;
      const el = e.target; _obsPoster.unobserve(el);
      TMDB.poster(el.dataset.serie).then((url) => {
        const arte = el.querySelector('.poster-arte');
        if (!url || !arte) return;
        const img = new Image();
        img.className = 'poster-img';
        img.onload = () => { arte.classList.add('tem-img'); arte.appendChild(img); };
        img.src = url;
      });
    }
  }, { rootMargin: '300px' });
  (raiz || document).querySelectorAll('.poster[data-serie]').forEach((p) => _obsPoster.observe(p));
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
  for (const c of LISTA.canais) if (!visto.has(c.categoria)) { visto.add(c.categoria); out.push(c.categoria); }
  return out;
}
function canaisDaCategoria(cat) {
  return cat === '__fav'
    ? LISTA.canais.filter((c) => _favoritos.has(c.id))
    : LISTA.canais.filter((c) => c.categoria === cat);
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
// Toca uma URL no <video> do preview (reusado na tela cheia). Troca de
// qualidade/fonte chama isto com a URL nova.
function tocarNoPreview(url, muted) {
  const v = document.getElementById('tv-prev-video');
  if (!v || !url) return;
  if (_hlsPrev) { _hlsPrev.destroy(); _hlsPrev = null; }
  const ehHls = /\.m3u8(\?|$)/i.test(url);
  if (ehHls && window.Hls && Hls.isSupported()) {
    _hlsPrev = new Hls();
    _hlsPrev.on(Hls.Events.MANIFEST_PARSED, () => { v.muted = muted; v.play().catch(() => {}); });
    _hlsPrev.attachMedia(v);
    _hlsPrev.loadSource(url);
  } else {
    // .ts e demais: player nativo (em TV real, live .ts pode exigir AVPlay).
    v.muted = muted; v.src = url;
    v.addEventListener('loadedmetadata', () => v.play().catch(() => {}), { once: true });
  }
}
function carregarPreviewVideo() {
  tocarNoPreview((_tvCanalPreview && _tvCanalPreview.url) || TEST_HLS, true);
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
    main.innerHTML = renderMidia(LISTA.catalogo[secaoId]);
    _heroItem = null;           // força o hero a atualizar no 1º foco
    ligarPostersSerie(main);    // pôster TMDB das séries (lazy)
  } else if (secaoId === 'tvaovivo') {
    main.innerHTML = renderTvAoVivo();
  } else if (secaoId === 'playlists') {
    main.innerHTML = renderPlaylists();
    gerarQr('pl-qr', Dispositivo.urlAtivacao());
    const rec = document.getElementById('pl-reload');
    if (rec) rec.addEventListener('click', async () => {
      toast('Verificando…');
      await Dispositivo.consultar();
      navegar('playlists');
    });
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
  ov.innerHTML = `
    <div class="det-bg" id="det-bg" style="background:${gradiente(item.titulo, true)}"></div>
    <div class="det-grad"></div>
    <div class="det-conteudo">
      <div class="det-poster" id="det-poster" style="background:${gradiente(item.titulo, true)}"></div>
      <div class="det-info">
        <h1 class="det-titulo">${escapar(item.titulo)}</h1>
        <div class="hero-meta" id="det-meta"></div>
        <p class="det-sinopse" id="det-sinopse">Carregando…</p>
        <div class="det-elenco" id="det-elenco"></div>
        <div class="hero-acoes">
          <button class="btn btn-primario focusable" data-acao="play"><svg viewBox="0 0 24 24"><path d="M8 5v14l11-7z"/></svg> Assistir</button>
          <button class="btn btn-secundario focusable" data-acao="fechar">Voltar</button>
        </div>
      </div>
    </div>`;
  document.body.appendChild(ov);
  ov._onVoltar = fecharDetalhe;
  ov.querySelector('[data-acao="fechar"]').addEventListener('click', fecharDetalhe);
  ov.querySelector('[data-acao="play"]').addEventListener('click', () => { ov.remove(); abrirPlayer(item); });
  SpatialNav.setFocus(ov.querySelector('.btn-primario'));

  document.getElementById('det-meta').innerHTML = notaHero(item, null);
  if (item.logo) document.getElementById('det-poster').style.background = `#000 center/cover url("${item.logo}")`;

  TMDB.info(item.titulo, item.tipo === 'serie').then(async (inf) => {
    if (!document.getElementById('detalhe-overlay')) return;
    const sin = document.getElementById('det-sinopse');
    if (!inf || inf.vazio) { if (sin) sin.textContent = item.sinopse || 'Sem descrição disponível.'; return; }
    const bg = document.getElementById('det-bg');
    if (inf.backdrop && bg) bg.style.background = `#000 center/cover url("${inf.backdrop}")`;
    if (!item.logo) {
      const pUrl = item.tipo === 'serie' ? await TMDB.poster(item.titulo) : inf.poster;
      const p = document.getElementById('det-poster');
      if (p && pUrl) p.style.background = `#000 center/cover url("${pUrl}")`;
    }
    if (sin) sin.textContent = inf.sinopse || 'Sem descrição disponível.';
    document.getElementById('det-meta').innerHTML = notaHero(item, inf);
    if (inf.id) TMDB.elenco(inf.id, inf.ehTv).then((cast) => {
      const e = document.getElementById('det-elenco');
      if (!e || !cast.length) return;
      e.innerHTML = '<span class="det-elenco-tit">Elenco</span>' +
        cast.slice(0, 6).map((a) => `<span class="det-ator">${escapar(a.nome)}</span>`).join('');
    });
  });
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
    <div class="pc-spinner" id="pc-spinner"></div>
    <div class="pc-erro oculto" id="pc-erro"></div>
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
  const spinner = (mostrar) => { const s = document.getElementById('pc-spinner'); if (s) s.classList.toggle('oculto', !mostrar); };
  const erroPlayer = (msg) => {
    spinner(false);
    const e = document.getElementById('pc-erro');
    if (e) { e.textContent = msg; e.classList.remove('oculto'); }
  };
  video.addEventListener('waiting', () => spinner(true));
  video.addEventListener('loadstart', () => spinner(true));
  video.addEventListener('playing', () => spinner(false));
  video.addEventListener('canplay', () => spinner(false));
  video.addEventListener('error', () => erroPlayer('Não foi possível reproduzir. O formato pode exigir o player nativo da TV.'));

  const fonte = item.url || TEST_HLS;     // URL real do item (fallback: teste)
  const ehHls = /\.m3u8(\?|$)/i.test(fonte);
  spinner(true);
  if (!ehHls || video.canPlayType('application/vnd.apple.mpegurl')) {
    video.src = fonte;                    // arquivo (mp4/ts) ou HLS nativo
  } else if (window.Hls && Hls.isSupported()) {
    _hls = new Hls();
    _hls.on(Hls.Events.ERROR, (_e, d) => { if (d && d.fatal) erroPlayer('Não foi possível reproduzir este conteúdo.'); });
    _hls.loadSource(fonte);
    _hls.attachMedia(video);
  } else {
    video.src = fonte;
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
  if (document.querySelector('.menu-opcoes')) return; // menu de qualidade/fonte tem prioridade
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
  q('qualidade').addEventListener('click', () => {
    if (!canal.variantes || canal.variantes.length < 2) { toast('Sem outras qualidades nesta fonte'); return; }
    abrirMenu('Qualidade', canal.variantes.map((v) => v.rotulo), (i) => tocarNoPreview(canal.variantes[i].url, false));
  });
  q('fontes').addEventListener('click', () => {
    if (!canal.fontes || canal.fontes.length < 2) { toast('Sem outras fontes'); return; }
    abrirMenu('Fontes', canal.fontes.map((f, i) => f.nome || ('Fonte ' + (i + 1))), (i) => {
      const f = canal.fontes[i];
      if (f.variantes && f.variantes.length) canal.variantes = f.variantes; // qualidade segue a fonte
      tocarNoPreview(f.url, false);
    });
  });
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

// Menu de seleção (qualidade/fonte) sobreposto ao player. D-pad: cima/baixo +
// OK; Voltar fecha. onPick recebe o índice escolhido.
function abrirMenu(titulo, rotulos, onPick) {
  const ov = document.createElement('div');
  ov.className = 'nav-modal menu-opcoes';
  ov.innerHTML = `
    <div class="mo-card">
      <div class="mo-titulo">${escapar(titulo)}</div>
      ${rotulos.map((r, i) => `<button class="mo-item focusable" data-i="${i}">${escapar(r)}</button>`).join('')}
    </div>`;
  document.body.appendChild(ov);
  const anterior = SpatialNav.atual;
  const restaurar = () => { if (anterior && document.contains(anterior)) SpatialNav.setFocus(anterior); };
  ov._onVoltar = () => { ov.remove(); restaurar(); };
  ov.querySelectorAll('.mo-item').forEach((b) => b.addEventListener('click', () => {
    const i = +b.dataset.i;
    ov.remove();
    restaurar();
    onPick(i);
  }));
  SpatialNav.setFocus(ov.querySelector('.mo-item'));
}

// ── Onboarding / ativacao ───────────────────────────────────────────────────
const STATUS_PT = { trial: 'Em teste', ativo: 'Ativo', expirado: 'Expirado', sem_lista: 'Sem lista' };

const IC_GLOBO = '<svg viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="1.8"><circle cx="12" cy="12" r="9"/><path d="M3 12h18M12 3c2.6 2.7 2.6 15.3 0 18M12 3c-2.6 2.7-2.6 15.3 0 18"/></svg>';
const IC_USER = '<svg viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="1.8"><circle cx="12" cy="8" r="4"/><path d="M4 21c0-4 4-6 8-6s8 2 8 6"/></svg>';
const IC_LOCK = '<svg viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="1.8"><rect x="4" y="10" width="16" height="11" rx="2"/><path d="M8 10V7a4 4 0 0 1 8 0v3"/></svg>';
const IC_LINK = '<svg viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="1.8"><path d="M10 14a4 4 0 0 0 6 .5l3-3a4 4 0 0 0-6-6l-1 1"/><path d="M14 10a4 4 0 0 0-6-.5l-3 3a4 4 0 0 0 6 6l1-1"/></svg>';

// Gera um QR (SVG, nitido na TV) dentro do elemento de id `elId`.
function gerarQr(elId, dados) {
  const el = document.getElementById(elId);
  if (!el) return;
  try {
    const qr = qrcode(0, 'M');
    qr.addData(dados);
    qr.make();
    el.innerHTML = qr.createSvgTag({ cellSize: 6, margin: 0 });
  } catch (_) {
    el.textContent = 'QR indisponível';
  }
}

// Tela cheia mostrada quando NAO ha lista (app neutro abre vazio — conformidade).
// Layout estilo apps de TV: logo no topo-centro, QR+link a esquerda, login
// (Xtream OU URL M3U) a direita, MAC/Key no rodape.
function mostrarOnboarding() {
  document.getElementById('app').classList.add('oculto');
  let ob = document.getElementById('onboarding');
  if (!ob) {
    ob = document.createElement('div');
    ob.id = 'onboarding';
    ob.className = 'nav-modal';
    document.body.appendChild(ob);
  }
  ob._onVoltar = () => {}; // sem "voltar" no onboarding (e a raiz)
  ob.innerHTML = `
    <div class="ob-wrap ob-grid">
      <div class="ob-top">
        <div class="logo ob-logo"><span class="logo-mark">▶</span><span class="ob-logo-text"><b>Hero</b> Play</span></div>
      </div>

      <div class="ob-left">
        <h2 class="ob-h2">Adicionar Playlist</h2>
        <div class="ob-qr" id="ob-qr"></div>
        <div class="ob-left-txt">Adicione e ative <b>tudo pelo site</b></div>
        <div class="ob-link">heroplaytv.com/upload</div>
        <button class="btn btn-secundario focusable" id="ob-reload">↻ Recarregar</button>
        <div class="ob-ou"><span>ou</span></div>
        <div class="ob-hint">Use as credenciais ou a URL da playlist no formulário ao lado</div>
      </div>

      <div class="ob-right">
        <h2 class="ob-h2 ob-right-h">Entrar com credenciais</h2>
        <div class="ob-tabs">
          <button class="ob-tab focusable ativo" data-modo="xtream">Xtream</button>
          <button class="ob-tab focusable" data-modo="m3u">M3U / URL</button>
        </div>
        <div class="ob-form" id="ob-form-xtream">
          <div class="ob-campo"><span class="ob-ico">${IC_GLOBO}</span><input class="ob-input focusable" id="x-host" placeholder="Servidor (http://host:porta)" autocomplete="off" spellcheck="false"></div>
          <div class="ob-campo"><span class="ob-ico">${IC_USER}</span><input class="ob-input focusable" id="x-user" placeholder="Usuário" autocomplete="off" spellcheck="false"></div>
          <div class="ob-campo"><span class="ob-ico">${IC_LOCK}</span><input class="ob-input focusable" id="x-pass" type="password" placeholder="Senha" autocomplete="off" spellcheck="false"></div>
        </div>
        <div class="ob-form oculto" id="ob-form-m3u">
          <div class="ob-campo"><span class="ob-ico">${IC_LINK}</span><input class="ob-input focusable" id="m-url" placeholder="https://.../lista.m3u" autocomplete="off" spellcheck="false"></div>
        </div>
        <button class="btn btn-primario focusable" id="ob-add">Conectar</button>
        <div class="ob-erro" id="ob-erro"></div>
      </div>
    </div>
    <div class="ob-cred-fixo">
      <div>Key: <b>${Dispositivo.key()}</b></div>
      <div>Mac: <b>${Dispositivo.mac()}</b></div>
    </div>`;
  gerarQr('ob-qr', Dispositivo.urlAtivacao());
  document.getElementById('ob-reload').addEventListener('click', recarregarOnboarding);
  document.getElementById('ob-add').addEventListener('click', onboardingAdicionar);
  ob.querySelectorAll('.ob-tab').forEach((t) =>
    t.addEventListener('click', () => trocarModoOnboarding(t.dataset.modo)));
  SpatialNav.setFocus(document.getElementById('x-host'));
}

function trocarModoOnboarding(modo) {
  document.querySelectorAll('.ob-tab').forEach((t) =>
    t.classList.toggle('ativo', t.dataset.modo === modo));
  document.getElementById('ob-form-xtream').classList.toggle('oculto', modo !== 'xtream');
  document.getElementById('ob-form-m3u').classList.toggle('oculto', modo !== 'm3u');
  const primeiro = (modo === 'xtream') ? 'x-host' : 'm-url';
  SpatialNav.setFocus(document.getElementById(primeiro));
}

// Adiciona a lista digitada no proprio app (Xtream OU M3U). "Traga sua lista":
// sem venda no app — só configura a playlist do cliente. Inicia o teste (trial).
function onboardingAdicionar() {
  const val = (id) => (document.getElementById(id).value || '').trim();
  const erro = (m) => { document.getElementById('ob-erro').textContent = m; };
  const modo = document.querySelector('.ob-tab.ativo')?.dataset.modo || 'xtream';
  let lista_url, epg_url;

  if (modo === 'xtream') {
    const host = val('x-host'), user = val('x-user'), pass = val('x-pass');
    if (!host || !user || !pass) return erro('Preencha servidor, usuário e senha.');
    ({ lista_url, epg_url } = ListaUtil.montarXtream(host, user, pass));
  } else {
    lista_url = val('m-url');
    if (!/^https?:\/\//i.test(lista_url)) return erro('Informe uma URL M3U válida (http/https).');
    epg_url = ListaUtil.derivarEpg(lista_url);
  }

  // Registra na nuvem (best-effort) + grava local, depois carrega a lista.
  const ob = document.getElementById('onboarding');
  if (ob) ob.remove();
  mostrarLoading('Adicionando sua lista…');
  Dispositivo.adicionar(lista_url, epg_url).then(() => iniciarApp());
}

async function recarregarOnboarding() {
  toast('Verificando…');
  await Dispositivo.consultar();
  if (Dispositivo.temLista()) {
    const ob = document.getElementById('onboarding');
    if (ob) ob.remove();
    iniciarApp();
  } else {
    toast('Nenhuma lista ainda. Adicione no celular e tente de novo.');
  }
}

// Aviso grande de periodo de teste (apos a lista ser adicionada e device inativo).
function mostrarAvisoTeste() {
  if (sessionStorage.getItem('aviso_teste_visto')) return;
  const ov = document.createElement('div');
  ov.id = 'aviso-teste';
  ov.className = 'nav-modal';
  ov.innerHTML = `
    <div class="aviso-card">
      <div class="aviso-badge">Período de teste</div>
      <h1 class="aviso-titulo">${Dispositivo.diasTeste()} dias grátis</h1>
      <p class="aviso-sub">Sua lista foi adicionada e o app está em teste. Para continuar
        depois do período, ative o app — você mesmo pode ativar escaneando o QR.</p>
      <div class="ob-qr" id="aviso-qr"></div>
      <div class="aviso-rotulo">Ativar / gerenciar</div>
      <div class="ob-link">heroplaytv.com/upload</div>
      <button class="btn btn-primario focusable" id="aviso-ok">Continuar no teste</button>
    </div>`;
  document.body.appendChild(ov);
  ov._onVoltar = fecharAvisoTeste;
  gerarQr('aviso-qr', Dispositivo.urlAtivacao());
  document.getElementById('aviso-ok').addEventListener('click', fecharAvisoTeste);
  SpatialNav.setFocus(document.getElementById('aviso-ok'));
}
function fecharAvisoTeste() {
  sessionStorage.setItem('aviso_teste_visto', '1');
  const ov = document.getElementById('aviso-teste');
  if (ov) ov.remove();
  const f = document.querySelector('#conteudo .focusable');
  if (f) SpatialNav.setFocus(f);
}

// Seção Playlists: mostra a lista atual + QR para adicionar/trocar.
function renderPlaylists() {
  const r = Dispositivo.registro();
  const tem = Dispositivo.temLista();
  const corpoLista = tem
    ? `<div class="pl-ok">✓ Lista configurada</div>
       <div class="pl-url">${escapar(r.lista_url)}</div>
       ${r.epg_url ? `<div class="pl-epg">EPG: ${escapar(r.epg_url)}</div>` : ''}
       <div class="pl-status">Status: <b>${STATUS_PT[Dispositivo.status()] || Dispositivo.status()}</b></div>`
    : `<div class="pl-vazio">Nenhuma lista configurada</div>`;
  return `<div class="secao secao-pl">
    <h2 class="titulo-secao">Sua lista</h2>
    <div class="pl-card">
      ${corpoLista}
      <p class="pl-add">Para adicionar ou trocar a lista, escaneie o QR com o celular:</p>
      <div class="pl-grid">
        <div class="ob-qr" id="pl-qr"></div>
        <div class="ob-cred">
          <div><span>MAC</span><b>${Dispositivo.mac()}</b></div>
          <div><span>Key</span><b>${Dispositivo.key()}</b></div>
        </div>
      </div>
      <button class="btn btn-secundario focusable" id="pl-reload">↻ Recarregar</button>
    </div>
  </div>`;
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
    const c = LISTA.canais.find((x) => x.id === canalItem.dataset.canal);
    if (c) selecionarPreview(c);
    return;
  }
  const tela = e.target.closest('.tv-tela');
  if (tela) { if (_tvCanalPreview) abrirLive(_tvCanalPreview); return; }
  const favBtn = e.target.closest('.tv-fav-btn');
  if (favBtn) { if (_tvCanalPreview) alternarFavorito(_tvCanalPreview.id); return; }
  const poster = e.target.closest('.poster');
  if (poster) {
    const item = LISTA.indice[poster.dataset.id];
    if (item) abrirDetalhe(item);
    return;
  }
  const assistir = e.target.closest('[data-acao="assistir"]');
  if (assistir) {
    const item = LISTA.indice[assistir.dataset.id];
    if (item) abrirDetalhe(item);
  }
});

// ── Tela de loading (logo + barra em movimento; nao congela) ────────────────
function mostrarLoading(msg) {
  let el = document.getElementById('loading');
  if (!el) { el = document.createElement('div'); el.id = 'loading'; document.body.appendChild(el); }
  el.innerHTML = `
    <div class="ld-card">
      <div class="logo ld-logo"><span class="logo-mark">▶</span><span class="ob-logo-text"><b>Hero</b> Play</span></div>
      <div class="ld-barra"><span></span></div>
      <div class="ld-msg" id="ld-msg">${escapar(msg || 'Carregando…')}</div>
    </div>`;
  el.style.display = 'grid';
}
function loadingMsg(m) { const e = document.getElementById('ld-msg'); if (e) e.textContent = m; }
function esconderLoading() { const el = document.getElementById('loading'); if (el) el.remove(); }

// Baixa + parseia a lista do dispositivo e aplica ao catálogo. O parse roda
// após um frame (a barra continua animando). Retorna true se carregou.
async function carregarLista(url) {
  if (!url) return false;
  try {
    const resp = await fetch(url);
    if (!resp.ok) throw new Error('HTTP ' + resp.status);
    const txt = await resp.text();
    loadingMsg('Organizando seus canais…');
    await new Promise((r) => requestAnimationFrame(r)); // deixa a UI respirar
    const parsed = Lista.parse(txt);
    if (!parsed.canais.length && !parsed.filmes.length && !parsed.series.length) {
      throw new Error('lista vazia ou formato não reconhecido');
    }
    aplicarLista(parsed);
    return true;
  } catch (e) {
    console.warn('[Hero Play] falha ao carregar lista:', e);
    return false;
  }
}

async function iniciarApp() {
  document.getElementById('app').classList.remove('oculto');
  const reg = Dispositivo.registro();
  if (reg && reg.lista_url) {
    mostrarLoading('Baixando sua lista…');
    const ok = await carregarLista(reg.lista_url);
    esconderLoading();
    if (!ok) toast('Não foi possível carregar sua lista. Verifique a URL/conexão.');
  }
  navegar('inicio');
  if (Dispositivo.status() === 'trial') mostrarAvisoTeste();
}

window.addEventListener('DOMContentLoaded', async () => {
  montarSidebar();
  // Hero reage ao item em foco (Início/Filmes/Séries).
  SpatialNav.aoFocar((el) => {
    if (el && el.classList && el.classList.contains('poster')) {
      const it = LISTA.indice[el.dataset.id];
      if (it) atualizarHero(it);
    }
  });
  await Dispositivo.consultar(); // best-effort (offline-first)
  if (Dispositivo.temLista()) iniciarApp();
  else mostrarOnboarding(); // app neutro: abre vazio ate ter lista (conformidade)
});
