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
  // Filme: usa o logo/poster da própria lista. Série: o "logo" é o thumbnail do
  // 1º episódio (feio/pixelado) — então busca o PÔSTER no TMDB (lazy). Se o TMDB
  // não tiver pôster, fica SÓ o nome (gradiente) — NÃO usa o thumb do episódio.
  // Filme sem logo também cai no TMDB.
  const ehSerie = item.tipo === 'serie';
  const usarLogo = !!item.logo && !ehSerie;
  const lazy = !usarLogo ? ` data-tmdb="${escapar(item.titulo)}"` : '';
  const img = usarLogo
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
      <img class="hero2-logo" id="hero2-logo" alt="">
      <h1 class="hero2-titulo" id="hero2-titulo"></h1>
      <div class="hero2-meta" id="hero2-meta"></div>
      <p class="hero2-sinopse" id="hero2-sinopse"></p>
    </div>
  </div>`;
}
function renderMidia(cfg, secaoId) {
  if (!cfg.trilhos.length) {
    return `<div class="secao">${renderPlaceholder('Nada por aqui', 'Sua lista não tem itens nesta seção.')}</div>`;
  }
  // Botão de busca da seção (só Filmes/Séries) — canto superior direito.
  const btnBusca = (secaoId === 'filmes' || secaoId === 'series')
    ? `<button class="midia-busca focusable" data-acao="busca-secao" data-escopo="${secaoId}" aria-label="Buscar nesta seção">${IC_BUSCA_LUPA}</button>`
    : '';
  return `<div class="midia">
    ${heroFixoHTML()}
    <div class="trilhos">${cfg.trilhos.map(trilhoHTML).join('')}</div>
    ${btnBusca}
  </div>`;
}

// ── Hero dinâmico (reflete o item em foco; metadados via TMDB) ───────────────
let _heroItem = null, _heroToken = 0, _heroTimer = null, _heroBgAtivo = 'A';
let _heroPendente = null, _heroDebounce = null;
const HERO_DELAY = 320; // só troca o hero após o foco ficar parado > ~0,3s

function notaHero(item, inf) {
  const nota = (inf && inf.nota) || (item.nota > 0 ? item.nota : null);
  const ano = (inf && inf.ano) || (item.ano || null);
  const partes = [];
  if (ano) partes.push(`<span>${ano}</span>`);
  if (nota) partes.push(`<span class="nota">★ ${Number(nota).toFixed(1)}</span>`);
  for (const g of (item.generos || [])) partes.push(`<span class="selo">${escapar(g)}</span>`);
  return partes.join('');
}
let _bgToken = 0;
function setHeroBg(val, blur) {
  if (!val) return;
  const ativoEhA = _heroBgAtivo === 'A';
  const ativo = document.getElementById(ativoEhA ? 'hero2-bgA' : 'hero2-bgB'); // visível agora
  const novo = document.getElementById(ativoEhA ? 'hero2-bgB' : 'hero2-bgA');  // entra agora
  if (!ativo || !novo) return;
  novo.style.backgroundImage = /^(linear|radial)-gradient/.test(val) ? val : `url("${val}")`;
  novo.classList.toggle('blur', !!blur);
  // O NOVO entra POR CIMA e faz fade-in; o ATIVO continua opaco por baixo até ser
  // coberto. Antes era um crossfade simultâneo (ambos cruzavam ~0.5 de opacidade)
  // → abria um "buraco" transparente deixando ver os trilhos atrás. Agora não.
  novo.style.zIndex = '1';
  ativo.style.zIndex = '0';
  novo.classList.add('on');
  const meu = ++_bgToken;
  // Depois do fade, apaga o antigo (já coberto → invisível) p/ ele voltar a 0 e
  // poder ser o próximo a entrar. Token cancela se houver outra troca antes.
  setTimeout(() => { if (meu === _bgToken) ativo.classList.remove('on'); }, 580);
  _heroBgAtivo = ativoEhA ? 'B' : 'A';
}
// Fundo padrão (cores do Hero Play) quando o TMDB não tem backdrop horizontal.
const FUNDO_PADRAO =
  'radial-gradient(1100px 560px at 22% 12%, rgba(229,57,53,.28), transparent 60%), ' +
  'linear-gradient(125deg, #241312 0%, #0F0E0D 62%)';

// Define o fundo do hero: backdrop horizontal do TMDB se houver; senão o fundo
// padrão Hero Play. Sempre troca (nunca herda o fundo do item anterior).
function definirFundoHero(item, inf) {
  setHeroBg((inf && inf.backdrop) ? inf.backdrop : FUNDO_PADRAO, false);
}
// Aplica backdrop + sinopse + meta + logo-título ao hero (token evita corrida).
function aplicarHeroInfo(item, inf, tok) {
  if (!inf || inf.vazio || tok !== _heroToken) return;
  definirFundoHero(item, inf);
  const sin = document.getElementById('hero2-sinopse'); if (sin) sin.textContent = inf.sinopse || item.sinopse || '';
  const meta = document.getElementById('hero2-meta'); if (meta) meta.innerHTML = notaHero(item, inf);
  if (!inf.id) return;
  const logoEl = document.getElementById('hero2-logo');
  const titulo = document.getElementById('hero2-titulo');
  const aplicaLogo = (lg) => {
    if (tok !== _heroToken || !lg || !logoEl) return;
    const mostrar = () => { if (tok === _heroToken) { logoEl.style.display = 'block'; if (titulo) titulo.style.display = 'none'; } };
    logoEl.onload = mostrar;
    logoEl.src = lg;
    // Pré-carregado (imagem já no cache do browser) → aparece NA HORA, sem o
    // flash de "título em texto" antes do logo (onload pode nem disparar se já
    // estiver completa).
    if (logoEl.complete && logoEl.naturalWidth > 0) mostrar();
  };
  const cached = TMDB.logoCache(inf.id, inf.ehTv);
  if (cached !== null) aplicaLogo(cached);
  else TMDB.tituloLogo(inf.id, inf.ehTv).then(aplicaLogo);
}
// Agenda a troca do hero com DEBOUNCE: o painel fica no item atual até o usuário
// parar num NOVO item por > HERO_DELAY; só então anima a troca. Em foco rápido
// (rolando os trilhos) nada muda — evita o "corte seco" a cada item.
function atualizarHero(item) {
  if (!item) return;
  // Já é o item exibido e não há troca pendente → nada a fazer.
  if (_heroItem === item.id && _heroPendente === null) {
    clearTimeout(_heroDebounce); _heroDebounce = null; _heroPendente = null;
    return;
  }
  // 1ª vez na seção (hero ainda vazio) → preenche já, sem esperar.
  if (_heroItem === null) {
    clearTimeout(_heroDebounce); _heroDebounce = null; _heroPendente = null;
    aplicarHero(item);
    return;
  }
  _heroPendente = item;
  clearTimeout(_heroDebounce);
  _heroDebounce = setTimeout(() => {
    _heroDebounce = null;
    const alvo = _heroPendente; _heroPendente = null;
    if (alvo) aplicarHero(alvo); // aplicarHero ignora se já for o item exibido
  }, HERO_DELAY);
}

// Aplica de fato o hero do item (texto/meta + backdrop/logo via TMDB), com a
// animação de troca. Chamado só quando o foco assenta (ver atualizarHero).
function aplicarHero(item) {
  const titulo = document.getElementById('hero2-titulo');
  if (!titulo || !item || _heroItem === item.id) return;
  _heroItem = item.id;
  const tok = ++_heroToken;
  const ehSerie = item.tipo === 'serie';

  // Texto/meta imediatos.
  const logoEl = document.getElementById('hero2-logo');
  if (logoEl) { logoEl.style.display = 'none'; logoEl.removeAttribute('src'); }
  titulo.style.display = '';
  titulo.textContent = item.titulo;
  document.getElementById('hero2-meta').innerHTML = notaHero(item, null);
  document.getElementById('hero2-sinopse').textContent = item.sinopse || '';
  const info = document.getElementById('hero2-info');
  if (info) { info.classList.remove('hero-anim'); void info.offsetWidth; info.classList.add('hero-anim'); }

  // Se já está em cache (pré-carregado), aplica NA HORA (sem o flash de texto→foto).
  const infC = TMDB.infoCache(item.titulo, ehSerie);
  if (infC && !infC.vazio) { aplicarHeroInfo(item, infC, tok); return; }

  // Não cacheado: fundo neutro DO ITEM enquanto busca (nunca o do anterior).
  definirFundoHero(item, null);

  clearTimeout(_heroTimer);
  _heroTimer = setTimeout(async () => {
    const inf = await TMDB.info(item.titulo, ehSerie);
    aplicarHeroInfo(item, inf, tok);
  }, 180);
}

// Foco num pôster: scroll horizontal (fila) + vertical (título do trilho sob o
// hero fixo) — sem isso o primeiro trilho não subia e o título sumia.
function focarPoster(el) {
  const fila = el.closest('.trilho-fila');
  if (fila) {
    const r = el.getBoundingClientRect(), fr = fila.getBoundingClientRect();
    fila.scrollTo({ left: fila.scrollLeft + (r.left - fr.left) - fr.width / 2 + r.width / 2, behavior: 'smooth' });
  }
  const cont = document.getElementById('conteudo');
  const trilho = el.closest('.trilho');
  const hero = document.getElementById('hero2');
  if (cont && trilho) {
    const heroH = hero ? hero.offsetHeight : 0;
    // +60: deixa o título ABAIXO do gradiente de transição (não escurecido).
    const delta = trilho.getBoundingClientRect().top - cont.getBoundingClientRect().top - heroH - 60;
    cont.scrollBy({ top: delta, behavior: 'smooth' });
  }
}

const _aquece = (u) => { if (u) { const im = new Image(); im.src = u; } };

// Itens INICIAIS (primeiros de cada trilho) de TODAS as seções com hero
// (Início/Filmes/Séries), em ordem de exibição e sem repetir. São os que o
// usuário tende a focar primeiro — pré-carregamos o hero (backdrop + logo-título)
// deles ANTES de abrir, p/ o foco já mostrar a imagem de título (sem flash).
function _itensIniciaisDeExibicao(porTrilho) {
  const cat = LISTA.catalogo || {}, visto = new Set(), out = [];
  const coletar = (sec) => {
    for (const t of (sec && sec.trilhos || [])) {
      const itens = t.itens || [];
      for (let i = 0; i < itens.length && i < porTrilho; i++) {
        const it = itens[i];
        if (it && !visto.has(it.id)) { visto.add(it.id); out.push(it); }
      }
    }
  };
  coletar(cat.inicio); coletar(cat.filmes); coletar(cat.series);
  return out;
}

// Pré-carrega o HERO de um item: info (backdrop/nota/sinopse) + logo-título PNG,
// e AQUECE as imagens (backdrop + logo) no cache do browser. Assim o hero aparece
// instantâneo ao focar — sem o "título em texto" piscando antes da imagem.
async function _precarregarHero(item) {
  const inf = await TMDB.info(item.titulo, item.tipo === 'serie');
  if (!inf || inf.vazio) return;
  _aquece(inf.backdrop);
  if (inf.id) { const lg = await TMDB.tituloLogo(inf.id, inf.ehTv); _aquece(lg); }
}

// Executa uma fila de tarefas (funções que retornam Promise) com CONCORRÊNCIA
// LIMITADA (evita o rate-limit do TMDB que deixava itens sem banner). Resolve
// quando tudo termina; cancela se `valido()` passar a ser falso.
function _executarFila(tarefas, conc, valido) {
  return new Promise((resolve) => {
    let i = 0, ativos = 0, fechado = false;
    const fim = () => { if (!fechado && ativos === 0 && i >= tarefas.length) { fechado = true; resolve(); } };
    (function pump() {
      if (valido && !valido()) { if (!fechado) { fechado = true; resolve(); } return; }
      while (ativos < conc && i < tarefas.length) {
        ativos++;
        Promise.resolve(tarefas[i++]()).catch(() => {}).finally(() => { ativos--; fim(); setTimeout(pump, 30); });
      }
      fim();
    })();
  });
}

// Pré-carrega o PÔSTER de um item (o que aparece nos trilhos), aquecendo o cache
// do browser. Filme com logo próprio → aquece a URL da lista; série/filme sem
// logo → pôster do TMDB. Cobre TUDO (filmes E séries), não só séries.
function _precarregarPoster(it) {
  if (it.tipo !== 'serie' && it.logo) { _aquece(it.logo); return Promise.resolve(); }
  return TMDB.poster(it.titulo).then(_aquece);
}

// Concorrência das filas de preload (equilíbrio: rápido sem estourar o rate-limit
// do TMDB, que deixava itens sem banner).
const PRELOAD_CONC = 5;

// 1) Pré-carrega (AGUARDANDO, com teto) o HERO dos itens iniciais + os PÔSTERES
//    do topo de TODAS as seções (filmes E séries) — p/ rolar um pouco já achar
//    carregado. 2) Quando termina, dispara o RESTO (tudo) em background. O teto
//    só libera a tela de loading; o preload continua rodando.
async function precarregarBanners() {
  const iniciais = _itensIniciaisDeExibicao(10);     // hero dos 1ºs de cada trilho
  const feitosHero = new Set(iniciais.map((it) => it.id));
  const postersTopo = _itensIniciaisDeExibicao(18);  // pôster dos 1ºs de cada trilho
  const prioridade = [
    ...iniciais.map((it) => () => _precarregarHero(it)),
    ...postersTopo.map((it) => () => _precarregarPoster(it)),
  ];
  // O fundo só começa DEPOIS da prioridade (não soma concorrência em cima dela).
  const tudo = _executarFila(prioridade, PRELOAD_CONC).then(() => precarregarFundo(feitosHero));
  await Promise.race([tudo, new Promise((r) => setTimeout(r, 9000))]); // teto do loading
}

// Background: PÔSTER de TUDO (filmes + séries) + hero (backdrop/logo) dos demais,
// com concorrência limitada. Garante que o catálogo inteiro fique pré-carregado.
let _fundoToken = 0;
function precarregarFundo(idsHeroFeitos) {
  const meu = ++_fundoToken;
  const feitos = idsHeroFeitos || new Set();
  const todos = [...(LISTA.filmes || []), ...(LISTA.series || [])];
  const tarefas = [
    ...todos.map((it) => () => _precarregarPoster(it)),                       // pôster de tudo
    ...todos.filter((it) => !feitos.has(it.id)).map((it) => () => _precarregarHero(it)), // hero dos demais
  ];
  return _executarFila(tarefas, PRELOAD_CONC, () => meu === _fundoToken);
}

// Lazy: pôster TMDB ao entrar na viewport (com margem grande p/ carregar bem
// ANTES de aparecer). Usa o cache NA HORA (pré-carregado); senão busca. Sem
// imagem do TMDB → fica só o nome (gradiente), NUNCA o thumb do episódio.
let _obsPoster = null;
function ligarPostersSerie(raiz) {
  if (!('IntersectionObserver' in window)) return;
  if (_obsPoster) _obsPoster.disconnect();
  const aplicar = (el, url) => {
    const arte = el.querySelector('.poster-arte');
    // já tem imagem OU já está carregando (re-observado num diff) → não duplica.
    if (!arte || arte.classList.contains('tem-img') || arte.dataset.carregando) return;
    if (!url) return;   // sem pôster no TMDB → mantém o nome no gradiente
    arte.dataset.carregando = '1';
    const img = new Image();
    img.className = 'poster-img';
    img.onload = () => { arte.classList.add('tem-img'); arte.appendChild(img); };
    img.onerror = () => { delete arte.dataset.carregando; };
    img.src = url;
  };
  _obsPoster = new IntersectionObserver((ents) => {
    for (const e of ents) {
      if (!e.isIntersecting) continue;
      const el = e.target; _obsPoster.unobserve(el);
      const cache = TMDB.posterCache(el.dataset.tmdb);   // pré-carregado → instantâneo
      if (cache !== null) aplicar(el, cache);
      else TMDB.poster(el.dataset.tmdb).then((u) => aplicar(el, u));
    }
  }, { rootMargin: '1600px' });   // carrega ~1,5 tela à frente (rolar um pouco já está pronto)
  (raiz || document).querySelectorAll('.poster[data-tmdb]').forEach((p) => _obsPoster.observe(p));
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

// ── Busca (teclado on-screen + resultados em grade de 5) ────────────────────
let _buscaQuery = '';
const IC_BUSCA_LUPA = '<svg viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="2" stroke-linecap="round"><circle cx="11" cy="11" r="7"/><path d="m21 21-4.3-4.3"/></svg>';
const IC_BUSCA_DEL = '<svg viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="2" stroke-linecap="round" stroke-linejoin="round"><path d="M21 6H8l-5 6 5 6h13a1 1 0 0 0 1-1V7a1 1 0 0 0-1-1z"/><path d="m15 9-4 6M11 9l4 6"/></svg>';

// Normaliza p/ comparação: sem acento, minúsculo (case-insensitive), sem
// pontuação (':', '-', etc. viram espaço), espaço simples.
function normBusca(s) {
  return (s || '').normalize('NFD').replace(/[̀-ͯ]/g, '')
    .toLowerCase().replace(/[^a-z0-9\s]/g, ' ').replace(/\s+/g, ' ').trim();
}

// Alvos de busca de um item: título da LISTA + nome TRADUZIDO e nome ORIGINAL do
// TMDB (quando já em cache do preload) → acha por referência/tradução (ex.: anime
// que na lista vem em inglês/japonês, mas o usuário busca o nome em PT, ou vice).
function alvosBusca(it) {
  const alvos = [it.titulo];
  const inf = TMDB.infoCache(it.titulo, it.tipo === 'serie');
  if (inf && !inf.vazio) { if (inf.nome) alvos.push(inf.nome); if (inf.original) alvos.push(inf.original); }
  return alvos;
}
// Casa se a query for substring de qualquer alvo — comparando normal E sem espaços
// (assim ":" / "-" não atrapalham: "spiderman" acha "Spider-Man", "round6" acha
// "Round 6"). Case-insensitive via normBusca.
function casaBusca(it, nq, nqSemEsp) {
  for (const alvo of alvosBusca(it)) {
    const a = normBusca(alvo);
    if (a.includes(nq)) return true;
    if (nqSemEsp && a.replace(/\s+/g, '').includes(nqSemEsp)) return true;
  }
  return false;
}

// Teclado: a-z + 1-9 0 (6 por linha, igual à referência) + Apagar/Espaço/Limpar.
const BUSCA_TECLAS = 'abcdefghijklmnopqrstuvwxyz1234567890';
function renderBuscar() {
  _buscaQuery = '';
  const teclas = [...BUSCA_TECLAS].map((c) =>
    `<button class="bsc-key focusable" data-k="${c}">${c}</button>`).join('');
  return `<div class="bsc">
    <div class="bsc-esq">
      <h2 class="bsc-titulo">Buscar</h2>
      <div class="bsc-input">
        <span class="bsc-input-ico">${IC_BUSCA_LUPA}</span>
        <span class="bsc-campo"><span class="bsc-q" id="bsc-q"></span><span class="bsc-caret"></span><span class="bsc-ph" id="bsc-ph">Buscar…</span></span>
      </div>
      <div class="bsc-teclado">
        ${teclas}
        <button class="bsc-key bsc-key-acao focusable" data-acao="apagar">${IC_BUSCA_DEL}</button>
        <button class="bsc-key bsc-key-acao focusable" data-acao="espaco">Espaço</button>
        <button class="bsc-key bsc-key-acao focusable" data-acao="limpar">Limpar</button>
      </div>
    </div>
    <div class="bsc-dir" id="bsc-dir">${htmlBuscaVazia()}</div>
  </div>`;
}

function htmlBuscaVazia() {
  return `<div class="bsc-vazio">
    <div class="bsc-vazio-ico">${IC_BUSCA_LUPA}</div>
    <div class="bsc-vazio-titulo">Encontre seus filmes e séries</div>
    <div class="bsc-vazio-sub">Digite o nome no teclado ao lado para começar</div>
  </div>`;
}
function htmlBuscaSemResultado(q) {
  return `<div class="bsc-vazio">
    <div class="bsc-vazio-ico">${IC_BUSCA_LUPA}</div>
    <div class="bsc-vazio-titulo">Nada encontrado para “${escapar(q)}”</div>
    <div class="bsc-vazio-sub">Confira a digitação ou tente outro título</div>
  </div>`;
}

// Filtra filmes + séries da lista pelo título (sem acento) e desenha em grade.
function atualizarBusca() {
  const q = _buscaQuery;
  const span = document.getElementById('bsc-q'); if (span) span.textContent = q;
  const ph = document.getElementById('bsc-ph'); if (ph) ph.style.display = q ? 'none' : '';
  const dir = document.getElementById('bsc-dir'); if (!dir) return;
  const nq = normBusca(q);
  if (!nq) { dir.innerHTML = htmlBuscaVazia(); return; }
  const nqSemEsp = nq.replace(/\s+/g, '');
  const itens = [...(LISTA.filmes || []), ...(LISTA.series || [])]
    .filter((it) => casaBusca(it, nq, nqSemEsp))
    .slice(0, 60);
  aplicarResultados(dir, itens, q);
}

// Atualiza a GRADE por DIFF (sem reconstruir tudo → sem "piscar"): mantém os
// pôsteres já mostrados, remove os que não casam mais, e adiciona/reordena o resto.
function aplicarResultados(dir, itens, q) {
  if (!itens.length) { dir.innerHTML = htmlBuscaSemResultado(q); return; }
  let grid = dir.querySelector('.bsc-grid');
  if (!grid) { dir.innerHTML = '<div class="bsc-grid"></div>'; grid = dir.querySelector('.bsc-grid'); }
  const querSet = new Set(itens.map((it) => it.id));
  for (const p of [...grid.querySelectorAll('.poster')]) if (!querSet.has(p.dataset.id)) p.remove();
  const existentes = {};
  for (const p of grid.querySelectorAll('.poster')) existentes[p.dataset.id] = p;
  let anterior = null;
  for (const it of itens) {
    let el = existentes[it.id];
    if (!el) { const tmp = document.createElement('div'); tmp.innerHTML = posterHTML(it); el = tmp.firstElementChild; }
    const ref = anterior ? anterior.nextElementSibling : grid.firstElementChild;
    if (el !== ref) grid.insertBefore(el, ref);   // só move se preciso (não recria → não pisca)
    anterior = el;
  }
  ligarPostersSerie(dir);   // observa os NOVOS (os já com imagem são ignorados)
}

// Indexa os APELIDOS p/ a busca por referência: carrega do TMDB o nome traduzido/
// original dos `itens` ainda sem cache e, conforme chegam, chama reRender (throttle)
// — assim "bunny girl senpai" acha "Seishun Buta Yarou..." pelo nome "Rascal Does
// Not Dream of Bunny Girl Senpai". A digitação continua 100% local; isto só
// preenche os apelidos em background. Para quando `ativo()` vira falso.
let _buscaIdxTok = 0;
function indexar(itens, reRender, ativo) {
  const meu = ++_buscaIdxTok;
  const pend = itens.filter((it) => TMDB.infoCache(it.titulo, it.tipo === 'serie') === null);
  if (!pend.length) return;
  let agendado = false;
  const vivo = () => meu === _buscaIdxTok && (!ativo || ativo());
  const aviso = () => {
    if (agendado || !vivo()) return;
    agendado = true;
    setTimeout(() => { agendado = false; if (vivo()) reRender(); }, 350);
  };
  const tarefas = pend.map((it) => () => TMDB.info(it.titulo, it.tipo === 'serie').then(aviso, () => {}));
  _executarFila(tarefas, 3, vivo);
}

// Liga os cliques do teclado on-screen, zera a busca e inicia a indexação.
function ligarBuscar(raiz) {
  _buscaQuery = '';
  raiz.querySelectorAll('.bsc-key').forEach((k) => k.addEventListener('click', () => {
    const a = k.dataset.acao;
    if (a === 'apagar') _buscaQuery = _buscaQuery.slice(0, -1);
    // Espaço: nunca no início nem dois seguidos (evita espaços "fantasma" que não
    // aparecem mas precisam de backspace depois).
    else if (a === 'espaco') { if (_buscaQuery && !_buscaQuery.endsWith(' ')) _buscaQuery += ' '; }
    else if (a === 'limpar') _buscaQuery = '';
    else _buscaQuery += k.dataset.k;
    atualizarBusca();
  }));
  indexar([...(LISTA.series || []), ...(LISTA.filmes || [])], atualizarBusca, () => !!document.getElementById('bsc-dir'));
}

// Busca DENTRO de uma seção (Filmes ou Séries): mesma tela da busca, mas só com os
// itens daquela seção + as CATEGORIAS dela abaixo do teclado (navegáveis). Abre com
// animação de "lupa tomando a tela" (círculo expandindo do botão) e fecha ao contrário.
function abrirBuscaSecao(escopo, btn) {
  const itensEscopo = (escopo === 'series') ? (LISTA.series || []) : (LISTA.filmes || []);
  const cats = (((LISTA.catalogo || {})[escopo] || {}).trilhos || []).map((t) => t.titulo);
  const titulo = escopo === 'series' ? 'Buscar em Séries' : 'Buscar em Filmes';
  let query = '', catSel = null;

  const teclas = [...BUSCA_TECLAS].map((c) => `<button class="bsc-key focusable" data-k="${c}">${c}</button>`).join('')
    + `<button class="bsc-key bsc-key-acao focusable" data-acao="apagar">${IC_BUSCA_DEL}</button>`
    + `<button class="bsc-key bsc-key-acao focusable" data-acao="espaco">Espaço</button>`
    + `<button class="bsc-key bsc-key-acao focusable" data-acao="limpar">Limpar</button>`;
  const catsHTML = [`<button class="bsc-cat focusable ativa" data-cat="">Todos</button>`,
    ...cats.map((c) => `<button class="bsc-cat focusable" data-cat="${escapar(c)}">${escapar(c)}</button>`)].join('');

  const ov = document.createElement('div');
  ov.className = 'nav-modal busca-secao';
  ov.innerHTML = `
    <div class="bs-reveal"></div>
    <div class="bs-conteudo">
      <div class="bsc">
        <div class="bsc-esq">
          <h2 class="bsc-titulo">${titulo}</h2>
          <div class="bsc-input">
            <span class="bsc-input-ico">${IC_BUSCA_LUPA}</span>
            <span class="bsc-campo"><span class="bsc-q" id="bs-q"></span><span class="bsc-caret"></span><span class="bsc-ph" id="bs-ph">Buscar…</span></span>
          </div>
          <div class="bsc-teclado">${teclas}</div>
          <div class="bsc-cats">${catsHTML}</div>
        </div>
        <div class="bsc-dir" id="bs-dir"></div>
      </div>
    </div>`;
  document.body.appendChild(ov);
  ov._onVoltar = fechar;

  // Geometria do reveal (lupa que abre) — origem no botão, RELATIVA ao overlay (que
  // começa após a sidebar). O círculo cresce até cobrir a área de conteúdo.
  const ovR = ov.getBoundingClientRect();
  const br = btn.getBoundingClientRect();
  const rx = (br.left + br.width / 2) - ovR.left, ry = (br.top + br.height / 2) - ovR.top;
  const maxDist = Math.max(Math.hypot(rx, ry), Math.hypot(ovR.width - rx, ry), Math.hypot(rx, ovR.height - ry), Math.hypot(ovR.width - rx, ovR.height - ry));
  const base = 120;
  ov.style.setProperty('--bs-esc', (2 * maxDist) / base + 0.4);
  const rev = ov.querySelector('.bs-reveal');
  rev.style.left = (rx - base / 2) + 'px';
  rev.style.top = (ry - base / 2) + 'px';

  function fechar() {
    ++_buscaIdxTok;                  // para a indexação desta seção
    ov.classList.remove('aberto');   // anima ao contrário (lupa encolhe)
    setTimeout(() => {
      ov.remove();
      const cont = document.getElementById('conteudo');
      if (cont) ligarPostersSerie(cont);   // re-observa os pôsteres da seção por baixo
      if (btn && document.contains(btn)) SpatialNav.setFocus(btn);
    }, 430);
  }
  function render() {
    const dir = document.getElementById('bs-dir'); if (!dir) return;
    const nq = normBusca(query), nqSemEsp = nq.replace(/\s+/g, '');
    let itens = itensEscopo;
    if (catSel) itens = itens.filter((it) => (it.generos && it.generos[0]) === catSel);
    if (nq) itens = itens.filter((it) => casaBusca(it, nq, nqSemEsp));
    aplicarResultados(dir, itens.slice(0, 60), query);
  }
  ov.querySelectorAll('.bsc-key').forEach((k) => k.addEventListener('click', () => {
    const a = k.dataset.acao;
    if (a === 'apagar') query = query.slice(0, -1);
    else if (a === 'espaco') { if (query && !query.endsWith(' ')) query += ' '; }
    else if (a === 'limpar') query = '';
    else query += k.dataset.k;
    document.getElementById('bs-q').textContent = query;
    document.getElementById('bs-ph').style.display = query ? 'none' : '';
    render();
  }));
  ov.querySelectorAll('.bsc-cat').forEach((c) => c.addEventListener('click', () => {
    catSel = c.dataset.cat || null;
    ov.querySelectorAll('.bsc-cat').forEach((x) => x.classList.toggle('ativa', x === c));
    render();
  }));

  requestAnimationFrame(() => requestAnimationFrame(() => ov.classList.add('aberto'))); // anima a entrada
  render();
  indexar(itensEscopo, render, () => document.body.contains(ov)); // apelidos da seção (re-filtra ao chegar)
  SpatialNav.setFocus(ov.querySelector('.bsc-key'));
}

// ── Roteamento entre secoes ─────────────────────────────────────────────────
function navegar(secaoId) {
  pararPreview(); // para o preview da TV ao vivo ao sair da secao
  const bsAberta = document.querySelector('.busca-secao'); if (bsAberta) bsAberta.remove(); // fecha a busca de seção ao trocar de seção
  clearTimeout(_heroDebounce); _heroDebounce = null; _heroPendente = null; // cancela troca de hero pendente
  document.querySelectorAll('.nav-item').forEach((n) =>
    n.classList.toggle('ativo', n.dataset.secao === secaoId));

  const main = document.getElementById('conteudo');
  if (secaoId === 'inicio' || secaoId === 'filmes' || secaoId === 'series') {
    main.innerHTML = renderMidia(LISTA.catalogo[secaoId], secaoId);
    _heroItem = null;                              // força o hero a atualizar no 1º foco
    ligarPostersSerie(main);                       // pôster TMDB (cache-first; lazy ao rolar)
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
    main.innerHTML = renderBuscar();
    ligarBuscar(main);
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
// ── Detalhe (pós-seleção) — estilo GTV melhorado ────────────────────────────
const _reEpA = /\bS(\d{1,2})\s?E(\d{1,3})\b/i;
const _reEpB = /\b(\d{1,2})x(\d{2,3})\b/;
function epInfo(nome) { const m = nome.match(_reEpA) || nome.match(_reEpB); return { s: m ? +m[1] : 1, e: m ? +m[2] : 0 }; }
function epsOrdenados(item) { return [...(item.episodios || [])].sort((a, b) => { const A = epInfo(a.nome), B = epInfo(b.nome); return A.s - B.s || A.e - B.e; }); }
function primeiroEp(item) { return epsOrdenados(item)[0]; }
function primeiroEpLabel(item) { const ep = primeiroEp(item); if (!ep) return ''; const { s, e } = epInfo(ep.nome); return `T${s}:E${e}`; }
function rotuloEp(item, ep) { const { s, e } = epInfo(ep.nome); return `${item.titulo} — T${s} E${String(e).padStart(2, '0')}`; }
function estrelas(n10) { const n = Math.max(0, Math.min(5, Math.round((n10 || 0) / 2))); return '★'.repeat(n) + '☆'.repeat(5 - n); }
function metaDetalhe(item, inf) {
  const ano = (inf && inf.ano) || item.ano || '';
  const nota = (inf && inf.nota) || (item.nota > 0 ? item.nota : 0);
  const gen = (item.generos || []).join(' / ');
  const l1 = [];
  if (ano) l1.push(`<span>${ano}</span>`);
  if (nota) l1.push(`<span class="imdb">IMDb ${nota.toFixed(1)}</span><span class="estrelas">${estrelas(nota)}</span>`);
  return `<div class="det2-meta1">${l1.join('<i class="pt">·</i>')}</div>${gen ? `<div class="det2-meta2">${escapar(gen)}</div>` : ''}`;
}
function recomendadosLocais(item) {
  const lista = item.tipo === 'serie' ? LISTA.series : LISTA.filmes;
  const g = (item.generos || [])[0];
  return lista.filter((x) => x.id !== item.id && (x.generos || [])[0] === g).slice(0, 18);
}
function montarRec(cont, itens) {
  cont.innerHTML = '';
  for (const it of itens) {
    const el = document.createElement('div');
    el.className = 'rec-poster focusable';
    el.innerHTML = `<div class="rec-arte" style="background:${gradiente(it.titulo)}"><span>${escapar(it.titulo)}</span></div>`;
    el.addEventListener('click', () => { fecharDetalhe(); abrirDetalhe(it); });
    cont.appendChild(el);
    const setImg = (u) => { if (!u) return; const im = new Image(); im.className = 'rec-img'; im.onload = () => { const a = el.querySelector('.rec-arte'); if (a) { a.classList.add('tem-img'); a.appendChild(im); } }; im.src = u; };
    if (it.tipo !== 'serie' && it.logo) setImg(it.logo); else TMDB.poster(it.titulo).then(setImg);
  }
}
function montarElenco(cont, elenco) {
  cont.innerHTML = '';
  for (const a of elenco) {
    const el = document.createElement('div');
    el.className = 'ator focusable';
    el.innerHTML = `<div class="ator-foto"${a.foto ? ` style="background:#000 center/cover url('${a.foto}')"` : ''}>${a.foto ? '' : escapar(iniciais(a.nome))}</div>
      <div class="ator-nome">${escapar(a.nome)}</div>${a.personagem ? `<div class="ator-pers">${escapar(a.personagem)}</div>` : ''}`;
    cont.appendChild(el);
  }
}

function abrirDetalhe(item) {
  const ehSerie = item.tipo === 'serie';
  let inf = null, cred = { elenco: [], direcao: [] };
  const ov = document.createElement('div');
  ov.id = 'detalhe-overlay';
  ov.className = 'nav-modal det2';
  const acoes = ehSerie
    ? `<button class="btn btn-primario focusable" data-acao="assistir"><svg viewBox="0 0 24 24"><path d="M8 5v14l11-7z"/></svg> Assistir ${escapar(primeiroEpLabel(item))}</button>
       <button class="btn btn-secundario focusable" data-acao="episodios"><svg viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="2" stroke-linecap="round"><path d="M3 6h13M3 12h13M3 18h9"/><path d="m18 11 4 3-4 3z" fill="currentColor" stroke="none"/></svg> Episódios e mais</button>`
    : `<button class="btn btn-primario focusable" data-acao="assistir"><svg viewBox="0 0 24 24"><path d="M8 5v14l11-7z"/></svg> Assistir</button>`;
  ov.innerHTML = `
    <div class="det2-bg" id="det2-bg" style="background:${FUNDO_PADRAO}"></div>
    <div class="det2-grad"></div>
    <div class="det2-scroll" id="det2-scroll">
      <section class="det2-topo">
        <img class="det2-logo" id="det2-logo" alt="" style="display:none">
        <h1 class="det2-titulo" id="det2-titulo">${escapar(item.titulo)}</h1>
        <div class="det2-meta" id="det2-meta"></div>
        <span class="det2-tag">${ehSerie ? 'Série' : 'Filme'}</span>
        <p class="det2-sinopse" id="det2-sinopse">${escapar(item.sinopse || '')}</p>
        <div class="det2-acoes">
          ${acoes}
          <button class="btn btn-icone focusable" data-acao="lista" title="Minha Lista"><svg viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="2.4" stroke-linecap="round"><path d="M12 5v14M5 12h14"/></svg></button>
          <button class="btn btn-icone focusable" data-acao="creditos" title="Créditos e mais informações"><svg viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="2"><circle cx="12" cy="12" r="9"/><path d="M12 11v5" stroke-linecap="round"/><circle cx="12" cy="8" r="0.6" fill="currentColor" stroke="none"/></svg></button>
        </div>
      </section>
      <section class="det2-secao oculto" id="det2-elenco">
        <h2 class="det2-h2">Elenco</h2>
        <div class="det2-fila" id="det2-elenco-fila"></div>
      </section>
      <section class="det2-secao oculto" id="det2-rec">
        <h2 class="det2-h2">Títulos semelhantes</h2>
        <div class="det2-fila" id="det2-rec-fila"></div>
      </section>
    </div>`;
  document.body.appendChild(ov);
  ov._onVoltar = fecharDetalhe;
  ov._voltarFoco = SpatialNav.atual;   // p/ voltar ao item que abriu (ex.: resultado da busca de seção)
  const q = (a) => ov.querySelector(`[data-acao="${a}"]`);
  q('assistir').addEventListener('click', () => {
    if (ehSerie) { const ep = primeiroEp(item); if (ep) { fecharDetalhe(); abrirPlayer({ titulo: rotuloEp(item, ep), url: ep.url }); } }
    else { fecharDetalhe(); abrirPlayer(item); }
  });
  if (q('episodios')) q('episodios').addEventListener('click', () => abrirEpisodios(item, inf));
  q('lista').addEventListener('click', () => toast('Minha Lista — em breve'));
  q('creditos').addEventListener('click', () => abrirCreditos(item, inf, cred));
  SpatialNav.setFocus(q('assistir'));

  document.getElementById('det2-meta').innerHTML = metaDetalhe(item, null);
  const recs = recomendadosLocais(item);
  if (recs.length) { document.getElementById('det2-rec').classList.remove('oculto'); montarRec(document.getElementById('det2-rec-fila'), recs); }

  TMDB.info(item.titulo, ehSerie).then(async (i) => {
    if (!document.getElementById('detalhe-overlay')) return;
    inf = i;
    if (!i || i.vazio) { const s = document.getElementById('det2-sinopse'); if (s && !s.textContent) s.textContent = 'Sem descrição disponível.'; return; }
    const bg = document.getElementById('det2-bg');
    if (i.backdrop && bg) bg.style.background = `#000 right top / cover no-repeat url("${i.backdrop}")`;
    const sin = document.getElementById('det2-sinopse'); if (sin) sin.textContent = i.sinopse || item.sinopse || 'Sem descrição disponível.';
    document.getElementById('det2-meta').innerHTML = metaDetalhe(item, i);
    if (i.id) {
      const lg = await TMDB.tituloLogo(i.id, i.ehTv);
      const logoEl = document.getElementById('det2-logo'), tit = document.getElementById('det2-titulo');
      if (lg && logoEl) { logoEl.onload = () => { logoEl.style.display = 'block'; if (tit) tit.style.display = 'none'; }; logoEl.src = lg; }
      TMDB.creditos(i.id, i.ehTv).then((c) => {
        cred = c;
        if (c.elenco.length && document.getElementById('detalhe-overlay')) {
          document.getElementById('det2-elenco').classList.remove('oculto');
          montarElenco(document.getElementById('det2-elenco-fila'), c.elenco);
        }
      });
    }
  });
}
function fecharDetalhe() {
  const ov = document.getElementById('detalhe-overlay');
  const volta = ov && ov._voltarFoco;
  if (ov) ov.remove();
  // Volta ao item que abriu (ex.: resultado dentro da busca de seção); senão, conteúdo.
  if (volta && document.contains(volta)) { SpatialNav.setFocus(volta); return; }
  const f = document.querySelector('#conteudo .focusable');
  if (f) SpatialNav.setFocus(f);
}

// Créditos e mais informações — menu à esquerda + painel à direita (estilo GTV).
function abrirCreditos(item, inf, cred) {
  const sec = [];
  if (cred && cred.direcao && cred.direcao.length) sec.push(['Direção', cred.direcao.join(', ')]);
  if (cred && cred.elenco && cred.elenco.length) sec.push(['Elenco', cred.elenco.map((a) => a.personagem ? `${a.nome} — ${a.personagem}` : a.nome).join('\n')]);
  const gen = (item.generos || []).join(', '); if (gen) sec.push(['Gêneros', gen]);
  const sin = (inf && inf.sinopse) || item.sinopse || ''; if (sin) sec.push(['Sinopse', sin]);
  if (!sec.length) sec.push(['Informações', 'Sem informações adicionais.']);

  const ov = document.createElement('div');
  ov.className = 'nav-modal cr';
  ov.innerHTML = `
    <div class="cr-card">
      <div class="cr-menu">
        <div class="cr-titulo">${escapar(item.titulo)}</div>
        ${sec.map((s, i) => `<button class="cr-item focusable${i === 0 ? ' ativo' : ''}" data-h="${escapar(s[0])}" data-cont="${escapar(s[1])}">${escapar(s[0])}</button>`).join('')}
      </div>
      <div class="cr-painel"><h3 class="cr-h" id="cr-h"></h3><div class="cr-c" id="cr-c"></div></div>
    </div>`;
  document.body.appendChild(ov);
  ov._onVoltar = () => { ov.remove(); const f = document.querySelector('#detalhe-overlay [data-acao="creditos"]'); if (f) SpatialNav.setFocus(f); };
  ov.querySelectorAll('.cr-item').forEach((b) => b.addEventListener('click', () => mostrarCredito(b)));
  SpatialNav.setFocus(ov.querySelector('.cr-item')); // aoFocar atualiza o painel
}
// Atualiza o painel de créditos a partir do item de menu focado.
function mostrarCredito(el) {
  if (!el) return;
  el.parentElement.querySelectorAll('.cr-item').forEach((b) => b.classList.toggle('ativo', b === el));
  const h = document.getElementById('cr-h'), c = document.getElementById('cr-c');
  if (h) h.textContent = el.dataset.h || '';
  if (c) c.textContent = el.dataset.cont || '';
}

// Episódios da série: seletor de TEMPORADA vertical à esquerda (bolinhas — a
// ativa vira uma "pílula" com "Temporada X") + lista de episódios CENTRALIZADA
// com o nome/logo da série no topo. Capas/sinopses vêm do TMDB ao abrir.
let _epCtrl = null; // controlador da tela aberta (usado pelo aoFocar ao focar temporada)

function abrirEpisodios(item, inf) {
  const eps = epsOrdenados(item);
  const porTemp = {};
  for (const ep of eps) { const { s } = epInfo(ep.nome); (porTemp[s] || (porTemp[s] = [])).push(ep); }
  let temps = Object.keys(porTemp).map(Number).sort((a, b) => a - b);
  if (!temps.length) { temps = [1]; porTemp[1] = eps; }
  let tAtual = temps[0];   // temporada selecionada (1ª por padrão)
  let tokTemp = 0;         // evita corrida do TMDB ao trocar de temporada

  const ov = document.createElement('div');
  ov.className = 'nav-modal ep';
  ov.innerHTML = `
    <div class="ep-bg" id="ep-bg" style="background:${FUNDO_PADRAO}"></div>
    <div class="ep-grad"></div>
    <div class="ep-conteudo">
      <div class="ep-cabecalho">
        <img class="ep-logo" id="ep-logo" alt="" style="display:none">
        <h1 class="ep-titulo" id="ep-titulo">${escapar(item.titulo)}</h1>
      </div>
      <div class="ep-temps" id="ep-temps">
        ${temps.map((t) => `<div class="ep-temp-item focusable${t === tAtual ? ' ativa' : ''}" data-s="${t}"><span class="ep-temp-dot"></span><span class="ep-temp-lbl">Temporada ${t}</span></div>`).join('')}
      </div>
      <div class="ep-centro"><div class="ep-lista" id="ep-lista"></div></div>
    </div>`;
  document.body.appendChild(ov);
  _epCtrl = { selecionarTemporada };
  ov._onVoltar = () => { _epCtrl = null; ov.remove(); const f = document.querySelector('#detalhe-overlay [data-acao="episodios"]'); if (f) SpatialNav.setFocus(f); };

  // Fundo: backdrop centralizado e esmaecido (ambiente p/ o conteúdo central).
  if (inf && inf.backdrop) document.getElementById('ep-bg').style.background = `#000 center/cover no-repeat url("${inf.backdrop}")`;

  // Logo-título da série no topo (se houver).
  if (inf && inf.id) {
    const aplicaLogo = (lg) => {
      if (!lg) return;
      const logoEl = document.getElementById('ep-logo'), tit = document.getElementById('ep-titulo');
      if (!logoEl) return;
      const mostrar = () => { logoEl.style.display = 'block'; if (tit) tit.style.display = 'none'; };
      logoEl.onload = mostrar; logoEl.src = lg;
      if (logoEl.complete && logoEl.naturalWidth > 0) mostrar();
    };
    const cache = TMDB.logoCache(inf.id, inf.ehTv);
    if (cache !== null) aplicaLogo(cache); else TMDB.tituloLogo(inf.id, inf.ehTv).then(aplicaLogo);

    // Pré-carrega as capas de TODAS as temporadas ao abrir — assim trocar de
    // temporada fica INSTANTÂNEO (sem a foto dos episódios "trocando" na hora).
    // TMDB.temporada cacheia por (id|temporada); aqui também aquecemos os stills.
    _executarFila(temps.map((t) => () => TMDB.temporada(inf.id, t).then((capas) => {
      for (const k in (capas || {})) _aquece(capas[k] && capas[k].still);
    })), 4);
  }

  // Clique numa temporada: seleciona e entra na lista de episódios (OK = entrar).
  ov.querySelectorAll('.ep-temp-item').forEach((it) => it.addEventListener('click', () => {
    selecionarTemporada(+it.dataset.s);
    const ep = ov.querySelector('.ep-item'); if (ep) SpatialNav.setFocus(ep);
  }));

  // Troca a temporada ativa (anima as bolinhas) e re-renderiza os episódios.
  // SEM roubar o foco — quem chama (foco/clique) decide onde o foco fica.
  function selecionarTemporada(s) {
    if (!(s in porTemp)) return;
    if (s === tAtual && ov.querySelector('.ep-item')) return; // já é a atual
    tAtual = s;
    ov.querySelectorAll('.ep-temp-item').forEach((it) => it.classList.toggle('ativa', +it.dataset.s === s));
    render(false);
  }

  // HTML de um episódio. `d` = dados do TMDB (still/nome/sinopse) se já houver;
  // `skel`=true mostra o skeleton da sinopse (enquanto o TMDB não respondeu).
  function epItemHTML(ep, e, d, skel) {
    const cap = (d && d.still) || (inf && inf.backdrop) || '';
    const nomeEp = (d && d.nome) || ep.nome;
    const sin = d && d.sinopse;
    const sinHTML = sin
      ? `<div class="ep-sinopse">${escapar(sin)}</div>`
      : (skel ? '<div class="ep-sinopse"><span class="ep-sk"></span><span class="ep-sk l2"></span></div>' : '');
    return `
      <div class="ep-capa"${cap ? ` style="background:#000 center/cover url('${cap}')"` : ` style="background:${gradiente(item.titulo)}"`}>${cap ? '' : `<span>E${e || ''}</span>`}</div>
      <div class="ep-info">
        <div class="ep-n">${e ? ('E' + String(e).padStart(2, '0') + ' · ') : ''}${escapar(nomeEp)}</div>
        ${sinHTML}
      </div>`;
  }

  // Renderiza os episódios da temporada atual. `focar`=true foca o 1º episódio.
  // Se a temporada JÁ está pré-carregada (cache), desenha as capas/sinopse DIRETO
  // — sem skeleton nem o "swap" backdrop→still (troca de temporada instantânea).
  function render(focar) {
    const tNum = tAtual;
    const meu = ++tokTemp;
    const lista = document.getElementById('ep-lista');
    const arr = porTemp[tNum] || [];
    const temTmdb = !!(inf && inf.id);
    const cache = temTmdb ? TMDB.temporadaCache(inf.id, tNum) : null;

    lista.innerHTML = '';
    const refs = [];
    for (const ep of arr) {
      const { e } = epInfo(ep.nome);
      const el = document.createElement('div');
      el.className = 'ep-item focusable';
      el.innerHTML = epItemHTML(ep, e, cache ? cache[e] : null, temTmdb && !cache);
      el.addEventListener('click', () => { _epCtrl = null; ov.remove(); const d = document.getElementById('detalhe-overlay'); if (d) d.remove(); abrirPlayer({ titulo: rotuloEp(item, ep), url: ep.url }); });
      lista.appendChild(el);
      refs.push({ el, e });
    }
    if (focar) { const first = lista.querySelector('.ep-item'); if (first) SpatialNav.setFocus(first); }
    if (!temTmdb || cache) return; // sem TMDB, ou já desenhado do cache → pronto

    // Não cacheado ainda: busca e preenche (skeleton → capa/nome/sinopse).
    TMDB.temporada(inf.id, tNum).then((capas) => {
      capas = capas || {};
      if (meu !== tokTemp || !document.body.contains(ov)) return; // trocou de temporada / fechou
      for (const r of refs) {
        const d = capas[r.e];
        if (d && d.still) {
          const c = r.el.querySelector('.ep-capa');
          if (c) { c.style.background = `#000 center/cover url('${d.still}')`; const sp = c.querySelector('span'); if (sp) sp.remove(); }
        }
        if (d && d.nome) {
          const n = r.el.querySelector('.ep-n');
          if (n) n.textContent = (r.e ? ('E' + String(r.e).padStart(2, '0') + ' · ') : '') + d.nome;
        }
        const sinEl = r.el.querySelector('.ep-sinopse');
        if (sinEl) {
          const sin = (d && d.sinopse) || '';
          if (sin) sinEl.textContent = sin;   // troca o skeleton pela sinopse
          else sinEl.remove();                 // sem sinopse → remove
        }
      }
    });
  }

  render(true); // abre focando o 1º episódio da temporada selecionada
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

// Tela de episódios: "esquerda" num episódio → vai p/ a temporada ATIVA (aberta);
// "direita" numa temporada → entra na lista de episódios.
window.addEventListener('keydown', (e) => {
  const ov = document.querySelector('.nav-modal.ep');
  if (!ov) return;
  const at = SpatialNav.atual;
  if (!at || !at.closest || !at.closest('.nav-modal.ep')) return;
  if (e.key === 'ArrowLeft' && at.classList.contains('ep-item')) {
    const ativa = ov.querySelector('.ep-temp-item.ativa') || ov.querySelector('.ep-temp-item');
    if (ativa) { e.preventDefault(); e.stopPropagation(); SpatialNav.setFocus(ativa); }
  } else if (e.key === 'ArrowRight' && at.classList.contains('ep-temp-item')) {
    const ep = ov.querySelector('.ep-item');
    if (ep) { e.preventDefault(); e.stopPropagation(); SpatialNav.setFocus(ep); }
  }
}, true);

// Carrosséis (Início/Filmes/Séries): ↑/↓ entre trilhos vai p/ a posição LEMBRADA
// do trilho-alvo (ou o 1º item, se nunca visitado) — NÃO o item geometricamente
// alinhado (que caía no meio). Cada trilho guarda seu último foco em data-ultimo.
function _posterLembrado(fila) {
  const id = fila.dataset.ultimo;
  if (!id) return null;
  return [...fila.querySelectorAll('.poster')].find((p) => p.dataset.id === id) || null;
}
window.addEventListener('keydown', (e) => {
  if (e.key !== 'ArrowDown' && e.key !== 'ArrowUp') return;
  const at = SpatialNav.atual;
  if (!at || !at.classList || !at.classList.contains('poster')) return;
  const filaAtual = at.closest('.trilho-fila');
  if (!filaAtual) return;
  const filas = [...document.querySelectorAll('#conteudo .trilho-fila')];
  const i = filas.indexOf(filaAtual);
  const alvoFila = filas[e.key === 'ArrowDown' ? i + 1 : i - 1];
  if (!alvoFila) return;                       // sem trilho na direção → foco fica
  const alvo = _posterLembrado(alvoFila) || alvoFila.querySelector('.poster');
  if (!alvo) return;                           // trilho-alvo vazio → deixa o engine
  e.preventDefault(); e.stopPropagation();
  SpatialNav.setFocus(alvo);
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
  const btnBuscaSec = e.target.closest('[data-acao="busca-secao"]');
  if (btnBuscaSec) { abrirBuscaSecao(btnBuscaSec.dataset.escopo, btnBuscaSec); return; }
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
    if (ok) { loadingMsg('Preparando seus banners…'); await precarregarBanners(); }
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
    if (!el || !el.classList) return;
    if (el.classList.contains('poster')) {
      if (el.closest('.bsc-grid')) {
        el.scrollIntoView({ block: 'nearest', behavior: 'smooth' }); // grade da busca rola sozinha
      } else {
        focarPoster(el);                       // scroll (fila + título sob o hero)
        const fila = el.closest('.trilho-fila'); // lembra a posição neste carrossel
        if (fila) fila.dataset.ultimo = el.dataset.id;
        const it = LISTA.indice[el.dataset.id];
        if (it) atualizarHero(it);
      }
    } else if (el.classList.contains('cr-item')) {
      mostrarCredito(el);                    // créditos: painel reage ao foco
    } else if (el.classList.contains('ep-temp-item')) {
      if (_epCtrl) _epCtrl.selecionarTemporada(+el.dataset.s); // temporada abre ao focar
    }
  });
  await Dispositivo.consultar(); // best-effort (offline-first)
  if (Dispositivo.temLista()) iniciarApp();
  else mostrarOnboarding(); // app neutro: abre vazio ate ter lista (conformidade)
});
