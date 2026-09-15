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
  { id: 'jogos', rotulo: 'Futebol', ico: 'jogos' },
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
  // Sem optional chaining (?.): webOS 5 = Chromium 68, onde `?.` é ERRO DE SINTAXE
  // e derruba o arquivo inteiro. Mesma regra p/ `??` e `||=`.
  return (((p[0] && p[0][0]) || '') + ((p[1] && p[1][0]) || '')).toUpperCase() || nome.slice(0, 2).toUpperCase();
};
const hhmm = (d) => String(d.getHours()).padStart(2, '0') + ':' + String(d.getMinutes()).padStart(2, '0');

// ── Render: poster ──────────────────────────────────────────────────────────
function posterHTML(item, vigiar) {
  // Filme: usa o logo/poster da PRÓPRIA LISTA (a lista já traz a capa certa — o
  // TMDB aqui é só fallback). Série: o "logo" é o thumbnail do 1º episódio (feio/
  // pixelado) — então busca o PÔSTER no TMDB (lazy). Se o TMDB não tiver pôster,
  // fica SÓ o nome (gradiente) — NÃO usa o thumb do episódio.
  // `vigiar`: usado na BUSCA — mantém a capa da lista, mas se ela PENDURAR (sem
  // load nem error, comum em alguns provedores na TV) cai pro TMDB depois de N ms.
  const ehSerie = item.tipo === 'serie';
  const usarLogo = !!item.logo && !ehSerie;
  const lazy = !usarLogo ? ` data-tmdb="${escapar(item.titulo)}" data-serie="${ehSerie ? 1 : 0}"` : '';
  // Filme com logo da lista: se o logo NÃO carregar (host do provedor bloqueado/
  // http na TV), cai para o pôster do TMDB pelo título — senão ficava só o nome.
  const img = usarLogo
    ? `<img class="poster-img" src="${escapar(item.logo)}" alt="" data-tmdb="${escapar(item.titulo)}"${vigiar ? ' data-vigiar="1"' : ''}
         onload="this.closest('.poster-arte').classList.add('tem-img')" onerror="_logoParaTmdb(this)">`
    : '';
  return `<div class="poster focusable" data-id="${item.id}"${lazy}>
    <div class="poster-arte">
      ${img}<span>${escapar(item.titulo)}</span>
    </div>
  </div>`;
}

// Logo da lista que "pendura" (nem load nem error): depois de LOGO_TIMEOUT sem
// carregar, cai pro pôster do TMDB — mesmo caminho do onerror. Só na busca, onde
// o item aparece sozinho e um pôster vazio é gritante.
const LOGO_TIMEOUT = 5000;
function vigiarLogo(el) {
  const img = el.querySelector('img.poster-img[data-vigiar]');
  if (!img) return;
  setTimeout(() => {
    const arte = img.closest('.poster-arte');
    if (!arte || !arte.isConnected || arte.classList.contains('tem-img')) return;
    if (img.complete && img.naturalWidth > 0) return;   // carregou (só o onload não veio)
    _logoParaTmdb(img);
  }, LOGO_TIMEOUT);
}

// Fallback do pôster de FILME: o logo da lista falhou → busca o pôster no TMDB
// pelo título e usa no lugar. Cobre provedores cujos logos não abrem na TV.
function _logoParaTmdb(img) {
  const arte = img.closest('.poster-arte');
  const titulo = img.dataset.tmdb;
  img.remove();
  if (!arte || !titulo || arte.classList.contains('tem-img')) return;
  TMDB.poster(titulo, false).then((u) => {
    if (!u || arte.classList.contains('tem-img') || !arte.isConnected) return;
    const n = new Image();
    n.className = 'poster-img';
    n.onload = () => arte.classList.add('tem-img');
    n.src = u;
    arte.appendChild(n);
  });
}

// ── Render: trilho ──────────────────────────────────────────────────────────
// ⚠️ O parâmetro se chama `tr`, NÃO `t`: `t()` é a função de tradução global, e
// um parâmetro com esse nome a SOMBREIA dentro da função. Chamar `t('...')` aqui
// virava "chamar o objeto do trilho como função" — TypeError em todo trilho, com
// Filmes e Séries sem conseguir montar. (Vários pontos deste arquivo usam `t`
// como nome de variável local; ao mexer neles, cuidado com isso.)
function trilhoHTML(tr) {
  // O TÍTULO é focável: selecionar a categoria abre a tela com TODOS os itens
  // dela (abrirCategoria). O trilho mostra só os primeiros — antes não havia
  // como ver o resto de uma categoria.
  return `<section class="trilho">
    <h2 class="trilho-titulo focusable" data-cat="${escapar(tr.titulo)}">
      ${escapar(tr.titulo)}
      <span class="trilho-tudo">${escapar(t('Ver tudo'))} ${IC_CHEVRON}</span>
    </h2>
    <div class="trilho-fila">${tr.itens.map((it) => posterHTML(it)).join('')}</div>
  </section>`;
}
const IC_CHEVRON = '<svg class="tr-chev" viewBox="0 0 24 24"><path d="m9 6 6 6-6 6" fill="none" stroke="currentColor" stroke-width="2.4" stroke-linecap="round" stroke-linejoin="round"/></svg>';

/**
 * Tela de CATEGORIA: grade com todos os itens de um gênero/categoria.
 *
 * Reaproveita a grade da busca (`.bsc-grid` + aplicarResultados) — mesmo pôster,
 * mesmo carregamento lazy de capa. Sem teclado: aqui não se digita, só se navega.
 * Os itens entram em LOTES (requestAnimationFrame), do mesmo jeito que a lista de
 * canais: uma categoria grande tem centenas de títulos e montar tudo de uma vez
 * congela a TV.
 */
const CAT_LOTE = 24;
let _catTok = 0;
function abrirCategoria(escopo, titulo) {
  // No Início os trilhos misturam filme e série, então não há lista-base para
  // filtrar por gênero: ali vale o próprio trilho (o fallback abaixo).
  const base = escopo === 'series' ? (LISTA.series || [])
    : escopo === 'filmes' ? (LISTA.filmes || []) : [];
  // Mesma regra de filtro da busca por seção: 1º gênero do item = categoria.
  let itens = base.filter((it) => (it.generos && it.generos[0]) === titulo);
  // Categoria que não casa por gênero (trilho especial, ex.: "Lançamentos") →
  // cai para os itens do próprio trilho, que é o que o usuário viu na tela.
  if (!itens.length) {
    const tr = (((LISTA.catalogo || {})[escopo] || {}).trilhos || []).find((x) => x.titulo === titulo);
    itens = (tr && tr.itens) || [];
  }
  const meu = ++_catTok;
  const ov = document.createElement('div');
  ov.className = 'nav-modal cat-tela';
  ov.innerHTML = `
    ${htmlVoltar()}
    <div class="cat-cab">
      <h1 class="cat-titulo">${escapar(titulo)}</h1>
      <div class="cat-sub">${itens.length} ${escapar(itens.length === 1 ? t('título') : t('títulos'))}</div>
    </div>
    <div class="cat-grade" id="cat-grade"></div>`;
  document.body.appendChild(ov);
  const anterior = SpatialNav.atual;
  ov._onVoltar = () => {
    ++_catTok;
    ov.remove();
    const cont = document.getElementById('conteudo');
    if (cont) ligarPostersSerie(cont);   // re-observa os pôsteres da seção por baixo
    if (anterior && document.contains(anterior)) SpatialNav.setFocus(anterior);
  };

  const grade = ov.querySelector('#cat-grade');
  if (!itens.length) {
    grade.innerHTML = `<div class="cat-vazio">${escapar(t('Nada por aqui'))}</div>`;
    SpatialNav.setFocus(ov.querySelector('.tela-voltar') || grade);
    return;
  }
  grade.innerHTML = '<div class="bsc-grid"></div>';
  const grid = grade.querySelector('.bsc-grid');
  let i = 0;
  const lote = () => {
    if (meu !== _catTok || !document.body.contains(ov)) return;
    let html = '';
    for (let n = 0; n < CAT_LOTE && i < itens.length; n++, i++) html += posterHTML(itens[i], true);
    grid.insertAdjacentHTML('beforeend', html);
    ligarPostersSerie(grade);            // capas lazy só do que entrou
    if (i < itens.length) requestAnimationFrame(lote);
  };
  lote();
  requestAnimationFrame(() => {
    const p = grid.querySelector('.poster');
    if (p) SpatialNav.setFocus(p);
  });
}

// Pôster com barra de progresso (trilho "Continuar assistindo").
function posterContHTML(item, prog) {
  const ehSerie = item.tipo === 'serie';
  const usarLogo = !!item.logo && !ehSerie;
  const lazy = !usarLogo ? ` data-tmdb="${escapar(item.titulo)}" data-serie="${ehSerie ? 1 : 0}"` : '';
  const img = usarLogo
    ? `<img class="poster-img" src="${escapar(item.logo)}" alt="" loading="lazy" onload="this.closest('.poster-arte').classList.add('tem-img')" onerror="this.remove()">`
    : '';
  const pct = Math.round(Math.max(0, Math.min(1, prog || 0)) * 100);
  return `<div class="poster focusable" data-id="${item.id}"${lazy}>
    <div class="poster-arte">
      ${img}<span>${escapar(item.titulo)}</span>
      <div class="poster-prog"><span style="width:${pct}%"></span></div>
    </div>
  </div>`;
}
function trilhoContinuarHTML(entries) {
  const posters = entries.map((e) => { const it = LISTA.indice[e.id]; return it ? posterContHTML(it, e.dur ? e.pos / e.dur : 0) : ''; }).filter(Boolean).join('');
  return posters ? `<section class="trilho"><h2 class="trilho-titulo">${escapar(t('Continuar assistindo'))}</h2><div class="trilho-fila">${posters}</div></section>` : '';
}
// Prepende "Continuar assistindo" + "Recomendações pra você" no topo do Início (por perfil).
function injetarTrilhosPerfil(main) {
  const trilhos = main.querySelector('.trilhos'); if (!trilhos) return;
  const rec = Biblioteca.recomendacoes(18);
  const extra = trilhoContinuarHTML(Biblioteca.continuarAssistindo())
    + (rec.length ? trilhoHTML({ titulo: t('Recomendações pra você'), itens: rec }) : '');
  if (!extra) return;
  // Marca como trilhos DO PERFIL (.trilho-perfil) p/ trocar só eles ao mudar de
  // perfil, sem reconstruir o catálogo (que é o mesmo p/ todos). Insere na ordem.
  const tmp = document.createElement('div'); tmp.innerHTML = extra;
  const frag = document.createDocumentFragment();
  [...tmp.children].forEach((s) => { s.classList.add('trilho-perfil'); frag.appendChild(s); });
  trilhos.insertBefore(frag, trilhos.firstChild);
}

// Troca de perfil: substitui SÓ os trilhos do perfil (Continuar + Recomendações)
// no Início já renderizado — sem recriar os pôsteres do catálogo nem re-decodar
// as imagens compartilhadas. Observa apenas os pôsteres novos.
function atualizarTrilhosPerfil(main) {
  const trilhos = main && main.querySelector('.trilhos'); if (!trilhos) return;
  trilhos.querySelectorAll('.trilho-perfil').forEach((s) => {
    s.querySelectorAll('.poster[data-tmdb]').forEach((p) => { if (_obsPoster) _obsPoster.unobserve(p); });
    s.remove();
  });
  injetarTrilhosPerfil(main);
  if (_obsPoster) trilhos.querySelectorAll('.trilho-perfil .poster[data-tmdb]').forEach((p) => _obsPoster.observe(p));
}

// "Minha Lista" no TOPO das seções Filmes/Séries (separada por tipo, por perfil).
function injetarMinhaLista(main, secaoId) {
  const trilhos = main && main.querySelector('.trilhos'); if (!trilhos) return;
  const tipo = secaoId === 'filmes' ? 'filme' : 'serie';
  const itens = Biblioteca.minhaLista(tipo).map((e) => LISTA.indice[e.id]).filter(Boolean);
  if (!itens.length) return;
  const tmp = document.createElement('div');
  tmp.innerHTML = trilhoHTML({ titulo: t('Minha Lista'), itens });
  const sec = tmp.firstElementChild; if (!sec) return;
  sec.classList.add('trilho-minha-lista');
  trilhos.insertBefore(sec, trilhos.firstChild);
}
// Atualiza o trilho "Minha Lista" da seção do TIPO ('filme'/'serie') no DOM
// cacheado (esteja visível ou não) — mantém o cache consistente após adicionar/
// remover no detalhe, sem reconstruir o catálogo.
function atualizarMinhaLista(tipo) {
  const secaoId = tipo === 'serie' ? 'series' : 'filmes';
  let node = _secCacheGet(secaoId);
  if (!node) {   // sem cache (TV): atualiza a seção VISÍVEL, se for a desse tipo
    const ativo = document.querySelector('.nav-item.ativo');
    if (ativo && ativo.dataset.secao === secaoId) node = document.getElementById('conteudo').firstElementChild;
  }
  const trilhos = node && node.querySelector('.trilhos'); if (!trilhos) return;
  trilhos.querySelectorAll('.trilho-minha-lista').forEach((s) => {
    s.querySelectorAll('.poster[data-tmdb]').forEach((p) => { if (_obsPoster) _obsPoster.unobserve(p); });
    s.remove();
  });
  injetarMinhaLista(node, secaoId);
  // Só observa (carrega banners) se a seção está visível agora; senão, o navegar
  // futuro re-observa via ligarPostersSerie.
  if (node.isConnected && _obsPoster) trilhos.querySelectorAll('.trilho-minha-lista .poster[data-tmdb]').forEach((p) => _obsPoster.observe(p));
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
          <svg viewBox="0 0 24 24"><path d="M8 5v14l11-7z"/></svg> ${escapar(t('Assistir'))}
        </button>
        <button class="btn btn-secundario focusable" data-acao="lista">
          <svg viewBox="0 0 24 24"><path d="M12 5v14M5 12h14" stroke="currentColor" stroke-width="2.4" fill="none" stroke-linecap="round"/></svg> ${escapar(t('Minha Lista'))}
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
const TV_TRILHOS_INICIAL = 8;   // TV: render inicial LEVE; o resto entra em chunks
function renderMidia(cfg, secaoId) {
  if (!cfg.trilhos.length) {
    return `<div class="secao">${renderPlaceholder(t('Nada por aqui'), t('Sua lista não tem itens nesta seção.'))}</div>`;
  }
  // Botão de busca da seção (só Filmes/Séries) — canto superior direito.
  const btnBusca = (secaoId === 'filmes' || secaoId === 'series')
    ? `<button class="midia-busca focusable" data-acao="busca-secao" data-escopo="${secaoId}" aria-label="${escapar(t('Buscar'))}">${IC_BUSCA_LUPA}</button>`
    : '';
  // TV: só os primeiros trilhos AGORA (evita travar a UI parseando centenas de
  // pôsteres de uma vez). O restante é anexado em chunks (anexarTrilhosRestantes).
  const trilhosIni = EH_TV ? cfg.trilhos.slice(0, TV_TRILHOS_INICIAL) : cfg.trilhos;
  return `<div class="midia">
    ${heroFixoHTML()}
    <div class="trilhos">${trilhosIni.map(trilhoHTML).join('')}</div>
    ${btnBusca}
  </div>`;
}

// TV: anexa os trilhos restantes em pequenos chunks (requestAnimationFrame) pra a
// UI não congelar. Cancelável por token (ao navegar de novo) e por node desanexado.
let _tokenTrilhos = 0;
function anexarTrilhosRestantes(node, cfg) {
  if (!EH_TV || !node || !cfg || cfg.trilhos.length <= TV_TRILHOS_INICIAL) return;
  const cont = node.querySelector('.trilhos'); if (!cont) return;
  const resto = cfg.trilhos.slice(TV_TRILHOS_INICIAL);
  const meu = ++_tokenTrilhos;
  let i = 0;
  function chunk() {
    if (meu !== _tokenTrilhos || !cont.isConnected) return;
    const antes = cont.children.length;
    let html = '';
    for (let n = 0; n < 3 && i < resto.length; n++, i++) html += trilhoHTML(resto[i]);
    cont.insertAdjacentHTML('beforeend', html);
    // observa SÓ os pôsteres dos trilhos recém-adicionados (via observer existente)
    if (_obsPoster) for (let k = antes; k < cont.children.length; k++) {
      cont.children[k].querySelectorAll('.poster[data-tmdb]').forEach((p) => _obsPoster.observe(p));
    }
    if (i < resto.length) requestAnimationFrame(chunk);
  }
  requestAnimationFrame(chunk);   // começa DEPOIS do ligarPostersSerie do navegar
}

// ── Hero dinâmico (reflete o item em foco; metadados via TMDB) ───────────────
let _heroItem = null, _heroToken = 0, _heroTimer = null, _heroBgAtivo = 'A';
let _heroPendente = null, _heroDebounce = null, _heroUltimoAplicado = 0;
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
    aplicarHero(item); _heroUltimoAplicado = Date.now();
    return;
  }
  _heroPendente = item;
  clearTimeout(_heroDebounce);
  // Debounce ao rolar. No desktop, se faz tempo desde a última troca (D-pad
  // SEGURADO) o hero acompanha devagar (40ms). Na TV isso era jank: cada passo
  // recarregava backdrop/logo e reanimava o hero enquanto o foco corria. Na TV o
  // hero só troca quando o foco PARA (sempre o debounce cheio) — bem mais leve.
  const espera = (!EH_TV && Date.now() - _heroUltimoAplicado > 550) ? 40 : HERO_DELAY;
  _heroDebounce = setTimeout(() => {
    _heroDebounce = null;
    const alvo = _heroPendente; _heroPendente = null;
    if (alvo) { aplicarHero(alvo); _heroUltimoAplicado = Date.now(); } // aplicarHero ignora se já for o exibido
  }, espera);
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
  const meta = document.getElementById('hero2-meta'); if (meta) meta.innerHTML = notaHero(item, null);
  const sinE = document.getElementById('hero2-sinopse'); if (sinE) sinE.textContent = item.sinopse || '';
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

// Scroll INSTANTÂNEO na TV, suave no desktop — ver `rolagem()` em spatial-nav.js.
// Segurando o D-pad, scroll animado a cada 150 ms se atropela e a tela pula.
const _rolagem = () => { try { return window.HP_rolagem ? window.HP_rolagem() : 'smooth'; } catch (_) { return 'smooth'; } };

// Foco num pôster: scroll horizontal (fila) + vertical (título do trilho sob o
// hero fixo) — sem isso o primeiro trilho não subia e o título sumia.
function focarPoster(el) {
  const fila = el.closest('.trilho-fila');
  if (fila) {
    const r = el.getBoundingClientRect(), fr = fila.getBoundingClientRect();
    fila.scrollTo({ left: fila.scrollLeft + (r.left - fr.left) - fr.width / 2 + r.width / 2, behavior: _rolagem() });
  }
  focarTrilho(el);
}

// Traz o trilho do elemento para logo ABAIXO do hero fixo. Vale para o pôster e
// para o título do trilho (que também é focável — abre a categoria inteira).
function focarTrilho(el) {
  const cont = document.getElementById('conteudo');
  const trilho = el.closest('.trilho');
  const hero = document.getElementById('hero2');
  if (!cont || !trilho) return;
  const heroH = hero ? hero.offsetHeight : 0;
  // +60: deixa o título ABAIXO do gradiente de transição (não escurecido).
  const delta = trilho.getBoundingClientRect().top - cont.getBoundingClientRect().top - heroH - 60;
  cont.scrollBy({ top: delta, behavior: _rolagem() });
}

// Foco num item do DETALHE (títulos semelhantes / elenco).
//
// O `scrollIntoView('nearest')` do SpatialNav encosta o item na borda do
// recorte: embaixo ele alinha a base do pôster com a base da tela, e na
// horizontal alinha com a borda da fila. Só que o anel de foco (box-shadow) e o
// crescimento de 8% ficam FORA da caixa que ele considera — e é justamente
// isso que aparecia cortado embaixo, à direita e à esquerda. Aqui o item nunca
// chega na borda: centraliza na fila e traz a seção inteira pro topo.
function focarItemDetalhe(el) {
  const fila = el.closest('.det2-fila');
  if (fila) {
    const r = el.getBoundingClientRect(), fr = fila.getBoundingClientRect();
    fila.scrollTo({ left: fila.scrollLeft + (r.left - fr.left) - fr.width / 2 + r.width / 2, behavior: _rolagem() });
  }
  const sc = document.getElementById('det2-scroll');
  const sec = el.closest('.det2-secao');
  if (sc && sec) {
    // 40px de folga acima do título da seção.
    const alvo = sc.scrollTop + (sec.getBoundingClientRect().top - sc.getBoundingClientRect().top) - 40;
    sc.scrollTo({ top: Math.max(0, alvo), behavior: _rolagem() });
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
function _executarFila(tarefas, conc, valido, pausar) {
  return new Promise((resolve) => {
    let i = 0, ativos = 0, fechado = false;
    const fim = () => { if (!fechado && ativos === 0 && i >= tarefas.length) { fechado = true; resolve(); } };
    (function pump() {
      if (fechado) return;
      if (valido && !valido()) { fechado = true; resolve(); return; }
      // PAUSA (só background): enquanto uma tela pesada (detalhe/player) está aberta,
      // NÃO dispara novas tarefas — libera as conexões do browser p/ o foreground.
      // As já em voo terminam; a fila retoma sozinha quando a tela fecha.
      if (pausar && pausar()) { setTimeout(pump, 250); return; }
      while (ativos < conc && i < tarefas.length) {
        ativos++;
        Promise.resolve(tarefas[i++]()).catch(() => {}).finally(() => { ativos--; fim(); setTimeout(pump, 30); });
      }
      fim();
    })();
  });
}
// Foreground "ocupado": detalhe/player abertos → o background pausa p/ o TMDB da
// tela atual carregar na frente.
const _focoOcupado = () => !!document.querySelector('#detalhe-overlay, .player-modal');

// Pré-carrega o PÔSTER de um item (o que aparece nos trilhos), aquecendo o cache
// do browser. Filme com logo próprio → aquece a URL da lista; série/filme sem
// logo → pôster do TMDB. Cobre TUDO (filmes E séries), não só séries.
function _precarregarPoster(it) {
  if (it.tipo !== 'serie' && it.logo) { _aquece(it.logo); return Promise.resolve(); }
  return TMDB.poster(it.titulo, it.tipo === 'serie').then(_aquece);
}

// ── MODO TV (webOS/Tizen) — leve p/ pouca RAM ───────────────────────────────
// Um pôster 500px decodificado custa ~1,5 MB de RAM. Numa lista real (centenas de
// itens) o predload de TUDO + guardar catálogos em memória estoura e a TV reinicia.
// Na TV: sem preload do catálogo, imagens VIRTUALIZADAS (descarrega fora da tela),
// menos concorrência e DOM menor. No desktop, comportamento normal.
const EH_TV = /web[0o]s|tizen|netcast|smart-?tv/i.test(navigator.userAgent);
if (EH_TV) { try { document.documentElement.classList.add('tv'); } catch (_) {} }
// Botão VOLTAR visível (SÓ na TV): em muitas TVs o botão Voltar do controle FECHA
// o app no nível do sistema (nada em JS impede). Este botão focável garante voltar
// pelo D-pad em telas que só saíam pelo Voltar. Vai no topo-esquerda do overlay.
// Etiqueta discreta de versão + largura da tela, mostrada nas telas em que o
// usuário PARA (onboarding e aviso de teste).
//
// Existe por um caso real: o app numa TV Philips (Google TV) aparecia espremido
// e não havia como saber, olhando a tela, se aquela TV tinha a versão nova — a
// tela "Sobre" trazia um `1.0.0-beta` fixo, igual em toda release. Com isto, uma
// FOTO da tela responde as duas perguntas: qual versão, e se a TV respeitou a
// viewport de 1600 (se vier um número bem menor, é ela que está espremendo).
function etiquetaVersao() {
  const v = (typeof APP_VERSAO === 'string' && APP_VERSAO) || '?';
  return `v${v} · ${window.innerWidth}×${window.innerHeight}`;
}

function htmlVoltar() {
  if (!EH_TV) return '';
  return '<button class="tela-voltar focusable" data-acao="tela-voltar" aria-label="Voltar">'
    + '<svg viewBox="0 0 24 24"><path d="M15 18l-6-6 6-6" stroke="currentColor" stroke-width="2.6" fill="none" stroke-linecap="round" stroke-linejoin="round"/></svg>'
    + ' ' + escapar(t('Voltar')) + '</button>';
}
const PRELOAD_CONC = EH_TV ? 2 : 5;
const OBS_MARGIN = EH_TV ? '350px' : '1600px';   // TV: carrega pouco à frente

// 1) Pré-carrega (AGUARDANDO, com teto) o HERO dos itens iniciais + os PÔSTERES
//    do topo de TODAS as seções (filmes E séries) — p/ rolar um pouco já achar
//    carregado. 2) Quando termina, dispara o RESTO (tudo) em background. O teto
//    só libera a tela de loading; o preload continua rodando.
async function precarregarBanners() {
  if (EH_TV) {
    // TV: aquece só o hero do 1º item (abre rápido). Pôsteres carregam sob demanda
    // (lazy) e o catálogo NÃO é pré-carregado — evita estourar a memória.
    const ini = _itensIniciaisDeExibicao(1);
    await Promise.race([
      _executarFila(ini.map((it) => () => _precarregarHero(it)), 1),
      new Promise((r) => setTimeout(r, 2500)),
    ]);
    return;
  }
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

// Aquece uma imagem RESOLVENDO no load/erro (p/ a fila limitar a concorrência real).
function _aquecerImg(url) {
  return new Promise((resolve) => {
    if (!url) return resolve();
    const im = new Image();
    im.onload = im.onerror = () => resolve();
    im.src = url;
  });
}
// Pré-carrega os ÍCONES dos canais ao vivo — 1 por canal AGRUPADO (cada
// LISTA.canais já é um grupo com um único `logo`). Background, com pausa quando o
// player está aberto e cancelamento ao trocar de playlist (token).
let _logosToken = 0;
function precarregarLogosCanais() {
  if (EH_TV) return Promise.resolve();   // TV: ícones carregam ao renderizar a lista (lazy)
  const meu = ++_logosToken;
  const tarefas = (LISTA.canais || []).filter((c) => c.logo).map((c) => () => _aquecerImg(c.logo));
  return _executarFila(tarefas, PRELOAD_CONC, () => meu === _logosToken, _focoOcupado);
}

// Background: PÔSTER de TUDO (filmes + séries) + hero (backdrop/logo) dos demais,
// com concorrência limitada. Garante que o catálogo inteiro fique pré-carregado.
let _fundoToken = 0;
function precarregarFundo(idsHeroFeitos) {
  if (EH_TV) return Promise.resolve();   // TV: NÃO pré-carrega o catálogo inteiro (memória)
  const meu = ++_fundoToken;
  const feitos = idsHeroFeitos || new Set();
  const todos = [...(LISTA.filmes || []), ...(LISTA.series || [])];
  const tarefas = [
    ...todos.map((it) => () => _precarregarPoster(it)),                       // pôster de tudo
    ...todos.filter((it) => !feitos.has(it.id)).map((it) => () => _precarregarHero(it)), // hero dos demais
  ];
  return _executarFila(tarefas, PRELOAD_CONC, () => meu === _fundoToken, _focoOcupado);
}

// Lazy: pôster TMDB ao entrar na viewport (com margem grande p/ carregar bem
// ANTES de aparecer). Usa o cache NA HORA (pré-carregado); senão busca. Sem
// imagem do TMDB → fica só o nome (gradiente), NUNCA o thumb do episódio.
let _obsPoster = null;
function ligarPostersSerie(raiz) {
  if (!('IntersectionObserver' in window)) return;
  if (_obsPoster) _obsPoster.disconnect();
  const MAX_TENT = 3;   // desiste após 3 falhas → fica só o fallback (preto + logo)
  const aplicar = (el, url) => {
    const arte = el.querySelector('.poster-arte');
    // já tem imagem OU já está carregando (re-observado num diff) → não duplica.
    if (!arte || arte.classList.contains('tem-img') || arte.dataset.carregando) return;
    if (!url) return;   // sem pôster no TMDB → fica o fallback
    arte.dataset.carregando = '1';
    const img = new Image();
    img.className = 'poster-img';
    img.onload = () => { arte.classList.add('tem-img'); arte.appendChild(img); };
    img.onerror = () => { delete arte.dataset.carregando; el.dataset.tent = (+(el.dataset.tent || 0)) + 1; };
    img.src = url;
  };
  const descarregar = (el) => {
    const arte = el.querySelector('.poster-arte');
    if (!arte) return;
    const img = arte.querySelector('img.poster-img');
    if (img) { img.onload = img.onerror = null; img.src = ''; img.remove(); }
    arte.classList.remove('tem-img'); delete arte.dataset.carregando;
  };
  // TV: antes descarregávamos a imagem assim que ela saía da margem — o que fazia
  // o pôster RECARREGAR ao voltar no carrossel (o cache de disco da TV é fraco).
  // Agora mantemos as últimas N em memória e só descarregamos a mais ANTIGA
  // quando passa do orçamento: ir e voltar não recarrega nada, e a RAM fica presa.
  // 60 era baixo demais: quem rola vários trilhos passa disso e as primeiras
  // imagens somem, "recarregando" ao voltar. Com o heap medido em 19% do orçamento
  // (54/290 MB) dá p/ segurar ~200 pôsteres (~40 MB decodificados) sem risco.
  const LIMITE_VIVAS = 200;
  const _vivas = [];                    // ordem de uso — o fim é o mais recente
  const tocar = (el) => {
    const i = _vivas.indexOf(el);
    if (i >= 0) _vivas.splice(i, 1);
    _vivas.push(el);
    while (_vivas.length > LIMITE_VIVAS) descarregar(_vivas.shift());
  };
  _obsPoster = new IntersectionObserver((ents) => {
    for (const e of ents) {
      const el = e.target;
      if (!e.isIntersecting) continue;   // TV: quem descarrega é o LRU (tocar)
      if (EH_TV) tocar(el);
      if (+(el.dataset.tent || 0) >= MAX_TENT) { _obsPoster.unobserve(el); continue; }  // desistiu (3 falhas)
      const ehSerie = el.dataset.serie === '1';
      const cache = TMDB.posterCache(el.dataset.tmdb, ehSerie);   // pré-carregado → instantâneo
      if (cache !== null) { if (!EH_TV) _obsPoster.unobserve(el); aplicar(el, cache); continue; }
      if (!EH_TV) _obsPoster.unobserve(el);              // desktop: busca 1x; TV: mantém p/ virtualizar
      const obs = _obsPoster;
      TMDB.poster(el.dataset.tmdb, ehSerie).then((u) => {
        aplicar(el, u);
        // Falha de REDE/rate-limit (não cacheada) → conta tentativa; re-tenta até 3x.
        if (!u && obs === _obsPoster && el.isConnected && TMDB.posterCache(el.dataset.tmdb, ehSerie) === null) {
          el.dataset.tent = (+(el.dataset.tent || 0)) + 1;
          if (!EH_TV && +(el.dataset.tent || 0) < MAX_TENT) obs.observe(el);
        }
      });
    }
  }, { rootMargin: OBS_MARGIN });   // desktop: ~1,5 tela à frente; TV: pouco (memória)
  (raiz || document).querySelectorAll('.poster[data-tmdb]').forEach((p) => _obsPoster.observe(p));
}

// ── TV ao vivo: 2 colunas (categorias↔canais | preview + EPG) ───────────────
let _tvCategoriaAtiva = null;
let _tvCanalPreview = null;
let _hlsPrev = null;

let _favoritos = new Set();                     // por perfil (Biblioteca)
function recarregarFavoritos() { _favoritos = Biblioteca.favoritos(); }
recarregarFavoritos();
function salvarFavoritos() { Biblioteca.salvarFavoritos(_favoritos); }

const IC_STAR = (on) => on
  ? '<svg viewBox="0 0 24 24"><path d="M12 2l2.9 6.26L22 9.27l-5 4.87 1.18 6.88L12 17.77 5.82 21l1.18-6.88-5-4.87 7.1-1.01z"/></svg>'
  : '<svg viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="1.7" stroke-linejoin="round"><path d="M12 2l2.9 6.26L22 9.27l-5 4.87 1.18 6.88L12 17.77 5.82 21l1.18-6.88-5-4.87 7.1-1.01z"/></svg>';

// Ícones da Minha Lista: "+" (fora) e "✓" PREENCHIDO (dentro). O check é filled
// porque `.btn svg { fill: currentColor }` preencheria um checkmark de traço aberto.
const IC_MAIS = '<svg viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="2.4" stroke-linecap="round"><path d="M12 5v14M5 12h14"/></svg>';
const IC_OK = '<svg viewBox="0 0 24 24"><path d="M9.55 17.6 4.4 12.45l1.5-1.5 3.65 3.65L18.1 6.15l1.5 1.5z"/></svg>';

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
    `<div class="tv-cat-item focusable" data-cat="__fav"><span class="tv-cat-nome">${escapar(t('Favoritos'))}</span>${CHEV_R}</div>`,
    ...categorias().map((cat) =>
      `<div class="tv-cat-item focusable" data-cat="${escapar(cat)}"><span class="tv-cat-nome">${escapar(cat)}</span>${CHEV_R}</div>`),
  ].join('');
  return `<div class="tv-lista tv-anim-esq"><div class="tv-lista-cab">${escapar(t('Categorias'))}</div>${itens}</div>`;
}

// Conteúdo de uma "caixa de logo" de canal: o logo REAL da playlist (tvg-logo)
// quando existe, com fallback p/ iniciais no gradiente. Ao carregar a imagem,
// marca o pai com .tem-img (esconde as iniciais); se falhar, some e fica o gradiente.
function logoCanalInner(nome, logoUrl, lazy) {
  // `loading="lazy"` não existe no Chromium 68 (webOS 5) → carregaria TUDO de uma
  // vez. Em LISTA (lazy=true) usamos data-logo + observer (ligarLogosCanais);
  // em logo único (preview/live) carregamos direto.
  const attr = logoUrl ? (lazy ? `data-logo="${escapar(logoUrl)}"` : `src="${escapar(logoUrl)}"`) : '';
  const img = logoUrl
    ? `<img class="canal-logo-img" ${attr} alt="" onload="this.parentNode.classList.add('tem-img')" onerror="this.remove()">`
    : '';
  return `${img}<span>${escapar(iniciais(nome))}</span>`;
}

// Lazy + virtualização dos LOGOS dos canais (lista pode ter centenas). Carrega ao
// entrar na viewport; na TV descarrega ao sair (libera RAM).
let _obsCanalLogo = null;
function ligarLogosCanais(raiz) {
  const alvos = (raiz || document).querySelectorAll('.canal-logo-img[data-logo]');
  if (!('IntersectionObserver' in window)) { alvos.forEach((im) => { im.src = im.dataset.logo; }); return; }
  if (_obsCanalLogo) _obsCanalLogo.disconnect();
  _obsCanalLogo = new IntersectionObserver((ents) => {
    for (const e of ents) {
      const im = e.target;
      if (e.isIntersecting) { if (!im.getAttribute('src') && im.dataset.logo) im.src = im.dataset.logo; if (!EH_TV) _obsCanalLogo.unobserve(im); }
      else if (EH_TV && im.getAttribute('src')) { im.removeAttribute('src'); if (im.parentNode) im.parentNode.classList.remove('tem-img'); }
    }
  }, { rootMargin: EH_TV ? '300px' : '1200px' });
  alvos.forEach((im) => _obsCanalLogo.observe(im));
}

function _itemCanalHTML(c) {
  return `<div class="tv-canal-item" data-canal="${c.id}">
       <div class="tv-canal-main focusable" data-canal="${c.id}">
         <div class="tv-canal-logo" style="background:${gradiente(c.nome, true)}">${logoCanalInner(c.nome, c.logo, true)}</div>
         <div class="tv-canal-txt">
           <div class="tv-canal-nome">${c.num} · ${escapar(c.nome)}</div>
           <div class="tv-canal-agora"><span class="tv-live-dot"></span><span class="tv-canal-prog">${rotuloAgora(c)}</span></div>
         </div>
       </div>
       <button class="tv-canal-fav focusable${_favoritos.has(c.id) ? ' ativo' : ''}" data-canal="${c.id}" data-acao="fav-lista" aria-label="${escapar(t('Favoritar'))}">${IC_STAR(_favoritos.has(c.id))}</button>
     </div>`;
}

// Categorias grandes (ex.: "SPORTS WORLD", "DESENHOS 24 HORAS") têm MILHARES de
// canais. Montar tudo de uma vez congelava a TV — a string, o parse de HTML e o
// registro dos focáveis num só frame. Renderizamos o primeiro lote (que já enche
// a tela) e o resto em fatias, sem bloquear o D-pad.
const CANAIS_LOTE = EH_TV ? 40 : 200;
function htmlCanais(cat, lista) {
  const nome = cat === '__fav' ? t('Favoritos') : cat;
  const itens = lista.slice(0, CANAIS_LOTE).map(_itemCanalHTML).join('');
  return `<div class="tv-lista tv-anim-dir">
    <div class="tv-lista-cab">${CHEV_L} ${escapar(nome)}</div>
    ${itens}
  </div>`;
}

// Token: se o usuário trocar de categoria (ou voltar) no meio, a fatia pendente
// é descartada em vez de despejar canais da categoria antiga na tela.
let _canaisToken = 0;
function anexarCanaisRestantes(pane, lista, cat) {
  const meu = ++_canaisToken;
  let i = CANAIS_LOTE;
  const passo = () => {
    if (meu !== _canaisToken || _tvCategoriaAtiva !== cat) return;
    const alvo = pane.querySelector('.tv-lista');
    if (!alvo || !alvo.isConnected) return;
    const frag = document.createElement('div');
    frag.innerHTML = lista.slice(i, i + CANAIS_LOTE).map(_itemCanalHTML).join('');
    while (frag.firstChild) alvo.appendChild(frag.firstChild);
    ligarLogosCanais(alvo);
    i += CANAIS_LOTE;
    if (i < lista.length) requestAnimationFrame(passo);
  };
  requestAnimationFrame(passo);
}

function htmlPreviewVazio() {
  return `<div class="tv-preview tv-preview-vazio">
    <div class="tv-vazio-logo">▶</div>
    <div class="tv-vazio-titulo">${escapar(t('Canais ao vivo'))}</div>
    <div class="tv-vazio-sub">${escapar(t('Selecione uma categoria e um canal'))}</div>
  </div>`;
}

// Rótulo do programa atual p/ a lista/preview: "AGORA: <programa>" (ou "Ao vivo"
// quando não há EPG casado p/ o canal).
// Retorna HTML: "AGORA:" em negrito + o programa (escapado). Sem EPG → "Ao vivo".
function rotuloAgora(c) {
  const prog = (EPG.agora(c).atual || {}).titulo || c.agora;
  return prog ? `<b class="tv-agora-lbl">${escapar(t('AGORA'))}:</b> ${escapar(prog)}` : escapar(t('Ao vivo'));
}

function htmlEpg(c) {
  const prox = EPG.proximos(c, 6);   // EPG real (XMLTV do Xtream), se houver
  if (prox.length) {
    const now = Date.now();
    return `<div class="tv-prog-lista">${prox.map((p) => {
      const atual = p.ini <= now && now < p.fim;
      return `<div class="tv-prog-row${atual ? ' atual' : ''}">
         <span class="tv-prog-hora">${atual ? t('AGORA') : hhmm(new Date(p.ini))}</span><span class="tv-prog-nome">${escapar(p.titulo)}</span>
       </div>`;
    }).join('')}</div>`;
  }
  // Fallback (sem EPG p/ este canal): só o "agora".
  return `<div class="tv-prog-lista">
    <div class="tv-prog-row atual"><span class="tv-prog-hora">${t('AGORA')}</span><span class="tv-prog-nome">${escapar(c.agora || t('Ao vivo'))}</span></div>
  </div>`;
}

// Baixa o EPG (XMLTV do Xtream) em 2º plano, 1x por lista. Ao concluir, atualiza
// os rótulos "agora" da lista + o painel da preview (best-effort; falha → fallback).
function carregarEpgSeNecessario() {
  const reg = Dispositivo.registro();
  let url = reg && reg.epg_url;
  // Sem epg_url salvo? deriva de get.php → xmltv.php (mesmas credenciais Xtream).
  if (!url && reg && reg.lista_url && typeof ListaUtil !== 'undefined') url = ListaUtil.derivarEpg(reg.lista_url);
  if (!url) return;
  EPG.carregar(url, LISTA.canais || []).then((ok) => { if (ok && document.querySelector('.tv-vivo')) atualizarEpgNaTela(); });
}
function atualizarEpgNaTela() {
  const mapa = {};
  for (const c of (LISTA.canais || [])) mapa[c.id] = c;   // O(1) por linha (evita find O(n²))
  document.querySelectorAll('.tv-canal-item').forEach((row) => {
    const c = mapa[row.dataset.canal]; if (!c) return;
    const el = row.querySelector('.tv-canal-prog');
    if (el) el.innerHTML = rotuloAgora(c);
  });
  if (_tvCanalPreview) {
    const area = document.getElementById('tv-prog-area'); if (area) area.innerHTML = htmlEpg(_tvCanalPreview);
    const pa = document.getElementById('tv-prev-agora'); if (pa) pa.innerHTML = rotuloAgora(_tvCanalPreview);
  }
}

// Estrutura FIXA do preview (criada uma vez). O <video> persiste entre canais —
// so trocamos a fonte e os textos; recriar o elemento deixava a tela preta.
function htmlPreviewShell() {
  return `<div class="tv-preview tv-anim-dir">
    <div class="tv-tela focusable" data-acao="tela">
      <video id="tv-prev-video" playsinline muted></video>
      <div class="tv-tela-hint">
        <svg viewBox="0 0 24 24" fill="none" stroke="#fff" stroke-width="2" stroke-linecap="round" stroke-linejoin="round"><path d="M8 3H5a2 2 0 0 0-2 2v3M21 8V5a2 2 0 0 0-2-2h-3M3 16v3a2 2 0 0 0 2 2h3M16 21h3a2 2 0 0 0 2-2v-3"/></svg>
        ${escapar(t('Abrir em tela cheia'))}
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
      <div class="tv-prog-titulo">${escapar(t('Programação'))}</div>
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

function mostrarCanais(cat, _okPin) {
  const lista = canaisDaCategoria(cat);
  if (cat === '__fav' && lista.length === 0) { toast(t('Nenhum canal favoritado ainda')); return; }
  // Controle dos pais: categoria bloqueada pede PIN antes de abrir.
  if (!_okPin && typeof canalCatBloqueada === 'function' && canalCatBloqueada(cat)) {
    pedirPin(() => mostrarCanais(cat, true)); return;
  }
  _tvCategoriaAtiva = cat;
  const pane = document.getElementById('tv-pane-canais');
  pane.innerHTML = htmlCanais(cat, lista);
  ligarLogosCanais(pane);          // logos lazy (não carrega centenas de uma vez)
  if (lista.length > CANAIS_LOTE) anexarCanaisRestantes(pane, lista, cat);
  // As categorias continuam visiveis a esquerda (recuadas + fade); ver CSS.
  document.getElementById('tv-panes').classList.add('com-canais');
  const primeiro = pane.querySelector('.focusable');
  if (primeiro) SpatialNav.setFocus(primeiro);
}

function mostrarCategorias() {
  const anterior = _tvCategoriaAtiva;   // categoria que estava aberta (p/ voltar o foco a ela)
  _tvCategoriaAtiva = null;
  document.getElementById('tv-panes').classList.remove('com-canais');
  const pane = document.getElementById('tv-pane-canais');
  if (pane) pane.innerHTML = ''; // limpa p/ nao deixar canais focaveis escondidos
  // Volta o foco à categoria que estava SELECIONADA (não à primeira), preservando
  // a seção escolhida — independente de onde o foco andou na lista de canais.
  const cats = [...document.querySelectorAll('#tv-pane-cat .tv-cat-item')];
  const alvo = (anterior && cats.find((el) => el.dataset.cat === anterior))
    || document.querySelector('#tv-pane-cat .focusable');
  if (alvo) SpatialNav.setFocus(alvo);
}

// Encerra a reprodução e LIBERA a conexão do <video>. Sem o removeAttribute+load()
// o socket do stream continua aberto (o servidor IPTV segue contando a sessão),
// e depois de alguns vídeos estoura o limite de telas simultâneas.
function liberarVideo(v) {
  if (!v) return;
  try {
    v.pause();
    v.removeAttribute('src');
    while (v.firstChild) v.removeChild(v.firstChild);   // <source> se houver
    v.load();                                            // aborta o carregamento em curso
  } catch (_) { /* best-effort */ }
}

function pararPreview() {
  if (_hlsPrev) { _hlsPrev.destroy(); _hlsPrev = null; }
  if (TEM_PLAYER_NATIVO) PlayerNativo.parar();
  liberarVideo(document.getElementById('tv-prev-video'));
}

// (Re)carrega o video do preview (coluna direita). Reusado ao voltar da tela cheia.
// Toca uma URL no <video> do preview (reusado na tela cheia). Troca de
// qualidade/fonte chama isto com a URL nova.
// Casca Android (Fire TV / TV Box): a ponte nativa só existe lá. Serve para
// separar o WebView do Chromium das TVs de verdade — nas TVs NADA muda.
const EH_ANDROID_TV = (function () { try { return !!window.HeroPlayAndroid; } catch (_) { return false; } })();
const TEM_PLAYER_NATIVO = (function () {
  try { return EH_ANDROID_TV && !!HeroPlayAndroid.temPlayer && HeroPlayAndroid.temPlayer(); } catch (_) { return false; }
})();

// ── Player NATIVO (ExoPlayer) da casca Android ──────────────────────────────
// O `<video>` do WebView só abre MP4/WebM: filme 4K (MKV) e canal ao vivo
// (MPEG-TS) não tocam. Na TV isso não acontece porque lá o `<video>` É o player
// do sistema. Então, no Android, mandamos a reprodução para o ExoPlayer — que
// fica ATRÁS do WebView — e devolvemos para a interface um objeto com a MESMA
// cara de um <video> (play/pause/currentTime/duration/addEventListener).
// Assim `abrirPlayer` e `tocarNoPreview` não precisam saber onde estão rodando.
const PlayerNativo = (function () {
  const ouvintes = {};
  let timer = null, ultimo = { pos: 0, dur: 0, tocando: false, buffering: false };
  let elDest = null;           // elemento cuja área o vídeo deve ocupar
  let pausadoManual = false;
  let ultimoErro = '';         // código do ExoPlayer, p/ a mensagem de erro

  function emitir(nome) {
    (ouvintes[nome] || []).slice().forEach((fn) => { try { fn({ type: nome }); } catch (_) {} });
  }
  function ler() {
    try { ultimo = JSON.parse(HeroPlayAndroid.estado()); } catch (_) {}
    return ultimo;
  }
  // Acompanha o retângulo do elemento: preview da TV ao vivo e tela cheia usam
  // áreas diferentes, e a superfície nativa tem que casar com as duas.
  function sincronizarArea() {
    if (!elDest) return;
    const r = elDest.getBoundingClientRect();
    // Manda o tamanho da VIEWPORT junto: é ele que dá ao lado nativo o fator
    // exato de CSS px → pixel de tela. Sem isso o Kotlin chutava pela densidade
    // do aparelho e a superfície saía deslocada (vídeo fora da moldura).
    try { HeroPlayAndroid.area(r.left, r.top, r.width, r.height, window.innerWidth, window.innerHeight); } catch (_) {}
    // Ocupando (quase) a tela toda? Então o resto do app tem que sumir — com a
    // página transparente ele apareceria POR CIMA do vídeo.
    const cheio = r.width >= window.innerWidth * 0.92 && r.height >= window.innerHeight * 0.92;
    try { document.documentElement.classList.toggle('video-nativo-cheio', cheio); } catch (_) {}
  }
  function iniciarTick() {
    if (timer) return;
    timer = setInterval(() => {
      const e = ler();
      sincronizarArea();
      emitir('timeupdate');
      if (e.buffering) emitir('waiting');
    }, 500);
  }
  function pararTick() { if (timer) { clearInterval(timer); timer = null; } }

  // Chamado pelo lado Kotlin (MainActivity.aoEvento).
  window.HeroPlayNativo = {
    evento(nome) {
      if (nome.indexOf('error') === 0) {          // "error:CODIGO_DO_EXOPLAYER"
        ultimoErro = nome.slice(6);
        emitir('error');
        return;
      }
      if (nome === 'playing') { pausadoManual = false; emitir('playing'); emitir('play'); }
      else if (nome === 'pause') emitir('pause');
      else if (nome === 'canplay') { emitir('loadedmetadata'); emitir('canplay'); }
      else emitir(nome);
    },
  };

  return {
    /** Liga o player nativo a um elemento: ele passa a ocupar a área dele. */
    abrir(el, url, posicaoSeg, mudo) {
      elDest = el;
      pausadoManual = false;
      ultimoErro = '';
      try { document.documentElement.classList.add('video-nativo'); } catch (_) {}
      sincronizarArea();
      try { HeroPlayAndroid.abrir(url, posicaoSeg || 0, !!mudo); } catch (_) {}
      _mudoNativo = !!mudo;
      iniciarTick();
      emitir('loadstart');
    },
    parar() {
      pararTick();
      elDest = null;
      try { HeroPlayAndroid.parar(); } catch (_) {}
      try {
        document.documentElement.classList.remove('video-nativo');
        document.documentElement.classList.remove('video-nativo-cheio');
      } catch (_) {}
    },
    /** Código do último erro do ExoPlayer (ex.: ERROR_CODE_IO_BAD_HTTP_STATUS). */
    erro() { return ultimoErro; },
    /** Faixas do que está tocando: `{audio:[{i,rotulo,sel}], texto:[…]}`. */
    faixas() {
      try { return JSON.parse(HeroPlayAndroid.faixas()); } catch (_) { return { audio: [], texto: [] }; }
    },
    /** Escolhe faixa. tipo: 'audio'|'texto'; i < 0 em 'texto' desliga a legenda. */
    selFaixa(tipo, i) { try { HeroPlayAndroid.faixa(tipo, i); } catch (_) {} },
    /** Objeto com cara de <video> para a interface existente. */
    fachada(el) {
      return {
        _el: el,
        get currentTime() { return ler().pos; },
        set currentTime(v) { try { HeroPlayAndroid.buscar(v); } catch (_) {} },
        get duration() { return ler().dur; },
        get paused() { return pausadoManual || !ler().tocando; },
        get muted() { return false; },
        set muted(v) { try { HeroPlayAndroid.mudo(!!v); } catch (_) {} },
        get textTracks() { return []; },
        get audioTracks() { return undefined; },
        // ⚠️ `ultimo.tocando` é atualizado OTIMISTA aqui. `paused` é lido do
        // retrato, que só se renova a cada 500 ms — então quem clicasse em
        // play/pause e perguntasse `paused` no mesmo instante recebia o valor
        // ANTIGO, e o ícone do botão ficava trocado (só acertava quando outro
        // evento chegava, tipo o de avançar). Assumir a intenção aqui deixa a
        // resposta correta na hora; o tick confirma logo depois.
        play() {
          pausadoManual = false; ultimo.tocando = true;
          try { HeroPlayAndroid.retomar(); } catch (_) {}
          return Promise.resolve();
        },
        pause() {
          pausadoManual = true; ultimo.tocando = false;
          try { HeroPlayAndroid.pausar(); } catch (_) {}
        },
        addEventListener(nome, fn) { (ouvintes[nome] = ouvintes[nome] || []).push(fn); },
        removeEventListener(nome, fn) {
          const l = ouvintes[nome]; if (!l) return;
          const i = l.indexOf(fn); if (i >= 0) l.splice(i, 1);
        },
      };
    },
    limparOuvintes() { for (const k in ouvintes) delete ouvintes[k]; },
  };
})();

// Canal ao vivo do Xtream costuma vir como MPEG-TS (`.../12345.ts` ou sem
// extensão). O player nativo da LG/Samsung toca isso; o WebView do Android
// NÃO — e era por isso que no TV Box o canal ficava "instável, trocando de
// fonte" para sempre, enquanto filme (.mp4) tocava normal.
// O mesmo canal existe em HLS no Xtream trocando a extensão para `.m3u8`, e
// esse o hls.js toca (remuxa o TS em MSE).
function _urlHlsEquivalente(url) {
  const i = url.indexOf('?');
  const caminho = i === -1 ? url : url.slice(0, i);
  const query = i === -1 ? '' : url.slice(i);
  if (/\.m3u8$/i.test(caminho)) return url;
  if (/\.(ts|m3u)$/i.test(caminho)) return caminho.replace(/\.[a-z0-9]+$/i, '.m3u8') + query;
  if (/\/[^/.]+$/.test(caminho)) return caminho + '.m3u8' + query;   // sem extensão
  return null;
}

// Dá play RESPEITANDO a política de autoplay: pede com som e, se a plataforma
// recusar (webOS/Tizen podem recusar áudio sem gesto), repete MUDO em vez de
// deixar o vídeo parado. Um `play()` recusado deixa o <video> pausado, e o que
// aparece na tela é o botão de play CINZA do sistema — foi o que voltou quando a
// preview passou a ter som.
/**
 * Mensagem HONESTA por código de erro do ExoPlayer.
 *
 * Antes tudo caía em "o formato pode exigir o player nativo da TV" — e num 403
 * do provedor isso manda o usuário investigar a coisa errada. Os códigos que
 * importam são poucos e dizem exatamente o que aconteceu.
 */
function mensagemErroPlayer(cod) {
  const c = String(cod || '');
  if (/BAD_HTTP_STATUS/.test(c)) {
    return t('O servidor da sua lista recusou a conexão. Costuma ser limite de telas simultâneas — feche o app nos outros aparelhos e tente de novo em alguns segundos.');
  }
  if (/IO_NETWORK|CONNECT_TIMEOUT|READ_TIMEOUT|NO_INTERNET/.test(c)) {
    return t('Falha de rede ao abrir o vídeo. Verifique a conexão da TV.');
  }
  if (/FILE_NOT_FOUND|INVALID_HTTP_CONTENT_TYPE/.test(c)) {
    return t('Este item não está mais disponível no servidor da sua lista.');
  }
  return t('Não foi possível reproduzir. O formato pode exigir o player nativo da TV.')
    + (c ? '  [' + c + ']' : '');
}

function tocarVideo(v, mudo) {
  if (!v) return;
  v.muted = !!mudo;
  try {
    const p = v.play();
    if (p && p.catch) p.catch(() => { v.muted = true; const r = v.play(); if (r && r.catch) r.catch(() => {}); });
  } catch (_) { /* navegador antigo: play() sem Promise */ }
}

function tocarNoPreview(url, muted) {
  const v = document.getElementById('tv-prev-video');
  if (!v || !url) return;
  monitorarVideoQualidade(v);            // 1x: travas/erros → auto-qualidade
  // Zera o monitor a cada nova reprodução: o <video> é REUSADO entre canais, então
  // travas/erros do canal anterior não podem contar pro novo. `_qIniciado` só vira
  // true quando o canal REALMENTE começa a tocar (evento 'playing').
  v._qStalls = 0; v._qT0 = 0; v._qIniciado = false; v._qPlayEm = 0;
  if (_hlsPrev) { _hlsPrev.destroy(); _hlsPrev = null; }
  const ehHls = /\.m3u8(\?|$)/i.test(url);
  const hlsNativo = !!v.canPlayType('application/vnd.apple.mpegurl');   // TV (webOS/Tizen): sim
  // PREFERE o player NATIVO da TV: toca .ts/.mkv/HEVC e HLS pela media pipeline do
  // sistema (mais compatível que o hls.js, que é SW e não decoda HEVC/.ts). Só usa
  // hls.js quando o nativo NÃO toca HLS (ex.: Chrome desktop no teste).
  // Android (Fire TV / TV Box): vai para o ExoPlayer, que toca MPEG-TS e HEVC
  // — o `<video>` do WebView não toca nenhum dos dois, e era por isso que o
  // canal ficava em "instável, trocando de fonte" para sempre.
  if (TEM_PLAYER_NATIVO) {
    PlayerNativo.abrir(v, url, 0, muted);
    return;
  }
  // Sem player nativo (navegador de teste): hls.js quando a URL for HLS.
  let alvo = url, viaHlsJs = ehHls && !hlsNativo;
  if (EH_ANDROID_TV && window.Hls && Hls.isSupported()) {
    const m3u8 = _urlHlsEquivalente(url);
    if (m3u8) { alvo = m3u8; viaHlsJs = true; }
  }
  if (!viaHlsJs && (!ehHls || hlsNativo)) {
    v.src = url;
    v.addEventListener('loadedmetadata', () => tocarVideo(v, muted), { once: true });
  } else if (window.Hls && Hls.isSupported()) {
    const convertida = alvo !== url;   // trocamos p/ o .m3u8 equivalente
    _hlsPrev = new Hls();
    _hlsPrev.on(Hls.Events.MANIFEST_PARSED, () => tocarVideo(v, muted));
    _hlsPrev.on(Hls.Events.ERROR, (_e, d) => {
      if (!d || !d.fatal) return;
      // O provedor pode não servir a variante .m3u8 daquele canal. Antes de
      // desistir e pular de fonte, tenta a URL ORIGINAL no player nativo.
      if (convertida) {
        if (_hlsPrev) { _hlsPrev.destroy(); _hlsPrev = null; }
        v.src = url;
        v.addEventListener('loadedmetadata', () => tocarVideo(v, muted), { once: true });
        return;
      }
      if (autoQualidadeOn() && _qAtual) autoTrocarFonte();
    });
    _hlsPrev.attachMedia(v);
    _hlsPrev.loadSource(alvo);
  } else {
    v.src = url;
    v.addEventListener('loadedmetadata', () => tocarVideo(v, muted), { once: true });
  }
}

// ── Qualidade dos canais ao vivo (preferência + auto-degradar/trocar fonte) ──
const _RANK_Q = { '4K': 4, 'FHD': 3, 'HD': 2, 'SD': 1, 'Padrão': 0 };
function autoQualidadeOn() { return localStorage.getItem(Perfis.chave('tv_auto_qualidade')) !== '0'; } // default ON, por perfil
function qualidadePadrao() { return localStorage.getItem(Perfis.chave('tv_qualidade_padrao')) || 'max'; }
// Fontes do canal: a PRINCIPAL (canal em si) + as alternativas (canal.fontes).
function fontesDoCanal(canal) {
  return [{ nome: t('Principal'), url: canal.url, variantes: canal.variantes || [] }, ...(canal.fontes || [])];
}
function variantesDaFonte(f) { return (f.variantes && f.variantes.length) ? f.variantes : [{ rotulo: 'Padrão', url: f.url }]; }
// Escolhe a variante conforme a preferência (max/fhd/hd/min).
function escolherVariante(vars, pref) {
  if (!vars || !vars.length) return null;
  const arr = vars.map((v) => ({ v, r: _RANK_Q[v.rotulo] != null ? _RANK_Q[v.rotulo] : 0 }));
  if (pref === 'max') return arr.reduce((a, b) => (b.r > a.r ? b : a)).v;
  if (pref === 'min') return arr.reduce((a, b) => (b.r < a.r ? b : a)).v;
  const cap = pref === 'fhd' ? 3 : 2;                       // fhd→≤FHD, hd→≤HD
  const abaixo = arr.filter((x) => x.r <= cap).sort((a, b) => b.r - a.r);
  return (abaixo[0] || arr.slice().sort((a, b) => a.r - b.r)[0]).v;
}
// No Android o som e do ExoPlayer: o `muted` do <video> (que nem toca nada la)
// nao significa nada. Guardamos o estado a parte.
let _mudoNativo = true;
function videoMutedAtual() {
  if (TEM_PLAYER_NATIVO) return _mudoNativo;
  const v = document.getElementById('tv-prev-video');
  return v ? v.muted : true;
}
/** Liga/desliga o som da reproducao ao vivo, no player que estiver valendo. */
function definirMudo(mudo) {
  if (TEM_PLAYER_NATIVO) {
    _mudoNativo = !!mudo;
    try { HeroPlayAndroid.mudo(!!mudo); } catch (_) {}
    return;
  }
  const v = document.getElementById('tv-prev-video');
  if (v) v.muted = !!mudo;
}

let _qAtual = null;   // { canal, fontes, fi, vi } — reprodução ativa (p/ auto-switch)
function tocarCanalAuto(canal, muted) {
  const fontes = fontesDoCanal(canal);
  const vars = variantesDaFonte(fontes[0]);
  const v = escolherVariante(vars, qualidadePadrao());
  _qAtual = { canal, fontes, fi: 0, vi: Math.max(0, vars.indexOf(v)) };
  tocarNoPreview((v || fontes[0]).url, muted);
}
// Travou demais → cai uma qualidade (mesma fonte); no fim, troca de fonte.
function autoDegradar() {
  if (!_qAtual) return;
  const vars = variantesDaFonte(_qAtual.fontes[_qAtual.fi]);
  if (_qAtual.vi < vars.length - 1) {
    _qAtual.vi++;
    const rot = vars[_qAtual.vi].rotulo;
    toast(t('Conexão instável — qualidade reduzida') + (rot ? ' (' + rot + ')' : ''));
    tocarNoPreview(vars[_qAtual.vi].url, videoMutedAtual());
  } else { autoTrocarFonte(); }
}
// Canal caiu (erro fatal) → próxima fonte, na qualidade preferida.
function autoTrocarFonte() {
  if (!_qAtual || _qAtual.fi >= _qAtual.fontes.length - 1) return;
  _qAtual.fi++;
  const vars = variantesDaFonte(_qAtual.fontes[_qAtual.fi]);
  const v = escolherVariante(vars, qualidadePadrao());
  _qAtual.vi = Math.max(0, vars.indexOf(v));
  toast(t('Canal instável — trocando de fonte…'));
  tocarNoPreview((v || _qAtual.fontes[_qAtual.fi]).url, videoMutedAtual());
}
// Monitor (1x por <video>): conta travas (waiting) e erros → auto-qualidade.
function monitorarVideoQualidade(v) {
  if (v._qMon) return; v._qMon = true;
  // O canal COMEÇOU a tocar → a partir daqui travas contam como instabilidade.
  // Zera o contador só no PRIMEIRO 'playing': ele também dispara ao sair de cada
  // trava, e zerar sempre impediria a contagem de chegar em 3.
  v.addEventListener('playing', () => {
    if (v._qIniciado) return;
    v._qIniciado = true; v._qPlayEm = Date.now(); v._qStalls = 0;
  });
  v.addEventListener('waiting', () => {
    if (!autoQualidadeOn() || !_qAtual) return;
    // Buffering INICIAL (canal ainda conectando/enchendo buffer) NÃO é instabilidade
    // — era isso que fazia trocar de fonte antes do canal sequer carregar.
    if (!v._qIniciado) return;
    if (Date.now() - (v._qPlayEm || 0) < 6000) return;                 // respiro após começar
    const now = Date.now();
    if (now - (v._qT0 || 0) > 20000) { v._qStalls = 0; v._qT0 = now; }  // janela de 20s
    v._qStalls = (v._qStalls || 0) + 1;
    if (v._qStalls >= 3) { v._qStalls = 0; autoDegradar(); }            // 3 travas → degrada
  });
  v.addEventListener('error', () => {
    if (!autoQualidadeOn() || !_qAtual) return;
    // MEDIA_ERR_ABORTED (1): o <video> abortou porque TROCAMOS a fonte/canal —
    // não é falha da fonte. Os demais (rede/decode/src inválido) sim.
    const err = v.error;
    if (err && err.code === 1) return;
    autoTrocarFonte();
  });
}

// ── Legendas e faixas de ÁUDIO ──────────────────────────────────────────────
// Duas fontes possíveis, nesta ordem:
//  1) hls.js (quando ELE está tocando): expõe subtitleTracks/audioTracks.
//  2) O próprio <video>: textTracks (legendas in-band/WebVTT) e audioTracks.
// ⚠️ `video.audioTracks` NÃO é implementado no Chromium (nem no da TV) — então em
// stream tocado pelo player NATIVO normalmente só há legenda; quando não há faixa
// alguma, avisamos em vez de fingir que trocou.
function _hlsDoVideo(v) {
  if (_hls && v === document.getElementById('player-video')) return _hls;
  if (_hlsPrev && v === document.getElementById('tv-prev-video')) return _hlsPrev;
  return null;
}
// ⚠️ ANDROID (TV Box/Fire TV) entra ANTES de tudo nestes seis helpers: lá quem
// toca é o ExoPlayer, atrás do WebView, e o <video> da página não tem faixa
// nenhuma para expor (era por isso que o CC no TV Box dizia sempre "este
// conteúdo não oferece legendas", enquanto no celular funcionava). As faixas
// vêm da ponte nativa — ver PlayerNativo.faixas() e PlayerNativo.kt.
function faixasLegenda(v) {
  if (TEM_PLAYER_NATIVO) return PlayerNativo.faixas().texto.map((f) => ({ i: f.i, rotulo: f.rotulo }));
  const hls = _hlsDoVideo(v);
  if (hls && hls.subtitleTracks && hls.subtitleTracks.length) {
    return hls.subtitleTracks.map((tr, i) => ({ i, rotulo: tr.name || tr.lang || (t('Legenda') + ' ' + (i + 1)) }));
  }
  const tt = v.textTracks || [];
  const out = [];
  for (let i = 0; i < tt.length; i++) {
    if (tt[i].kind && tt[i].kind !== 'subtitles' && tt[i].kind !== 'captions') continue;
    out.push({ i, rotulo: tt[i].label || tt[i].language || (t('Legenda') + ' ' + (i + 1)) });
  }
  return out;
}
function legendaAtual(v) {
  if (TEM_PLAYER_NATIVO) { const s = PlayerNativo.faixas().texto.find((f) => f.sel); return s ? s.i : -1; }
  const hls = _hlsDoVideo(v);
  if (hls && hls.subtitleTracks && hls.subtitleTracks.length) return hls.subtitleDisplay === false ? -1 : hls.subtitleTrack;
  const tt = v.textTracks || [];
  for (let i = 0; i < tt.length; i++) if (tt[i].mode === 'showing') return i;
  return -1;
}
function selecionarLegenda(v, i) {          // i = -1 → desativar
  if (TEM_PLAYER_NATIVO) { PlayerNativo.selFaixa('texto', i); return; }
  const hls = _hlsDoVideo(v);
  if (hls && hls.subtitleTracks && hls.subtitleTracks.length) {
    hls.subtitleDisplay = i >= 0; hls.subtitleTrack = i; return;
  }
  const tt = v.textTracks || [];
  for (let k = 0; k < tt.length; k++) tt[k].mode = (k === i) ? 'showing' : 'disabled';
}
function faixasAudio(v) {
  if (TEM_PLAYER_NATIVO) return PlayerNativo.faixas().audio.map((f) => ({ i: f.i, rotulo: f.rotulo }));
  const hls = _hlsDoVideo(v);
  if (hls && hls.audioTracks && hls.audioTracks.length) {
    return hls.audioTracks.map((tr, i) => ({ i, rotulo: tr.name || tr.lang || (t('Áudio') + ' ' + (i + 1)) }));
  }
  const at = v.audioTracks;                 // undefined no Chromium
  const out = [];
  if (at) for (let i = 0; i < at.length; i++) out.push({ i, rotulo: at[i].label || at[i].language || (t('Áudio') + ' ' + (i + 1)) });
  return out;
}
function audioAtual(v) {
  if (TEM_PLAYER_NATIVO) { const s = PlayerNativo.faixas().audio.find((f) => f.sel); return s ? s.i : -1; }
  const hls = _hlsDoVideo(v);
  if (hls && hls.audioTracks && hls.audioTracks.length) return hls.audioTrack;
  const at = v.audioTracks;
  if (at) for (let i = 0; i < at.length; i++) if (at[i].enabled) return i;
  return -1;
}
function selecionarAudio(v, i) {
  if (TEM_PLAYER_NATIVO) { PlayerNativo.selFaixa('audio', i); return; }
  const hls = _hlsDoVideo(v);
  if (hls && hls.audioTracks && hls.audioTracks.length) { hls.audioTrack = i; return; }
  const at = v.audioTracks;
  if (at) for (let k = 0; k < at.length; k++) at[k].enabled = (k === i);
}
const _marca = (txt, on) => txt + (on ? '  ✓' : '');

// As faixas de legenda/áudio NÃO existem no instante em que o vídeo começa a
// tocar: no player nativo da TV elas só aparecem depois que o demuxer lê o
// stream (evento `addtrack`, às vezes segundos depois), e no hls.js só depois do
// MANIFEST_PARSED. Ler na hora do clique retornava lista vazia — era por isso que
// o menu sempre dizia "não oferece legendas". Aqui esperamos até `ms` por elas.
// (No app mobile o media_kit/libmpv já entrega as faixas prontas; no web precisamos
// escutar os eventos.)
function _esperarFaixas(v, contar, ms) {
  return new Promise((resolve) => {
    if (contar()) return resolve(true);
    const t0 = Date.now();
    const tt = v.textTracks, at = v.audioTracks;
    let iv = 0;
    const limpar = () => {
      clearInterval(iv);
      if (tt && tt.removeEventListener) tt.removeEventListener('addtrack', checar);
      if (at && at.removeEventListener) at.removeEventListener('addtrack', checar);
    };
    function checar() {
      if (contar()) { limpar(); resolve(true); }
      else if (Date.now() - t0 >= ms) { limpar(); resolve(false); }
    }
    iv = setInterval(checar, 250);
    if (tt && tt.addEventListener) tt.addEventListener('addtrack', checar);
    if (at && at.addEventListener) at.addEventListener('addtrack', checar);
  });
}

// ── LEGENDA EXTERNA (.srt/.vtt) — render próprio ────────────────────────────
// No webOS a legenda EMBUTIDA de MP4/MKV não é acessível por web app (a LG só
// suporta .vtt externa). Então, quando existe legenda externa (via Xtream
// get_vod_info), baixamos, convertemos p/ cues e renderizamos NÓS MESMOS num
// overlay sincronizado ao vídeo — funciona em qualquer plataforma, sem depender
// do render nativo de <track>.
let _playerItem = null;              // item do VOD atual (tem a URL p/ get_vod_info)
let _legCues = [];                   // [{ini, fim, txt}] em segundos
let _legIdx = -1;                    // índice do cue exibido agora (evita repintar)
let _legExternasCache = {};          // url do VOD -> lista de legendas externas
function _legendaReset() { _legCues = []; _legIdx = -1; const el = document.getElementById('player-legenda'); if (el) { el.textContent = ''; el.classList.remove('on'); } }

// Converte "HH:MM:SS,mmm" ou "MM:SS.mmm" em segundos.
function _tempoLeg(s) {
  const m = s.trim().replace(',', '.').match(/(?:(\d+):)?(\d{1,2}):(\d{2}(?:\.\d+)?)/);
  if (!m) return 0;
  return (parseInt(m[1] || '0') * 3600) + (parseInt(m[2]) * 60) + parseFloat(m[3]);
}
// Parser SRT E WebVTT → cues. Aceita os dois (a maioria dos provedores serve SRT).
function parseLegenda(txt) {
  const cues = [];
  txt = txt.replace(/^﻿/, '').replace(/\r/g, '').replace(/^WEBVTT.*$/m, '');
  for (const bloco of txt.split(/\n\n+/)) {
    const linhas = bloco.split('\n').filter((l) => l.trim() !== '');
    if (!linhas.length) continue;
    let i = 0;
    if (/^\d+$/.test(linhas[0].trim())) i = 1;           // número do cue (SRT)
    const tempo = linhas[i] && linhas[i].match(/(.+?)\s*-->\s*(.+)/);
    if (!tempo) continue;
    const ini = _tempoLeg(tempo[1]), fim = _tempoLeg(tempo[2]);
    const texto = linhas.slice(i + 1).join('\n')
      .replace(/<[^>]+>/g, '').replace(/\{[^}]+\}/g, '').trim();   // tira tags
    if (texto) cues.push({ ini, fim, txt: texto });
  }
  cues.sort((a, b) => a.ini - b.ini);
  return cues;
}
// Liga a atualização do overlay ao tempo do vídeo (1x por player).
function _ligarLegendaTick(v) {
  if (v._legTick) return;
  v._legTick = true;
  v.addEventListener('timeupdate', () => {
    const el = document.getElementById('player-legenda');
    if (!el || !_legCues.length) return;
    const t = v.currentTime;
    // cue atual ainda vale? (barato)
    if (_legIdx >= 0 && _legCues[_legIdx] && t >= _legCues[_legIdx].ini && t <= _legCues[_legIdx].fim) return;
    let achou = -1;
    for (let i = 0; i < _legCues.length; i++) { if (t >= _legCues[i].ini && t <= _legCues[i].fim) { achou = i; break; } if (_legCues[i].ini > t) break; }
    if (achou === _legIdx) return;
    _legIdx = achou;
    if (achou < 0) { el.classList.remove('on'); el.textContent = ''; }
    else { el.innerHTML = escapar(_legCues[achou].txt).replace(/\n/g, '<br>'); el.classList.add('on'); }
  });
}
async function aplicarLegendaExterna(v, url) {
  try {
    const r = await fetch(url);
    const txt = await r.text();
    _legCues = parseLegenda(txt); _legIdx = -1;
    _ligarLegendaTick(v);
    return _legCues.length;
  } catch (_) { return 0; }
}
function desativarLegenda() { _legCues = []; _legIdx = -1; const el = document.getElementById('player-legenda'); if (el) { el.classList.remove('on'); el.textContent = ''; } }

// Descobre legendas EXTERNAS do VOD atual via Xtream get_vod_info. A URL do M3U
// costuma ser http://host:port/movie/USER/PASS/VODID.ext → dá p/ montar a chamada.
async function legendasExternas(item) {
  const url = item && item.url; if (!url) return [];
  if (_legExternasCache[url]) return _legExternasCache[url];
  let out = [];
  try {
    const m = url.match(/^(https?:\/\/[^/]+)\/(?:movie|series)\/([^/]+)\/([^/]+)\/(\d+)\./i);
    if (m) {
      const [, base, user, pass, vodId] = m;
      const api = `${base}/player_api.php?username=${encodeURIComponent(user)}&password=${encodeURIComponent(pass)}&action=get_vod_info&vod_id=${vodId}`;
      const j = await (await fetch(api)).json();
      const subs = (j && j.info && (j.info.subtitles || j.info.subtitle)) || [];
      out = (Array.isArray(subs) ? subs : []).map((s, i) => {
        const u = typeof s === 'string' ? s : (s.url || s.file || s.src || '');
        const lang = (typeof s === 'object' && (s.language || s.lang || s.label)) || ('Legenda ' + (i + 1));
        return u ? { rotulo: String(lang), url: u } : null;
      }).filter(Boolean);
    }
  } catch (_) { /* provedor sem get_vod_info / CORS */ }
  _legExternasCache[url] = out;
  return out;
}

// DIAGNÓSTICO: o que a plataforma REALMENTE expõe de faixas, para cada fonte.
// Serve p/ sabermos, na TV real, por que legenda/áudio não aparece (sem DevTools).
//
// ⚠️ DESLIGADO em produção: o usuário final não pode ver "sub via hls: 0". Quando
// não há faixa, ele recebe a frase amigável. Para ligar em teste, no console da
// TV (ares-inspect / DevTools):  localStorage.setItem('hp_diag','1')  e reabrir.
function _diagLigado() {
  try {
    return localStorage.getItem('hp_diag') === '1' ||
      /[?&]diag=1(&|$)/.test(location.search);
  } catch (_) { return false; }
}
let _fonteVodDiag = null;   // { ehHls, ext } do último VOD aberto
function _diagFaixas(v) {
  const hls = _hlsDoVideo(v);
  const n = (x) => (x && x.length != null) ? String(x.length) : (x == null ? 'n/d' : '0');
  const fmt = _fonteVodDiag ? ((_fonteVodDiag.ehHls ? 'HLS' : 'arquivo') + ' .' + _fonteVodDiag.ext) : '?';
  return [
    'formato: ' + fmt,
    'player: ' + (hls ? 'hls.js' : 'nativo TV'),
    'sub via hls: ' + n(hls && hls.subtitleTracks),
    'sub nativo (textTracks): ' + n(v.textTracks),
    'audio via hls: ' + n(hls && hls.audioTracks),
    'audio nativo (audioTracks): ' + (v.audioTracks ? String(v.audioTracks.length) : 'n/d (nao exposto)'),
  ];
}

async function abrirMenuLegendas(v) {
  if (!v) return;
  // 1) Faixas IN-BAND (HLS com VTT/CEA via hls.js — quando existirem).
  let fx = faixasLegenda(v);
  // 2) Legendas EXTERNAS do provedor (Xtream get_vod_info) — a ÚNICA via no webOS
  //    p/ arquivo MP4/MKV. Busca só p/ VOD (tem _playerItem).
  let ext = [];
  if (_playerItem) {
    toast(t('Procurando legendas…'));
    ext = await legendasExternas(_playerItem);
    if (!fx.length && !ext.length) {
      // dá uma última chance às in-band tardias (HLS)
      await _esperarFaixas(v, () => faixasLegenda(v).length, 4000);
      fx = faixasLegenda(v);
    }
  }
  if (!fx.length && !ext.length) {
    if (_diagLigado()) {
      abrirMenu(t('Legendas — nada encontrado (diagnóstico)'), _diagFaixas(v), () => {});
    } else {
      toast(t('Este conteúdo não oferece legendas'));
    }
    return;
  }
  const at = legendaAtual(v);
  const externaOn = _legCues.length > 0;
  // Monta a lista: Desativar + in-band + externas.
  const itens = [{ tipo: 'off', rotulo: _marca(t('Desativadas'), at < 0 && !externaOn) }];
  fx.forEach((f) => itens.push({ tipo: 'hls', i: f.i, rotulo: _marca(f.rotulo, f.i === at) }));
  ext.forEach((e) => itens.push({ tipo: 'ext', url: e.url, rotulo: _marca(e.rotulo + '  ·  externa', false) }));
  abrirMenu(t('Legendas'), itens.map((x) => x.rotulo), async (k) => {
    const sel = itens[k];
    if (sel.tipo === 'off') { desativarLegenda(); if (fx.length) selecionarLegenda(v, -1); toast(t('Legendas desativadas')); return; }
    if (sel.tipo === 'hls') { desativarLegenda(); selecionarLegenda(v, sel.i); toast(t('Legenda') + ': ' + fx.find((f) => f.i === sel.i).rotulo); return; }
    if (sel.tipo === 'ext') {
      if (fx.length) selecionarLegenda(v, -1);           // desliga in-band se houver
      toast(t('Carregando legenda…'));
      const n = await aplicarLegendaExterna(v, sel.url);
      toast(n ? (t('Legenda ativada')) : t('Não foi possível carregar a legenda'));
    }
  });
}
async function abrirMenuAudio(v) {
  if (!v) return;
  let fx = faixasAudio(v);
  if (fx.length < 2) {
    toast(t('Procurando faixas de áudio…'));
    await _esperarFaixas(v, () => faixasAudio(v).length > 1, 8000);
    fx = faixasAudio(v);
  }
  if (fx.length < 2) {
    if (_diagLigado()) {
      abrirMenu(t('Áudio — só uma faixa (diagnóstico)'), _diagFaixas(v), () => {});
    } else {
      toast(t('Este conteúdo tem apenas uma faixa de áudio'));
    }
    return;
  }
  const at = audioAtual(v);
  abrirMenu(t('Áudio'), fx.map((f) => _marca(f.rotulo, f.i === at)), (k) => {
    selecionarAudio(v, fx[k].i);
    toast(t('Áudio') + ': ' + fx[k].rotulo);
  });
}

function carregarPreviewVideo() {
  // COM SOM já no preview: escolher um canal é um gesto do usuário, então não há
  // trava de autoplay a respeitar — e ouvir na hora é o comportamento de quem
  // está zapeando (era mudo, e só ligava em tela cheia).
  // O stream de TESTE (nenhum canal escolhido) segue mudo: ninguém pediu por ele.
  if (_tvCanalPreview) tocarCanalAuto(_tvCanalPreview, false);
  else tocarNoPreview(TEST_HLS, true);
}

function selecionarPreview(canal) {
  _tvCanalPreview = canal;
  // Marca o canal SELECIONADO na lista (p/ o "voltar" da preview retornar a ele).
  document.querySelectorAll('.tv-canal-main.sel').forEach((e) => e.classList.remove('sel'));
  const cel = document.querySelector(`.tv-canal-main[data-canal="${canal.id}"]`);
  if (cel) cel.classList.add('sel');
  const col = document.getElementById('tv-col-dir');
  if (!document.getElementById('tv-prev-video')) col.innerHTML = htmlPreviewShell();

  const prevLogo = document.getElementById('tv-prev-logo');
  prevLogo.style.background = gradiente(canal.nome, true);
  prevLogo.classList.remove('tem-img');
  prevLogo.innerHTML = logoCanalInner(canal.nome, canal.logo);
  document.getElementById('tv-prev-canal').textContent = `${canal.num} · ${canal.nome}`;
  document.getElementById('tv-prev-agora').innerHTML = rotuloAgora(canal);
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
  // Estrela na LISTA (botão de favoritar de cada canal), sem depender da preview.
  const listBtn = document.querySelector(`.tv-canal-fav[data-canal="${id}"]`);
  if (listBtn) { listBtn.innerHTML = IC_STAR(on); listBtn.classList.toggle('ativo', on); }
  toast(on ? t('Adicionado aos favoritos') : t('Removido dos favoritos'));
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
      <h2 class="bsc-titulo">${escapar(t('Buscar'))}</h2>
      <div class="bsc-input">
        <span class="bsc-input-ico">${IC_BUSCA_LUPA}</span>
        <span class="bsc-campo"><span class="bsc-q" id="bsc-q"></span><span class="bsc-caret"></span><span class="bsc-ph" id="bsc-ph">${escapar(t('Buscar…'))}</span></span>
      </div>
      <div class="bsc-teclado">
        ${teclas}
        <button class="bsc-key bsc-key-acao focusable" data-acao="apagar">${IC_BUSCA_DEL}</button>
        <button class="bsc-key bsc-key-acao focusable" data-acao="espaco">${escapar(t('Espaço'))}</button>
        <button class="bsc-key bsc-key-acao focusable" data-acao="limpar">${escapar(t('Limpar'))}</button>
      </div>
      <div class="bsc-sug" id="bsc-sug"></div>
    </div>
    <div class="bsc-dir" id="bsc-dir">${htmlBuscaVazia()}</div>
  </div>`;
}

function htmlBuscaVazia() {
  return `<div class="bsc-vazio">
    <div class="bsc-vazio-ico">${IC_BUSCA_LUPA}</div>
    <div class="bsc-vazio-titulo">${escapar(t('Encontre seus filmes e séries'))}</div>
    <div class="bsc-vazio-sub">${escapar(t('Digite o nome no teclado ao lado para começar'))}</div>
  </div>`;
}
function htmlBuscaSemResultado(q) {
  return `<div class="bsc-vazio">
    <div class="bsc-vazio-ico">${IC_BUSCA_LUPA}</div>
    <div class="bsc-vazio-titulo">${escapar(t('Nada encontrado para “{q}”').replace('{q}', q))}</div>
    <div class="bsc-vazio-sub">${escapar(t('Confira a digitação ou tente outro título'))}</div>
  </div>`;
}

// Filtra filmes + séries da lista pelo título (sem acento) e desenha em grade.
function atualizarBusca() {
  const q = _buscaQuery;
  const span = document.getElementById('bsc-q'); if (span) span.textContent = q;
  const ph = document.getElementById('bsc-ph'); if (ph) ph.style.display = q ? 'none' : '';
  const dir = document.getElementById('bsc-dir'); if (!dir) return;
  const sug = document.getElementById('bsc-sug');
  const nq = normBusca(q);
  if (!nq) { dir.innerHTML = htmlBuscaVazia(); if (sug) renderSugestoes(sug, sugestoesPopulares(), true); return; }
  const nqSemEsp = nq.replace(/\s+/g, '');
  const matched = [...(LISTA.filmes || []), ...(LISTA.series || [])].filter((it) => casaBusca(it, nq, nqSemEsp));
  aplicarResultados(dir, matched.slice(0, 60), q);
  // Indexa apelidos (TMDB) só dos RESULTADOS na tela — não dos 165k (isso travava
  // a busca no início). Progressivo: casa por referência conforme o usuário navega.
  indexar(matched.slice(0, 60), atualizarBusca, () => !!document.getElementById('bsc-dir'));
  if (sug) {
    // Prioriza quem COMEÇA com o texto (autocomplete de verdade); depois contém no
    // título; por último os que casaram só por referência/tradução (rank 3).
    const rank = (it) => {
      const t = normBusca(it.titulo || '');
      if (t.startsWith(nq)) return 0;
      if (t.replace(/\s+/g, '').startsWith(nqSemEsp)) return 1;
      if (t.includes(nq)) return 2;
      return 3;
    };
    renderSugestoes(sug, [...matched].sort((a, b) => rank(a) - rank(b)).slice(0, 8), false);
  }
}

// Autocomplete estilo Netflix (abaixo do teclado): títulos prováveis. OK abre o detalhe.
function renderSugestoes(container, itens, populares) {
  // Enquanto o foco está numa sugestão, NÃO re-renderiza (senão o elemento focado
  // é removido, o foco "some" e o próximo toque cai na sidebar).
  if (SpatialNav.atual && container.contains(SpatialNav.atual)) return;
  if (!itens.length) { container.innerHTML = ''; return; }
  const cab = `<div class="bsc-sug-cab">${escapar(populares ? t('Sugestões') : t('Resultados prováveis'))}</div>`;
  container.innerHTML = cab + itens.map((it) =>
    `<button class="bsc-sug-item focusable" data-id="${escapar(it.id)}"><span class="bsc-sug-nome">${escapar(it.titulo)}</span><span class="bsc-sug-tipo">${it.tipo === 'serie' ? t('Série') : t('Filme')}</span></button>`).join('');
  container.querySelectorAll('.bsc-sug-item').forEach((b) => b.addEventListener('click', () => { const it = LISTA.indice[b.dataset.id]; if (it) abrirDetalhe(it); }));
}
// Quando o campo está vazio: alguns títulos do catálogo (intercala filmes/séries).
function sugestoesPopulares() {
  const f = LISTA.filmes || [], s = LISTA.series || [], out = [];
  for (let i = 0; out.length < 8 && (i < f.length || i < s.length); i++) { if (f[i]) out.push(f[i]); if (s[i]) out.push(s[i]); }
  return out;
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
    let novo = false;
    if (!el) { const tmp = document.createElement('div'); tmp.innerHTML = posterHTML(it, true); el = tmp.firstElementChild; novo = true; }
    const ref = anterior ? anterior.nextElementSibling : grid.firstElementChild;
    if (el !== ref) grid.insertBefore(el, ref);   // só move se preciso (não recria → não pisca)
    if (novo) vigiarLogo(el);                     // capa da lista pendurou → TMDB depois de 5s
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
  _executarFila(tarefas, 3, vivo, _focoOcupado);
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
  atualizarBusca(); // sugestões iniciais (populares) já ao abrir — a indexação de
  // apelidos agora é POR RESULTADO (dentro de atualizarBusca), não dos 165k itens.
}

// Busca DENTRO de uma seção (Filmes ou Séries): mesma tela da busca, mas só com os
// itens daquela seção + as CATEGORIAS dela abaixo do teclado (navegáveis). Abre com
// animação de "lupa tomando a tela" (círculo expandindo do botão) e fecha ao contrário.
function abrirBuscaSecao(escopo, btn) {
  const itensEscopo = (escopo === 'series') ? (LISTA.series || []) : (LISTA.filmes || []);
  const cats = (((LISTA.catalogo || {})[escopo] || {}).trilhos || []).map((t) => t.titulo);
  const titulo = escopo === 'series' ? t('Buscar em Séries') : t('Buscar em Filmes');
  let query = '', catSel = null;

  const teclas = [...BUSCA_TECLAS].map((c) => `<button class="bsc-key focusable" data-k="${c}">${c}</button>`).join('')
    + `<button class="bsc-key bsc-key-acao focusable" data-acao="apagar">${IC_BUSCA_DEL}</button>`
    + `<button class="bsc-key bsc-key-acao focusable" data-acao="espaco">${escapar(t('Espaço'))}</button>`
    + `<button class="bsc-key bsc-key-acao focusable" data-acao="limpar">${escapar(t('Limpar'))}</button>`;
  const catsHTML = [`<button class="bsc-cat focusable ativa" data-cat="">${escapar(t('Todos'))}</button>`,
    ...cats.map((c) => `<button class="bsc-cat focusable" data-cat="${escapar(c)}">${escapar(c)}</button>`)].join('');

  const ov = document.createElement('div');
  ov.className = 'nav-modal busca-secao';
  ov.innerHTML = `
    <div class="bs-reveal"></div>
    ${htmlVoltar()}
    <div class="bs-conteudo">
      <div class="bsc">
        <div class="bsc-esq">
          <h2 class="bsc-titulo">${escapar(titulo)}</h2>
          <div class="bsc-input">
            <span class="bsc-input-ico">${IC_BUSCA_LUPA}</span>
            <span class="bsc-campo"><span class="bsc-q" id="bs-q"></span><span class="bsc-caret"></span><span class="bsc-ph" id="bs-ph">${escapar(t('Buscar…'))}</span></span>
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
    const vis = itens.slice(0, 60);
    aplicarResultados(dir, vis, query);
    indexar(vis, render, () => document.body.contains(ov)); // apelidos só do que está na tela
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
  render();  // a indexação de apelidos é por resultado (dentro de render), não da seção toda
  SpatialNav.setFocus(ov.querySelector('.bsc-key'));
}

// ── Roteamento entre secoes ─────────────────────────────────────────────────
// Cache do DOM já renderizado de Início/Filmes/Séries: alternar entre seções
// REUSA o node (com os banners já carregados) em vez de reconstruir tudo — evita
// travar e os pôsteres sumirem ao trocar rápido. Invalidado ao trocar de perfil
// (só Filmes/Séries, pela Minha Lista) e ao recarregar a lista.
// TV: cache DESLIGADO (guardar 3 catálogos em DOM+imagens estoura a RAM). No
// desktop, cacheia p/ troca instantânea. `_secCache` centraliza o acesso.
let _secoesCache = {};
// LRU de seções já montadas. Na TV isto estava DESLIGADO (economia de RAM), o que
// fazia Filmes↔Séries remontarem do zero a cada troca — caro e visível. Com o heap
// medido em 19% do orçamento, dá pra cachear; só limitamos a quantidade.
const _secOrdem = [];                         // fim = usada mais recentemente
const MAX_SEC_CACHE = EH_TV ? 3 : 12;         // TV: início + filmes + séries
function limparCacheSecoes() { _secoesCache = {}; _secOrdem.length = 0; }
function _secToque(id) {
  const i = _secOrdem.indexOf(id);
  if (i >= 0) _secOrdem.splice(i, 1);
  _secOrdem.push(id);
}
function _secCacheDel(id) {
  delete _secoesCache[id];
  const i = _secOrdem.indexOf(id);
  if (i >= 0) _secOrdem.splice(i, 1);
}
const _secCacheGet = (id) => { const n = _secoesCache[id]; if (n) _secToque(id); return n || null; };
const _secCacheSet = (id, node) => {
  _secoesCache[id] = node;
  _secToque(id);
  while (_secOrdem.length > MAX_SEC_CACHE) _secCacheDel(_secOrdem[0]);
};

function navegar(secaoId) {
  pararPreview(); // para o preview da TV ao vivo ao sair da secao
  document.querySelectorAll('.busca-secao, .addpl').forEach((o) => o.remove()); // fecha busca de seção / add playlist ao trocar de seção
  clearTimeout(_heroDebounce); _heroDebounce = null; _heroPendente = null; // cancela troca de hero pendente
  document.querySelectorAll('.nav-item').forEach((n) =>
    n.classList.toggle('ativo', n.dataset.secao === secaoId));

  const main = document.getElementById('conteudo');
  if (secaoId === 'inicio' || secaoId === 'filmes' || secaoId === 'series') {
    let node = _secCacheGet(secaoId);
    if (node) {
      while (main.firstChild) main.removeChild(main.firstChild);  // detach (node cacheado sobrevive)
      main.appendChild(node);                      // reusa o DOM (banners já carregados)
      _tokenTrilhos++;                             // cacheado (desktop): cancela append pendente
    } else {
      main.innerHTML = renderMidia(LISTA.catalogo[secaoId], secaoId);
      if (secaoId === 'inicio') injetarTrilhosPerfil(main);  // Continuar assistindo + Recomendações
      else injetarMinhaLista(main, secaoId);               // Minha Lista no topo de Filmes/Séries
      node = main.firstElementChild;
      _secCacheSet(secaoId, node);
      anexarTrilhosRestantes(node, LISTA.catalogo[secaoId]);  // TV: resto dos trilhos em chunks (não trava)
    }
    // Reset do hero: o node (fresco OU cacheado) pode ter estado antigo de
    // backdrop; zera as camadas e o ponteiro A/B p/ o 1º foco aplicar limpo.
    _heroItem = null; _heroUltimoAplicado = 0; _heroBgAtivo = 'A';
    const _bA = node.querySelector('#hero2-bgA'), _bB = node.querySelector('#hero2-bgB');
    if (_bA) _bA.classList.remove('on'); if (_bB) _bB.classList.remove('on');
    ligarPostersSerie(node);                       // re-observa (pôsteres já carregados são pulados)
  } else if (secaoId === 'tvaovivo') {
    main.innerHTML = renderTvAoVivo();
    carregarEpgSeNecessario();
  } else if (secaoId === 'playlists') {
    main.innerHTML = renderPlaylists();
    preencherPlaylists();
  } else if (secaoId === 'buscar') {
    main.innerHTML = renderBuscar();
    ligarBuscar(main);
  } else if (secaoId === 'jogos') {
    main.innerHTML = renderJogos();
    ligarJogos();
  } else if (secaoId === 'config') {
    main.innerHTML = renderConfig();
  }
  main.scrollTop = 0;

  // Foca o 1o elemento do conteudo; se nao houver (placeholder), mantem no menu.
  // Jogos: começa na aba HOJE (a ativa), não na 1ª aba (Ontem).
  const primeiro = main.querySelector('.jogos-data.ativa') || main.querySelector('.focusable');
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
// Episódio salvo no "continuar assistindo" (casa pela URL) e rótulo do botão.
function _epDoProgresso(item, pr) { return (pr && pr.url) ? epsOrdenados(item).find((ep) => ep.url === pr.url) || null : null; }
function rotuloContinuar(item, pr) {
  if (item.tipo !== 'serie') return t('Continuar');
  const ep = _epDoProgresso(item, pr);
  if (ep) { const { s, e } = epInfo(ep.nome); return `${t('Continuar')} EP ${e} T ${s}`; }
  return t('Continuar');
}
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
    el.innerHTML = `<div class="rec-arte"><span>${escapar(it.titulo)}</span></div>`;
    el.addEventListener('click', () => { fecharDetalhe(); abrirDetalhe(it); });
    cont.appendChild(el);
    const setImg = (u) => { if (!u) return; const im = new Image(); im.className = 'rec-img'; im.onload = () => { const a = el.querySelector('.rec-arte'); if (a) { a.classList.add('tem-img'); a.appendChild(im); } }; im.src = u; };
    if (it.tipo !== 'serie' && it.logo) setImg(it.logo); else TMDB.poster(it.titulo, it.tipo === 'serie').then(setImg);
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

function abrirDetalhe(item, _okPin) {
  // Controle dos pais: se o item cai numa categoria bloqueada, pede o PIN.
  if (!_okPin && typeof conteudoBloqueado === 'function' && conteudoBloqueado(item)) {
    pedirPin(() => abrirDetalhe(item, true)); return;
  }
  const ehSerie = item.tipo === 'serie';
  // Continuar assistindo: se há progresso salvo, o botão vira "Continuar" (filme)
  // ou "Continuar EP e T s" (série) e, ao clicar, pergunta continuar × do início.
  const prog = Biblioteca.progressoDe(item.id);
  const temProg = !!(prog && prog.pos > 15 && (!prog.dur || prog.pos < prog.dur - 20));
  const rotPrinc = temProg ? rotuloContinuar(item, prog)
    : (ehSerie ? `${t('Assistir')} ${primeiroEpLabel(item)}` : t('Assistir'));
  let inf = null, cred = { elenco: [], direcao: [] };
  const ov = document.createElement('div');
  ov.id = 'detalhe-overlay';
  ov.className = 'nav-modal det2';
  const btnPrinc = `<button class="btn btn-primario focusable" data-acao="assistir"><svg viewBox="0 0 24 24"><path d="M8 5v14l11-7z"/></svg> ${escapar(rotPrinc)}</button>`;
  const acoes = ehSerie
    ? `${btnPrinc}
       <button class="btn btn-secundario focusable" data-acao="episodios"><svg viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="2" stroke-linecap="round"><path d="M3 6h13M3 12h13M3 18h9"/><path d="m18 11 4 3-4 3z" fill="currentColor" stroke="none"/></svg> ${escapar(t('Episódios e mais'))}</button>`
    : btnPrinc;
  ov.innerHTML = `
    <div class="det2-bg" id="det2-bg" style="background:${FUNDO_PADRAO}"></div>
    <div class="det2-grad"></div>
    ${htmlVoltar()}
    <div class="det2-scroll" id="det2-scroll">
      <section class="det2-topo">
        <img class="det2-logo" id="det2-logo" alt="" style="display:none">
        <h1 class="det2-titulo" id="det2-titulo">${escapar(item.titulo)}</h1>
        <div class="det2-meta" id="det2-meta"></div>
        <span class="det2-tag">${ehSerie ? t('Série') : t('Filme')}</span>
        <p class="det2-sinopse" id="det2-sinopse">${escapar(item.sinopse || '')}</p>
        <div class="det2-acoes">
          ${acoes}
          <button class="btn btn-icone focusable" data-acao="lista" title="${escapar(t('Minha Lista'))}"><svg viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="2.4" stroke-linecap="round"><path d="M12 5v14M5 12h14"/></svg></button>
          <button class="btn btn-icone focusable" data-acao="creditos" title="Créditos e mais informações"><svg viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="2"><circle cx="12" cy="12" r="9"/><path d="M12 11v5" stroke-linecap="round"/><circle cx="12" cy="8" r="0.6" fill="currentColor" stroke="none"/></svg></button>
        </div>
      </section>
      <section class="det2-secao oculto" id="det2-elenco">
        <h2 class="det2-h2">${escapar(t('Elenco'))}</h2>
        <div class="det2-fila" id="det2-elenco-fila"></div>
      </section>
      <section class="det2-secao oculto" id="det2-rec">
        <h2 class="det2-h2">${escapar(t('Títulos semelhantes'))}</h2>
        <div class="det2-fila" id="det2-rec-fila"></div>
      </section>
    </div>`;
  document.body.appendChild(ov);
  ov._onVoltar = fecharDetalhe;
  ov._voltarFoco = SpatialNav.atual;   // p/ voltar ao item que abriu (ex.: resultado da busca de seção)
  const q = (a) => ov.querySelector(`[data-acao="${a}"]`);
  // Reproduz: continuar (retoma) ou reiniciar (do início). Série sem progresso → 1º ep.
  const reproduzir = (reiniciar) => {
    fecharDetalhe();
    if (ehSerie) {
      let url = temProg && prog ? prog.url : null, rot = (temProg && prog && prog.ep) || '';
      if (!url) { const ep = primeiroEp(item); if (ep) { url = ep.url; rot = rotuloEp(item, ep); } }
      if (url) abrirPlayer({ titulo: rot || item.titulo, url }, ctxProgresso(item, url, rot), reiniciar);
    } else {
      abrirPlayer(item, ctxProgresso(item, item.url), reiniciar);
    }
  };
  q('assistir').addEventListener('click', () => {
    if (temProg) modalContinuarAssistir(item, prog, () => reproduzir(false), () => reproduzir(true));
    else reproduzir(false);
  });
  if (q('episodios')) q('episodios').addEventListener('click', () => abrirEpisodios(item, inf));
  // Minha Lista: adiciona/remove (por perfil) e atualiza o carrossel da seção.
  const btnLista = q('lista');
  const syncLista = () => {
    const na = Biblioteca.naLista(item.id);
    btnLista.classList.toggle('ativo', na);
    btnLista.title = na ? t('Remover da Minha Lista') : t('Minha Lista');
    btnLista.innerHTML = na ? IC_OK : IC_MAIS;
  };
  syncLista();
  btnLista.addEventListener('click', () => {
    const add = Biblioteca.alternarLista(item);
    syncLista();
    atualizarMinhaLista(item.tipo);
    toast(add ? t('Adicionado à Minha Lista') : t('Removido da Minha Lista'));
  });
  q('creditos').addEventListener('click', () => abrirCreditos(item, inf, cred));
  SpatialNav.setFocus(q('assistir'));

  document.getElementById('det2-meta').innerHTML = metaDetalhe(item, null);
  const recs = recomendadosLocais(item);
  if (recs.length) { document.getElementById('det2-rec').classList.remove('oculto'); montarRec(document.getElementById('det2-rec-fila'), recs); }

  TMDB.info(item.titulo, ehSerie).then(async (i) => {
    if (!document.getElementById('detalhe-overlay')) return;
    inf = i;
    if (!i || i.vazio) { const s = document.getElementById('det2-sinopse'); if (s && !s.textContent) s.textContent = t('Sem descrição disponível.'); return; }
    const bg = document.getElementById('det2-bg');
    if (i.backdrop && bg) bg.style.background = `#000 right top / cover no-repeat url("${i.backdrop}")`;
    const sin = document.getElementById('det2-sinopse'); if (sin) sin.textContent = i.sinopse || item.sinopse || t('Sem descrição disponível.');
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
  focarTopo();
}

// Modal "Continuar assistindo?": retomar de onde parou × ver desde o início.
function modalContinuarAssistir(item, pr, aoContinuar, aoInicio) {
  const ov = document.createElement('div');
  ov.className = 'nav-modal cont-modal';
  const ep = item.tipo === 'serie' ? _epDoProgresso(item, pr) : null;
  let sub;
  if (ep) { const { s, e } = epInfo(ep.nome); sub = `T${s} · EP ${e} — ${fmtTempo(pr.pos)}`; }
  else sub = t('Parou em') + ' ' + fmtTempo(pr.pos);
  ov.innerHTML = `<div class="cont-card">
    <div class="cont-tit">${escapar(t('Continuar assistindo?'))}</div>
    <div class="cont-sub">${escapar(item.titulo)}</div>
    <div class="cont-pos">${escapar(sub)}</div>
    <div class="cont-acoes">
      <button class="btn btn-primario focusable" data-c="1"><svg viewBox="0 0 24 24"><path d="M8 5v14l11-7z"/></svg> ${escapar(t('Continuar'))}</button>
      <!-- fill="none" em CADA path, não no svg: a regra ".btn svg { fill:
           currentColor }" vence o atributo posto no svg (mas perde para o
           atributo do próprio path). Era isso que enchia o arco de sólido. -->
      <button class="btn btn-secundario focusable" data-i="1"><svg viewBox="0 0 24 24" stroke="currentColor" stroke-width="2.2" stroke-linecap="round" stroke-linejoin="round"><path d="M3 12a9 9 0 1 0 9-9 9.75 9.75 0 0 0-6.74 2.74L3 8" fill="none"/><path d="M3 3v5h5" fill="none"/></svg> ${escapar(t('Do início'))}</button>
    </div>
  </div>`;
  document.body.appendChild(ov);
  const ant = SpatialNav.atual;
  const fechar = () => { ov.remove(); if (ant && document.contains(ant)) SpatialNav.setFocus(ant); };
  ov._onVoltar = fechar;
  ov.querySelector('[data-c]').addEventListener('click', () => { ov.remove(); aoContinuar(); });
  ov.querySelector('[data-i]').addEventListener('click', () => { ov.remove(); aoInicio(); });
  SpatialNav.setFocus(ov.querySelector('[data-c]'));
}

// Créditos e mais informações — menu à esquerda + painel à direita (estilo GTV).
function abrirCreditos(item, inf, cred) {
  const sec = [];
  if (cred && cred.direcao && cred.direcao.length) sec.push([t('Direção'), cred.direcao.join(', ')]);
  if (cred && cred.elenco && cred.elenco.length) sec.push([t('Elenco'), cred.elenco.map((a) => a.personagem ? `${a.nome} — ${a.personagem}` : a.nome).join('\n')]);
  const gen = (item.generos || []).join(', '); if (gen) sec.push([t('Gêneros'), gen]);
  const sin = (inf && inf.sinopse) || item.sinopse || ''; if (sin) sec.push([t('Sinopse'), sin]);
  if (!sec.length) sec.push([t('Informações'), t('Sem informações adicionais.')]);

  const ov = document.createElement('div');
  ov.className = 'nav-modal cr';
  ov.innerHTML = `
    ${htmlVoltar()}
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
    ${htmlVoltar()}
    <div class="ep-conteudo">
      <div class="ep-cabecalho">
        <img class="ep-logo" id="ep-logo" alt="" style="display:none">
        <h1 class="ep-titulo" id="ep-titulo">${escapar(item.titulo)}</h1>
      </div>
      <div class="ep-temps" id="ep-temps">
        ${(() => { const _tTemp = t('Temporada'); return temps.map((s) => `<div class="ep-temp-item focusable${s === tAtual ? ' ativa' : ''}" data-s="${s}"><span class="ep-temp-dot"></span><span class="ep-temp-lbl">${escapar(_tTemp)} ${s}</span></div>`).join(''); })()}
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
      el.addEventListener('click', () => { _epCtrl = null; ov.remove(); const d = document.getElementById('detalhe-overlay'); if (d) d.remove(); const rot = rotuloEp(item, ep); abrirPlayer({ titulo: rot, url: ep.url }, ctxProgresso(item, ep.url, rot)); });
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

let _playerCtx = null, _lastProgSave = 0;   // contexto p/ "continuar assistindo"
// Vídeo ATIVO do VOD: o <video> nas TVs, ou a fachada do ExoPlayer no Android.
// Quem precisa de currentTime/duration (barra de progresso, busca, salvar o
// ponto) usa isto — nunca o getElementById direto.
let _videoVod = null;
function abrirPlayer(item, ctx, reiniciar) {
  // Encerra o AO VIVO antes de abrir o VOD. No Android é um só ExoPlayer (o
  // `abrir` já derruba o anterior), mas na LG/Samsung são DOIS <video>: o do
  // preview continuaria com `src` e o provedor contaria DUAS sessões — é assim
  // que se chega no 403 sem o usuário ter aberto nada em outro aparelho.
  try { pararPreview(); } catch (_) {}
  _playerCtx = ctx || null; _lastProgSave = 0;
  _playerItem = item;                 // p/ buscar legenda externa (Xtream get_vod_info)
  _legendaReset();
  const ov = document.createElement('div');
  ov.id = 'player-overlay';
  ov.className = 'nav-modal player-modal';
  ov.innerHTML = `
    <video id="player-video" playsinline></video>
    <div class="player-legenda" id="player-legenda"></div>
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

  // No Android o vídeo roda no ExoPlayer (atrás do WebView) e a interface fala
  // com uma FACHADA que imita o <video> — daí todo o resto desta função
  // continuar igual nas TVs e no TV Box.
  const elVideo = document.getElementById('player-video');
  const video = TEM_PLAYER_NATIVO ? PlayerNativo.fachada(elVideo) : elVideo;
  _videoVod = video;
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
  let _inicioVod = 0;   // posição de retomada (usada também na retentativa)
  let _tUltimo = -1;    // último tempo visto (reconciliação + retentativa)
  // ── Erro de reprodução ────────────────────────────────────────────────────
  // O 403 do provedor (BAD_HTTP_STATUS) merece tratamento próprio: quase sempre
  // é a sessão ANTERIOR ainda sendo contada do lado dele. O socket já fechou
  // aqui (ver `parar()` no PlayerNativo e o `Connection: close`), mas o painel
  // do provedor leva alguns segundos pra liberar a "tela" — e nesse intervalo
  // qualquer abertura é recusada. Uma única retentativa depois de 2s resolve o
  // caso comum sem o usuário precisar fazer nada.
  let _reTentou = false;
  video.addEventListener('error', () => {
    const cod = TEM_PLAYER_NATIVO ? PlayerNativo.erro() : '';
    if (/BAD_HTTP_STATUS/.test(cod) && !_reTentou && TEM_PLAYER_NATIVO) {
      _reTentou = true;
      spinner(true);
      setTimeout(() => {
        if (!document.getElementById('player-overlay')) return;   // usuário já saiu
        PlayerNativo.abrir(elVideo, fonte, _tUltimo > 0 ? _tUltimo : _inicioVod, false);
      }, 2000);
      return;
    }
    erroPlayer(mensagemErroPlayer(cod));
  });

  const fonte = item.url || TEST_HLS;     // URL real do item (fallback: teste)
  const ehHls = /\.m3u8(\?|$)/i.test(fonte);
  // Guarda formato/fonte p/ o diagnóstico de faixas (o usuário não vê a URL na UI).
  _fonteVodDiag = { ehHls, ext: ((fonte.split('?')[0].split('.').pop() || '').toLowerCase().slice(0, 5)) || '?' };
  spinner(true);
  // VOD HLS → PREFERE hls.js quando ele é suportado. O player nativo do webOS
  // frequentemente NÃO expõe as faixas de áudio/legenda embutidas via
  // video.audioTracks/textTracks; o hls.js as entrega de forma confiável
  // (hls.audioTracks/subtitleTracks). Para arquivo direto (mp4/mkv/ts) não há
  // escolha: vai no nativo (hls.js não demuxa .ts/HEVC) e aí as faixas dependem
  // do que a TV expõe. (No live mantemos nativo-first por causa de .ts/HEVC.)
  if (TEM_PLAYER_NATIVO) {
    // Retoma de onde parou já na abertura: o ExoPlayer aceita a posição no
    // prepare, então não precisamos esperar o 'loadedmetadata' para buscar.
    if (!reiniciar && _playerCtx) {
      const pr = Biblioteca.progressoDe(_playerCtx.id);
      if (pr && pr.url === fonte && pr.pos > 15 && (!pr.dur || pr.pos < pr.dur - 20)) _inicioVod = pr.pos;
    }
    PlayerNativo.abrir(elVideo, fonte, _inicioVod, false);
  } else if (ehHls && window.Hls && Hls.isSupported()) {
    _hls = new Hls();
    _hls.on(Hls.Events.ERROR, (_e, d) => { if (d && d.fatal) erroPlayer(t('Não foi possível reproduzir este conteúdo.')); });
    _hls.loadSource(fonte);
    _hls.attachMedia(video);
    video.play().catch(() => {});
  } else {
    video.src = fonte;                    // arquivo (mp4/ts) ou HLS nativo (sem hls.js)
    video.play().catch(() => {});
  }
  // Retomar de onde parou (mesmo item/URL) — "continuar assistindo" por perfil.
  // Se `reiniciar` (escolheu "Do início"), começa do zero.
  video.addEventListener('loadedmetadata', () => {
    if (TEM_PLAYER_NATIVO) return;        // no ExoPlayer a posição já foi no abrir
    if (reiniciar || !_playerCtx) return;
    const pr = Biblioteca.progressoDe(_playerCtx.id);
    if (pr && pr.url === fonte && pr.pos > 15 && (!pr.dur || pr.pos < pr.dur - 20)) { try { video.currentTime = pr.pos; } catch (_) {} }
  }, { once: true });

  const q = (a) => ov.querySelector(`[data-acao="${a}"]`);
  q('fechar').addEventListener('click', fecharPlayer);
  q('playpause').addEventListener('click', () => (video.paused ? video.play() : video.pause()));
  q('retroceder').addEventListener('click', () => { video.currentTime = Math.max(0, video.currentTime - 10); revelarControles(); });
  q('avancar').addEventListener('click', () => { video.currentTime = Math.min(video.duration || 1e9, video.currentTime + 10); revelarControles(); });
  q('legendas').addEventListener('click', () => { abrirMenuLegendas(video); revelarControles(); });
  q('audio').addEventListener('click', () => { abrirMenuAudio(video); revelarControles(); });

  const sincIcone = () => { q('playpause').innerHTML = video.paused ? IC_PLAY : IC_PAUSE; };
  video.addEventListener('play', sincIcone);
  video.addEventListener('pause', sincIcone);
  video.addEventListener('playing', sincIcone);

  // ── Reconciliação por ESTADO (não só por evento) ──────────────────────────
  // O spinner e o ícone eram controlados só por eventos ('playing', 'canplay'…).
  // Se um evento se perde — e com o ExoPlayer atrás de uma ponte JS isso
  // acontece — o spinner ficava girando sobre um filme que já estava rodando, e
  // só saía quando um pause/play forçava o evento. Aqui, a cada tick, o que
  // manda é a REALIDADE: se está tocando e o tempo anda, não há o que carregar.
  const reconciliar = () => {
    const andando = video.currentTime > 0 && video.currentTime !== _tUltimo;
    _tUltimo = video.currentTime;
    if (!video.paused && andando) spinner(false);
    sincIcone();
  };
  video.addEventListener('timeupdate', () => {
    reconciliar();
    // Salva o progresso a cada ~5s (continuar assistindo por perfil).
    if (_playerCtx && video.duration && Date.now() - _lastProgSave > 5000) {
      _lastProgSave = Date.now();
      Biblioteca.salvarProgresso(_playerCtx, video.currentTime, video.duration);
    }
    if (_scrub) return; // durante a busca, a barra mostra o ALVO (preview)
    const prog = document.getElementById('pc-prog');
    if (!prog) return;
    if (video.duration) prog.style.width = (video.currentTime / video.duration * 100) + '%';
    document.getElementById('pc-atual').textContent = fmtTempo(video.currentTime);
    document.getElementById('pc-total').textContent = fmtTempo(video.duration);
  });

  revelarControles();
  SpatialNav.setFocus(q('playpause'));
}

// Busca na barra: cada toque avanca/recua; segurar acelera ate 3 niveis.
function scrub(dir) {
  const v = _videoVod || document.getElementById('player-video');
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
  const v = _videoVod || document.getElementById('player-video');
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
  } else if (e.key === 'ArrowLeft' && at.classList.contains('tv-canal-main')) {
    e.preventDefault(); e.stopPropagation();
    mostrarCategorias();                       // ← do retângulo principal volta p/ categorias
  } else if (e.key === 'ArrowLeft' && at.closest('.tv-col-dir')) {
    // Da coluna do player (preview/EPG/estrela) → vai para a LISTA DE CANAIS
    // que esta aparecendo (nao para o sliver de categorias).
    const pane = document.getElementById('tv-pane-canais');
    const alvoCanal = pane && (
      pane.querySelector(`.tv-canal-main[data-canal="${_tvCanalPreview ? _tvCanalPreview.id : ''}"]`) ||
      pane.querySelector('.tv-canal-main')
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
/**
 * LINHAS navegáveis da seção, em ordem de tela: título focável, fila, título…
 *
 * ⚠️ O título ENTRA na sequência. Antes esta função só olhava `.trilho-fila`, e
 * o ↑/↓ pulava de fila em fila — o título do trilho ficava INALCANÇÁVEL, então
 * o "Ver tudo" só funcionava no PRIMEIRO trilho (Lançamentos): ali o ↑ não tinha
 * fila acima, o handler devolvia o evento pro engine e a geometria achava o
 * título. Nos demais, o ↑ saltava direto pra fila de cima.
 *
 * "Continuar assistindo" tem título sem `.focusable` (não é categoria) → fica de
 * fora da sequência, como deve.
 */
function _linhasDaSecao() {
  const linhas = [];
  document.querySelectorAll('#conteudo .trilho').forEach((s) => {
    const tit = s.querySelector('.trilho-titulo.focusable');
    if (tit) linhas.push(tit);
    const fila = s.querySelector('.trilho-fila');
    if (fila && fila.querySelector('.poster')) linhas.push(fila);
  });
  return linhas;
}
window.addEventListener('keydown', (e) => {
  if (e.key !== 'ArrowDown' && e.key !== 'ArrowUp') return;
  const at = SpatialNav.atual;
  if (!at || !at.closest) return;
  const linhaAtual = at.classList.contains('poster') ? at.closest('.trilho-fila')
    : at.classList.contains('trilho-titulo') ? at
    : null;
  if (!linhaAtual || !linhaAtual.closest('#conteudo')) return;
  const linhas = _linhasDaSecao();
  const i = linhas.indexOf(linhaAtual);
  if (i < 0) return;
  const alvo = linhas[e.key === 'ArrowDown' ? i + 1 : i - 1];
  if (!alvo) return;                           // ponta → deixa o engine (hero/nav)
  // Fila → posição lembrada; título → ele mesmo.
  const dest = alvo.classList.contains('trilho-fila')
    ? (_posterLembrado(alvo) || alvo.querySelector('.poster'))
    : alvo;
  if (!dest) return;
  e.preventDefault(); e.stopPropagation();
  SpatialNav.setFocus(dest);
}, true);

/**
 * TELA ACESA enquanto toca (Samsung/LG e navegador).
 *
 * Assistindo um filme ninguém toca no controle, então a TV conta aquilo como
 * INATIVIDADE e apaga a tela no meio da sessão. No Android quem resolve é a
 * casca (`keepScreenOn`, ver MainActivity.kt) — aqui cobrimos as plataformas
 * onde o vídeo é o `<video>` da página.
 *
 * Tudo em try/catch e checado antes: cada plataforma tem uma API (ou nenhuma),
 * e faltar uma delas não pode derrubar a reprodução.
 */
const TelaAcesa = (() => {
  let ligada = false, lock = null;
  const tizenAc = () => {
    try { return (typeof webapis !== 'undefined' && webapis.appcommon) ? webapis.appcommon : null; }
    catch (_) { return null; }
  };
  async function set(on) {
    if (on === ligada) return;
    ligada = on;
    // Samsung: desliga o protetor de tela do sistema enquanto o vídeo roda.
    try {
      const ac = tizenAc();
      if (ac && ac.setScreenSaver) {
        ac.setScreenSaver(on ? ac.AppCommonScreenSaverState.SCREEN_SAVER_OFF
          : ac.AppCommonScreenSaverState.SCREEN_SAVER_ON);
      }
    } catch (_) { /* sem o privilégio no config.xml, ignora */ }
    // Padrão da web, onde existir (Chromium moderno / webOS novo).
    try {
      if (on) {
        if (navigator.wakeLock && !lock) lock = await navigator.wakeLock.request('screen');
      } else if (lock) { lock.release(); lock = null; }
    } catch (_) { lock = null; }
  }
  // Voltar do background solta o wakeLock sozinho — repõe se ainda está tocando.
  document.addEventListener('visibilitychange', () => {
    if (document.visibilityState === 'visible' && ligada) { ligada = false; set(true); }
  });
  return { set };
})();
// `playing`/`pause`/`ended` não borbulham → captura no document.
document.addEventListener('playing', () => TelaAcesa.set(true), true);
document.addEventListener('pause', () => TelaAcesa.set(false), true);
document.addEventListener('ended', () => TelaAcesa.set(false), true);

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

// Foco de volta ao FECHAR uma camada: vale a tela do topo da pilha, não o
// `#conteudo`. Sem isto, sair do player aberto de dentro da grade de categoria
// (ou da busca) devolvia o foco para a seção que está ATRÁS: o usuário via a
// grade e navegava, invisível, no que estava por baixo.
function focarTopo() {
  const modais = document.querySelectorAll('.nav-modal');
  const topo = modais.length ? modais[modais.length - 1] : null;
  const alvo = (topo || document.getElementById('conteudo'));
  if (!alvo) return;
  // Volta pro item de onde o usuário saiu (guardado no aoFocar), não pro
  // primeiro da lista — numa grade de categoria com 200 títulos, recomeçar do
  // topo depois de cada filme é insuportável.
  const ult = alvo._ultimoFoco;
  const f = (ult && document.contains(ult) && alvo.contains(ult)) ? ult : alvo.querySelector('.focusable');
  if (f) SpatialNav.setFocus(f);
}

function fecharPlayer() {
  clearTimeout(_hideTimer);
  // Salva o ponto final ao sair (continuar assistindo / concluir → recomendação).
  // ANTES de soltar o player nativo — depois de parar não há mais posição.
  const vf = _videoVod || document.getElementById('player-video');
  if (_playerCtx && vf && vf.duration) Biblioteca.salvarProgresso(_playerCtx, vf.currentTime, vf.duration);
  if (TEM_PLAYER_NATIVO) { PlayerNativo.parar(); PlayerNativo.limparOuvintes(); }
  _videoVod = null;
  _playerCtx = null; _playerItem = null; _legendaReset();
  if (_hls) { _hls.destroy(); _hls = null; }
  // Encerra de fato a conexão. Só destruir o hls.js / remover o overlay NÃO basta:
  // um <video> com `src` mantém o socket aberto mesmo fora do DOM, e o servidor
  // IPTV continua contando aquela sessão. Depois de abrir alguns filmes isso
  // estoura o limite de telas simultâneas e tudo passa a dar erro.
  liberarVideo(vf);
  // "Continuar assistindo" mudou: se o Início está visível, atualiza-o na hora;
  // senão descarta o cache pra rebuildar na volta.
  const ativo = document.querySelector('.nav-item.ativo');
  const main = document.getElementById('conteudo');
  if (ativo && ativo.dataset.secao === 'inicio' && main && main.querySelector('.trilhos')) {
    atualizarTrilhosPerfil(main); _secCacheSet('inicio', main.firstElementChild);
  } else {
    _secCacheDel('inicio');
  }
  const ov = document.getElementById('player-overlay');
  if (ov) ov.remove();
  focarTopo();
}

// Sair do app (exigência de QA da LG/Samsung: Back na raiz devolve ao launcher).
// Pergunta antes — evita saída acidental — e chama a API nativa da plataforma.
function sairDoApp() {
  try { pararPreview(); } catch (_) {}                 // solta conexão/vídeo do live
  // Android: garante que o ExoPlayer solte a conexão antes de encerrar — o
  // provedor conta sessão, e sair com o stream aberto ocupa uma "tela".
  try { if (TEM_PLAYER_NATIVO) PlayerNativo.parar(); } catch (_) {}
  try { liberarVideo(document.getElementById('player-video')); } catch (_) {}
  try { salvarMetaTmdb(); } catch (_) {}               // best-effort: persiste o cache
  // Android TV / Fire TV (shell WebView do tv-android): window.close() nao
  // encerra a Activity — a ponte nativa e a unica forma de sair de verdade.
  if (window.HeroPlayAndroid && window.HeroPlayAndroid.sair) {
    try { window.HeroPlayAndroid.sair(); return; } catch (_) {}
  }
  // Samsung Tizen
  if (window.tizen && tizen.application) {
    try { tizen.application.getCurrentApplication().exit(); return; } catch (_) {}
  }
  // LG webOS (e navegador): window.close encerra o app empacotado.
  try { window.close(); } catch (_) {}
  // Fallback webOS antigo.
  if (window.webOS && webOS.platformBack) { try { webOS.platformBack(); } catch (_) {} }
}
function confirmarSairApp() {
  if (typeof confirmarAcao === 'function') {
    confirmarAcao(t('Sair do Hero Play?'), t('Você voltará à tela inicial da TV.'), sairDoApp);
  } else {
    sairDoApp();
  }
}

// Abre a seção "TV ao vivo" JÁ no canal indicado (usado pelo modal de Jogos).
// Antes o modal chamava abrirLive() direto, mas abrirLive só MAXIMIZA a preview
// que já existe na seção ao vivo — fora dela não há <video>, então dava só o
// layout transparente. Aqui entramos na seção, abrimos a categoria do canal e o
// selecionamos como preview (o usuário vai p/ a direita e maximiza se quiser).
function abrirTvNoCanal(canal) {
  if (!canal) return;
  navegar('tvaovivo');
  // navegar() monta a UI de forma síncrona; abrimos a categoria do canal.
  const cat = canal.categoria;
  const catBloqueada = typeof canalCatBloqueada === 'function' && canalCatBloqueada(cat);
  const seguir = () => {
    mostrarCanais(cat, true);
    // Seleciona o canal na lista (preview começa a tocar) e foca nele.
    const cel = document.querySelector(`#tv-pane-canais .tv-canal-main[data-canal="${canal.id}"]`);
    selecionarPreview(canal);
    if (cel) SpatialNav.setFocus(cel);
  };
  if (catBloqueada) { pedirPin(seguir); return; }
  seguir();
}

// ── Player de TV AO VIVO (full-screen estilo TV a cabo) ─────────────────────
function abrirLive(canal) {
  clearInterval(_relogioInt); _relogioInt = null; // defensivo: nunca 2 relogios
  const ov = document.createElement('div');
  ov.id = 'live-overlay';
  ov.className = 'nav-modal player-modal';
  ov.innerHTML = `
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
      <button class="live-top-btn focusable" data-acao="audio">
        <svg viewBox="0 0 24 24"><path d="M3 10v4h4l5 5V5L7 10H3z"/><path d="M16 8.5a4 4 0 0 1 0 7" stroke="#fff" stroke-width="1.8" fill="none"/></svg> ${escapar(t('Áudio'))}
      </button>
      <button class="live-top-btn focusable" data-acao="legendas">
        <span class="cc">CC</span>
      </button>
    </div>
    <div class="live-bar">
      <div class="live-bar-esq">
        <span class="live-num">${canal.num}</span>
        <span class="live-canal-nome">${escapar(canal.nome)}</span>
      </div>
      <div class="live-bar-centro" id="live-prog-centro">${htmlBarraProg(canal)}</div>
      <div class="live-bar-dir">
        <div class="live-relogio" id="live-relogio">--:--</div>
        <div class="live-logo" style="background:${gradiente(canal.nome, true)}">${logoCanalInner(canal.nome, canal.logo)}</div>
        <button class="live-epg-btn focusable" data-acao="epg">
          <svg viewBox="0 0 24 24"><rect x="3" y="4" width="18" height="16" rx="2" stroke="#fff" stroke-width="2" fill="none"/><path d="M3 9h18M8 4v16" stroke="#fff" stroke-width="2"/></svg> Programação
        </button>
      </div>
    </div>`;
  document.body.appendChild(ov);
  ov._onVoltar = fecharLive;

  // Maximiza SEM tocar no DOM: só marcamos a moldura do preview como `.cheia` e o
  // CSS a leva a tela inteira. Antes movíamos o <video> para dentro do overlay —
  // reparentar um media element faz o pipeline nativo da TV recriar o player, o
  // que dava tela preta até trocar de fonte/qualidade. Agora é o MESMO player,
  // tocando ininterruptamente; só muda o tamanho.
  const pv = document.getElementById('tv-prev-video');
  const tela = document.querySelector('.tv-tela');
  if (tela) tela.classList.add('cheia');
  // Som ligado em tela cheia. A preview já vem com som; isto garante o caso de
  // ela ter caído para mudo por recusa de autoplay (ver `tocarVideo`) — aqui há
  // um gesto do usuário bem recente, então a plataforma aceita.
  definirMudo(false);
  if (pv && !TEM_PLAYER_NATIVO) tocarVideo(pv, false);

  const q = (a) => ov.querySelector(`[data-acao="${a}"]`);
  q('fechar').addEventListener('click', fecharLive);
  q('favoritar').addEventListener('click', () => alternarFavorito(canal.id));
  // Legendas/áudio do canal ao vivo (o <video> é o do preview, reusado aqui).
  q('audio').addEventListener('click', () => abrirMenuAudio(document.getElementById('tv-prev-video')));
  q('legendas').addEventListener('click', () => abrirMenuLegendas(document.getElementById('tv-prev-video')));
  q('qualidade').addEventListener('click', () => {
    const fonte = _qAtual && _qAtual.fontes[_qAtual.fi];
    const vars = fonte ? variantesDaFonte(fonte) : (canal.variantes || []);
    if (vars.length < 2) { toast(t('Sem outras qualidades nesta fonte')); return; }
    abrirMenu(t('Qualidade'), vars.map((v) => v.rotulo), (i) => { if (_qAtual) _qAtual.vi = i; tocarNoPreview(vars[i].url, false); });
  });
  q('fontes').addEventListener('click', () => {
    const fontes = _qAtual ? _qAtual.fontes : fontesDoCanal(canal);
    if (fontes.length < 2) { toast(t('Sem outras fontes')); return; }
    abrirMenu(t('Fontes'), fontes.map((f, i) => f.nome || (t('Fonte') + ' ' + (i + 1))), (i) => {
      const f = fontes[i], vars = variantesDaFonte(f), v = escolherVariante(vars, qualidadePadrao());
      if (_qAtual) { _qAtual.fi = i; _qAtual.vi = Math.max(0, vars.indexOf(v)); }
      tocarNoPreview((v || f).url, false);
    });
  });
  q('epg').addEventListener('click', () => abrirModalEpg(canal));

  // Relógio a cada segundo e, de carona, a barra de programação: ela precisa
  // virar sozinha quando o programa acaba (a pessoa pode ficar horas no canal) e
  // quando o EPG termina de baixar em 2º plano. Só reescreve o DOM se o HTML
  // MUDOU — comparar duas strings 1x por segundo é barato; repintar não é.
  let _progHtml = '';
  const tick = () => {
    const r = document.getElementById('live-relogio');
    if (r) r.textContent = hhmm(new Date());
    const c = document.getElementById('live-prog-centro');
    if (!c) return;
    const novo = htmlBarraProg(canal);
    if (novo !== _progHtml) { c.innerHTML = novo; _progHtml = novo; }
  };
  _progHtml = htmlBarraProg(canal);
  tick();
  _relogioInt = setInterval(tick, 1000);

  revelarControles();
  SpatialNav.setFocus(q('epg'));
}

function fecharLive() {
  clearTimeout(_hideTimer);
  clearInterval(_relogioInt); _relogioInt = null;
  // Volta ao tamanho de preview — o vídeo nunca saiu do lugar e CONTINUA com
  // som (a preview passou a ter áudio; antes voltava mudo aqui).
  const tela = document.querySelector('.tv-tela');
  if (tela) tela.classList.remove('cheia');
  const ov = document.getElementById('live-overlay');
  if (ov) ov.remove();
  const alvo = document.querySelector('.tv-tela') || document.querySelector('#conteudo .focusable');
  if (alvo) SpatialNav.setFocus(alvo);
}

// Menu de seleção (qualidade/fonte) sobreposto ao player. D-pad: cima/baixo +
// OK; Voltar fecha. onPick recebe o índice escolhido.
/**
 * "AGORA" + "A seguir" da barra do ao vivo em tela cheia.
 *
 * A fonte é o EPG (`EPG.agora` devolve `{atual, prox}`), NÃO o canal: os campos
 * `canal.prox`/`canal.proxIni` nascem string vazia no parse da lista e nunca são
 * preenchidos — era por isso que o espaço do "A seguir:" ficava em branco.
 * Sem EPG casado para o canal, a linha do "A seguir" simplesmente não aparece:
 * melhor não ter a linha do que ter uma prometendo um dado que não existe.
 */
function htmlBarraProg(canal) {
  const ag = (typeof EPG !== 'undefined') ? EPG.agora(canal) : { atual: null, prox: null };
  const atual = (ag.atual && ag.atual.titulo) || canal.agora || t('Ao vivo');
  const linhaProx = ag.prox
    ? `<div class="live-prog-prox">${escapar(t('A seguir'))}: <b>${escapar(ag.prox.titulo)}</b> · ${hhmm(new Date(ag.prox.ini))}</div>`
    : '';
  return `<div class="live-prog-atual">${escapar(atual)}</div>${linhaProx}`;
}

// Programação do canal em TELA CHEIA. Antes era um `toast('em breve')` — mas a
// grade já existe e é a MESMA que a coluna direita da TV ao vivo mostra
// (`htmlEpg`), então aqui é só trazê-la para um modal com a cara dos outros.
function abrirModalEpg(canal) {
  const ov = document.createElement('div');
  ov.className = 'nav-modal menu-opcoes epg-modal';
  ov.innerHTML = `
    <div class="mo-card epg-card">
      <div class="epg-cab">
        <div class="live-logo epg-logo" style="background:${gradiente(canal.nome, true)}">${logoCanalInner(canal.nome, canal.logo)}</div>
        <div>
          <div class="epg-canal">${canal.num} · ${escapar(canal.nome)}</div>
          <div class="epg-agora">${rotuloAgora(canal)}</div>
        </div>
      </div>
      <div class="epg-lista">${htmlEpg(canal)}</div>
      <button class="btn btn-secundario focusable" data-acao="epg-fechar">${escapar(t('Fechar'))}</button>
    </div>`;
  document.body.appendChild(ov);
  const anterior = SpatialNav.atual;
  const fechar = () => {
    ov.remove();
    if (anterior && document.contains(anterior)) SpatialNav.setFocus(anterior);
    revelarControles();   // o modal come o timer de esconder os controles
  };
  ov._onVoltar = fechar;
  ov.querySelector('[data-acao="epg-fechar"]').addEventListener('click', fechar);
  SpatialNav.setFocus(ov.querySelector('[data-acao="epg-fechar"]'));
}

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
// ── Teclado on-screen (TV) ───────────────────────────────────────────────────
// O IME do sistema é inconstante em Tizen/webOS (e no desktop nem aparece), então
// os campos de texto (Xtream/URL) abrem ESTE teclado próprio, navegável por D-pad.
// Também aceita teclado físico (desktop/teste). Abre ao ativar (Enter/clique) o campo.
let _kbShift = false;
// TVs (LG webOS / Samsung Tizen) têm teclado virtual NATIVO do sistema que abre
// ao focar um <input>. Nesses casos NÃO abrimos o nosso (evita 2 teclados) —
// só focamos o campo e deixamos o nativo agir. No desktop/navegador comum (sem
// VKB do sistema), abrimos o teclado on-screen do Hero Play.
//
// ⚠️ O TV Box/Fire TV fica de FORA: o userAgent da casca Android também diz
// "SmartTV", mas o teclado de lá é o IME do Android — ele abre sozinho ao focar
// o campo, cobre o app e o Voltar do controle não fecha (a Activity intercepta o
// Back e manda pro app). Resultado: onboarding travado com o teclado aberto.
// Lá usamos o teclado do próprio app, que é navegável por D-pad e fecha no Back.
const _tvComTecladoNativo = () => !EH_ANDROID_TV && /web[0o]s|tizen|netcast|smart-?tv/i.test(navigator.userAgent);
function abrirTeclado(input) {
  if (!input || document.querySelector('.tv-kb')) return;
  if (_tvComTecladoNativo()) {
    try { input.focus({ preventScroll: true }); } catch (_) { try { input.focus(); } catch (_) {} }
    return;
  }
  const ov = document.createElement('div');
  ov.className = 'nav-modal tv-kb';
  const rotulo = input.getAttribute('placeholder') || t('Digite');
  let valor = input.value || '';
  _kbShift = false;
  const linhas = ['1234567890', 'qwertyuiop', 'asdfghjkl', 'zxcvbnm'];
  const simbolos = ['.', '/', ':', '@', '-', '_', '?', '&', '=', '+'];

  const pintar = () => {
    const d = ov.querySelector('#tv-kb-disp');
    if (d) d.innerHTML = (valor ? escapar(valor) : `<span class="tv-kb-ph">${escapar(t('Digite…'))}</span>`) + '<span class="tv-kb-caret"></span>';
  };
  const aplicar = () => { input.value = valor; input.dispatchEvent(new Event('input', { bubbles: true })); };
  const digitar = (t) => { valor += t; aplicar(); pintar(); };
  const render = () => {
    const up = _kbShift;
    const rows = linhas.map((ln, i) => {
      const keys = [...ln].map((c) => { const ch = up ? c.toUpperCase() : c; return `<button class="tv-kb-key focusable" data-k="${ch}">${ch}</button>`; }).join('');
      const extra = i === 3
        ? `<button class="tv-kb-key tv-kb-act focusable" data-acao="shift"${up ? ' data-on="1"' : ''}>⇧</button><button class="tv-kb-key tv-kb-act focusable" data-acao="apagar">⌫</button>`
        : '';
      return `<div class="tv-kb-row">${keys}${extra}</div>`;
    }).join('');
    const simbRow = `<div class="tv-kb-row">${simbolos.map((c) => `<button class="tv-kb-key focusable" data-k="${c}">${c === '&' ? '&amp;' : c}</button>`).join('')}</div>`;
    const acaoRow = `<div class="tv-kb-row">
      <button class="tv-kb-key tv-kb-wide focusable" data-k=".com">.com</button>
      <button class="tv-kb-key tv-kb-space focusable" data-acao="espaco">${escapar(t('Espaço'))}</button>
      <button class="tv-kb-key tv-kb-wide focusable" data-acao="limpar">${escapar(t('Limpar'))}</button>
      <button class="tv-kb-key tv-kb-ok focusable" data-acao="ok">OK</button>
    </div>`;
    ov.innerHTML = `<div class="tv-kb-card">
      <div class="tv-kb-titulo">${escapar(rotulo)}</div>
      <div class="tv-kb-display" id="tv-kb-disp"></div>
      <div class="tv-kb-grid">${rows}${simbRow}${acaoRow}</div>
    </div>`;
    pintar();
  };
  const fisico = (e) => {
    if (e.key && e.key.length === 1 && !e.ctrlKey && !e.metaKey && !e.altKey) {
      valor += e.key; aplicar(); pintar(); e.stopPropagation(); e.preventDefault();
    }
  };
  const fechar = () => { aplicar(); window.removeEventListener('keydown', fisico, true); ov.remove(); SpatialNav.setFocus(input); };

  ov.addEventListener('click', (e) => {
    const k = e.target.closest('.tv-kb-key'); if (!k) return;
    const a = k.dataset.acao;
    if (a === 'ok') return fechar();
    if (a === 'shift') { _kbShift = !_kbShift; render(); const s = ov.querySelector('[data-acao="shift"]'); if (s) SpatialNav.setFocus(s); return; }
    if (a === 'apagar') { valor = valor.slice(0, -1); aplicar(); pintar(); return; }
    if (a === 'espaco') return digitar(' ');
    if (a === 'limpar') { valor = ''; aplicar(); pintar(); return; }
    digitar(k.dataset.k);
  });

  render();
  document.body.appendChild(ov);
  ov._onVoltar = fechar;
  window.addEventListener('keydown', fisico, true);
  SpatialNav.setFocus(ov.querySelector('.tv-kb-key'));
}

function mostrarOnboarding() {
  document.getElementById('app').classList.add('oculto');
  let ob = document.getElementById('onboarding');
  if (!ob) {
    ob = document.createElement('div');
    ob.id = 'onboarding';
    ob.className = 'nav-modal';
    document.body.appendChild(ob);
  }
  // O onboarding E a raiz do app: o Voltar aqui nao tem para onde ir, entao
  // pergunta se quer SAIR (as lojas exigem que o Back na raiz devolva ao
  // launcher). Antes era um no-op e o usuario ficava preso no app.
  ob._onVoltar = () => confirmarSairApp();
  ob.innerHTML = `
    <div class="ob-wrap ob-grid">
      <div class="ob-top">
        <div class="logo ob-logo"><img class="logo-mark" src="heroplay-icon.svg" alt="Hero Play"><span class="ob-logo-text"><b>Hero</b> Play</span></div>
      </div>

      <div class="ob-left">
        <h2 class="ob-h2">${escapar(t('Adicionar Playlist'))}</h2>
        <div class="ob-qr" id="ob-qr"></div>
        <div class="ob-left-txt">${t('Adicione e ative <b>tudo pelo site</b>')}</div>
        <div class="ob-link">heroplaytv.com/upload</div>
        <button class="btn btn-secundario focusable" id="ob-reload">${escapar(t('↻ Recarregar'))}</button>
        <div class="ob-espera" id="ob-espera"><span class="ob-espera-dot"></span>${escapar(t('Aguardando a playlist…'))}</div>
        <div class="ob-ou"><span>${escapar(t('ou'))}</span></div>
        <div class="ob-hint">${escapar(t('Use as credenciais ou a URL da playlist no formulário ao lado'))}</div>
      </div>

      <div class="ob-right">
        <h2 class="ob-h2 ob-right-h">${escapar(t('Entrar com credenciais'))}</h2>
        <div class="ob-tabs">
          <button class="ob-tab focusable ativo" data-modo="xtream">Xtream</button>
          <button class="ob-tab focusable" data-modo="m3u">M3U / URL</button>
        </div>
        <div class="ob-form" id="ob-form-xtream">
          <div class="ob-campo"><span class="ob-ico">${IC_GLOBO}</span><input class="ob-input focusable" id="x-host" placeholder="${escapar(t('Servidor ou código'))}" autocomplete="off" spellcheck="false"></div>
          <div class="ob-campo"><span class="ob-ico">${IC_USER}</span><input class="ob-input focusable" id="x-user" placeholder="${escapar(t('Usuário'))}" autocomplete="off" spellcheck="false"></div>
          <div class="ob-campo"><span class="ob-ico">${IC_LOCK}</span><input class="ob-input focusable" id="x-pass" type="password" placeholder="${escapar(t('Senha'))}" autocomplete="off" spellcheck="false"></div>
        </div>
        <div class="ob-form oculto" id="ob-form-m3u">
          <div class="ob-campo"><span class="ob-ico">${IC_LINK}</span><input class="ob-input focusable" id="m-url" placeholder="https://.../lista.m3u" autocomplete="off" spellcheck="false"></div>
        </div>
        <button class="btn btn-primario focusable" id="ob-add">${escapar(t('Conectar'))}</button>
        <div class="ob-erro" id="ob-erro"></div>
      </div>
    </div>
    <div class="ob-cred-fixo">
      <div>Key: <b>${Dispositivo.key()}</b></div>
      <div>Mac: <b>${Dispositivo.mac()}</b></div>
      <div class="ob-versao">${escapar(etiquetaVersao())}</div>
    </div>`;
  gerarQr('ob-qr', Dispositivo.urlAtivacao());
  document.getElementById('ob-reload').addEventListener('click', recarregarOnboarding);
  document.getElementById('ob-add').addEventListener('click', onboardingAdicionar);
  ob.querySelectorAll('.ob-tab').forEach((t) =>
    t.addEventListener('click', () => trocarModoOnboarding(t.dataset.modo)));
  ob.querySelectorAll('.ob-input').forEach((inp) => inp.addEventListener('click', () => abrirTeclado(inp)));
  SpatialNav.setFocus(document.getElementById('x-host'));
  ligarEsperaVinculo();
}

// ── Espera pela vinculação (o usuário não precisa apertar nada) ─────────────
//
// Enquanto o onboarding está na tela, perguntamos à nuvem de tempos em tempos
// se já vincularam uma playlist a este aparelho. Assim que vincular (pelo site
// ou pelo painel do revendedor), a TV entra sozinha — o "↻ Recarregar" vira
// atalho para quem não quer esperar, não uma obrigação.
let _obPoll = null, _obPollInicio = 0;

function pararEsperaVinculo() {
  if (_obPoll) { clearTimeout(_obPoll); _obPoll = null; }
}

function ligarEsperaVinculo() {
  pararEsperaVinculo();
  _obPollInicio = Date.now();

  const agendar = () => {
    // 5s nos primeiros 3 minutos — é a janela em que o usuário está mexendo no
    // celular AGORA. Depois cai para 20s: uma TV pode ficar horas nesta tela e
    // não faz sentido martelar a Edge Function a noite toda.
    const decorrido = Date.now() - _obPollInicio;
    _obPoll = setTimeout(tick, decorrido < 180000 ? 5000 : 20000);
  };

  async function tick() {
    _obPoll = null;
    // Saiu do onboarding (entrou pelo formulário, por exemplo): para.
    if (!document.getElementById('onboarding')) return;
    // App em segundo plano: não gasta rede, só re-agenda.
    if (document.hidden) return agendar();
    try {
      await Dispositivo.consultar();
      if (Dispositivo.temLista()) {
        pararEsperaVinculo();
        toast(t('Playlist encontrada! Carregando…'));
        const ob = document.getElementById('onboarding');
        if (ob) ob.remove();
        iniciarApp();
        return;
      }
    } catch (_) { /* rede instável: tenta de novo no próximo ciclo */ }
    agendar();
  }

  agendar();
}

function trocarModoOnboarding(modo) {
  document.querySelectorAll('.ob-tab').forEach((t) =>
    t.classList.toggle('ativo', t.dataset.modo === modo));
  document.getElementById('ob-form-xtream').classList.toggle('oculto', modo !== 'xtream');
  document.getElementById('ob-form-m3u').classList.toggle('oculto', modo !== 'm3u');
  const primeiro = (modo === 'xtream') ? 'x-host' : 'm-url';
  SpatialNav.setFocus(document.getElementById(primeiro));
}

// O campo "Servidor" aceita o ENDERECO ou o CODIGO que o admin cadastrou em
// Servidores no painel — o cliente digita "1234" no controle em vez de um
// endereco inteiro. Com ":" (esquema ou porta) e endereco, como sempre foi.
const _pareceCodigoServidor = (v) => !v.includes(':') && /^[A-Za-z0-9._-]{2,64}$/.test(v);

// Devolve { host } ou { erro }. Sem ponto nao existe dominio: se a nuvem nao
// conhece o codigo, e codigo errado, e dizer isso poupa uma lista que nunca
// carrega. Com ponto e nao sendo codigo ("servidor.com"), segue como host.
async function hostDoCampo(valor) {
  const v = (valor || '').trim();
  if (!_pareceCodigoServidor(v)) return { host: v };
  const r = await Dispositivo.resolverServidor(v);
  if (r.host) return { host: r.host };
  if (v.includes('.')) return { host: v };
  return {
    erro: r.motivo === 'offline'
      ? t('Sem conexão para conferir o código do servidor.')
      : t('Código de servidor não encontrado.'),
  };
}

// Barra o "Conectar" repetido enquanto o codigo e conferido: no controle remoto
// o OK repete facil, e cada toque criaria uma playlist na nuvem.
let _conferindoServidor = false;

// Adiciona a lista digitada no proprio app (Xtream OU M3U). "Traga sua lista":
// sem venda no app — só configura a playlist do cliente. Inicia o teste (trial).
async function onboardingAdicionar() {
  if (_conferindoServidor) return;
  const val = (id) => (document.getElementById(id).value || '').trim();
  const erro = (m) => { document.getElementById('ob-erro').textContent = m; };
  const _tab = document.querySelector('.ob-tab.ativo');
  const modo = (_tab && _tab.dataset.modo) || 'xtream';
  let lista_url, epg_url, user = '';

  if (modo === 'xtream') {
    const campo = val('x-host'); user = val('x-user'); const pass = val('x-pass');
    if (!campo || !user || !pass) return erro(t('Preencha servidor, usuário e senha.'));
    _conferindoServidor = true;
    try {
      if (_pareceCodigoServidor(campo)) mostrarLoading(t('Conferindo o servidor…'));
      const r = await hostDoCampo(campo);
      if (r.erro) { esconderLoading(); return erro(r.erro); }
      ({ lista_url, epg_url } = ListaUtil.montarXtream(r.host, user, pass));
    } finally { _conferindoServidor = false; }
  } else {
    lista_url = val('m-url');
    if (!/^https?:\/\//i.test(lista_url)) return erro(t('Informe uma URL M3U válida (http/https).'));
    epg_url = ListaUtil.derivarEpg(lista_url);
  }

  // Registra na nuvem (best-effort) + grava local, depois carrega a lista.
  pararEsperaVinculo();   // o usuário resolveu pelo formulário
  const ob = document.getElementById('onboarding');
  if (ob) ob.remove();
  mostrarLoading(t('Adicionando sua lista…'));
  Dispositivo.adicionar(lista_url, epg_url, _nomeDaPlaylist(modo, lista_url, user)).then(() => iniciarApp());
}

async function recarregarOnboarding() {
  toast(t('Verificando…'));
  await Dispositivo.consultar();
  if (Dispositivo.temLista()) {
    pararEsperaVinculo();
    const ob = document.getElementById('onboarding');
    if (ob) ob.remove();
    iniciarApp();
  } else {
    toast(t('Nenhuma lista ainda. Adicione no celular e tente de novo.'));
  }
}

/**
 * ASSINATURA VENCIDA: tela de bloqueio.
 *
 * O servidor já para de mandar a lista quando o plano vence — mas o catálogo
 * fica em cache AQUI, com os links dos streams dentro, então sem esta tela o
 * aparelho continuaria tocando offline. É ela que faz "1 ano" significar 1 ano.
 *
 * NEUTRA de propósito (regra das lojas): diz o que aconteceu e manda falar com
 * o provedor. Sem preço, sem link de pagamento, sem CTA de compra. O MAC/Key
 * aparecem porque é como o provedor acha o aparelho.
 */
let _expPoll = null;
function mostrarExpirado() {
  const app = document.getElementById('app'); if (app) app.classList.add('oculto');
  document.querySelectorAll('#onboarding, #aviso-teste').forEach((e) => e.remove());
  let ov = document.getElementById('expirado');
  if (!ov) {
    ov = document.createElement('div');
    ov.id = 'expirado';
    ov.className = 'nav-modal';
    document.body.appendChild(ov);
  }
  // Raiz do app: Back pergunta se quer sair (as lojas exigem devolver ao launcher).
  ov._onVoltar = () => confirmarSairApp();
  ov.innerHTML = `
    <div class="aviso-card">
      <div class="aviso-badge aviso-badge-off">${escapar(t('Ativação expirada'))}</div>
      <h1 class="aviso-titulo">${escapar(t('Este aparelho não está mais ativo'))}</h1>
      <p class="aviso-sub">${escapar(t('A ativação deste aparelho venceu. Fale com quem forneceu o seu acesso para renovar — assim que renovarem, o app volta sozinho.'))}</p>
      <div class="exp-ids">
        <div>Mac: <b>${escapar(Dispositivo.mac())}</b></div>
        <div>Key: <b>${escapar(Dispositivo.key())}</b></div>
      </div>
      <button class="btn btn-primario focusable" id="exp-check">${escapar(t('Verificar de novo'))}</button>
      <div class="ob-versao">${escapar(etiquetaVersao())}</div>
    </div>`;
  const verificar = async () => {
    const b = document.getElementById('exp-check');
    if (b) { b.disabled = true; b.textContent = t('Verificando…'); }
    try { await Dispositivo.consultar(); } catch (_) { /* offline: segue bloqueado */ }
    if (!Dispositivo.expirado() && Dispositivo.temLista()) return liberarExpirado();
    if (b) { b.disabled = false; b.textContent = t('Verificar de novo'); }
  };
  document.getElementById('exp-check').addEventListener('click', verificar);
  SpatialNav.setFocus(document.getElementById('exp-check'));
  // Renovou no painel? A TV entra sozinha, sem ninguém apertar nada.
  if (_expPoll) clearInterval(_expPoll);
  _expPoll = setInterval(async () => {
    if (!document.getElementById('expirado') || document.hidden) return;
    try { await Dispositivo.consultar(); } catch (_) { return; }
    if (!Dispositivo.expirado() && Dispositivo.temLista()) liberarExpirado();
  }, 30000);
}
function liberarExpirado() {
  if (_expPoll) { clearInterval(_expPoll); _expPoll = null; }
  const ov = document.getElementById('expirado'); if (ov) ov.remove();
  toast(t('Ativação renovada! Carregando…'));
  iniciarApp();
}

// Aviso grande de periodo de teste (apos a lista ser adicionada e device inativo).
function mostrarAvisoTeste() {
  if (sessionStorage.getItem('aviso_teste_visto')) return;
  const ov = document.createElement('div');
  ov.id = 'aviso-teste';
  ov.className = 'nav-modal';
  ov.innerHTML = `
    <div class="aviso-card">
      <div class="aviso-badge">${escapar(t('Período de teste'))}</div>
      <h1 class="aviso-titulo">${escapar(t('{n} dias grátis').replace('{n}', Dispositivo.diasTeste()))}</h1>
      <p class="aviso-sub">${escapar(t('Sua lista foi adicionada e o app está em teste. Para continuar depois do período, ative o app — você mesmo pode ativar escaneando o QR.'))}</p>
      <div class="ob-qr" id="aviso-qr"></div>
      <div class="aviso-rotulo">${escapar(t('Ativar / gerenciar'))}</div>
      <div class="ob-link">heroplaytv.com/upload</div>
      <button class="btn btn-primario focusable" id="aviso-ok">${escapar(t('Continuar no teste'))}</button>
      <div class="ob-versao">${escapar(etiquetaVersao())}</div>
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

// ── Playlists (Minhas Playlists) ────────────────────────────────────────────
const IC_PL_REFRESH = '<svg viewBox="0 0 24 24" style="fill:none" fill="none" stroke="currentColor" stroke-width="2" stroke-linecap="round" stroke-linejoin="round"><path d="M21 12a9 9 0 1 1-2.64-6.36"/><path d="M21 3v5h-5"/></svg>';
const IC_PL_TRASH = '<svg viewBox="0 0 24 24" style="fill:none" fill="none" stroke="currentColor" stroke-width="2" stroke-linecap="round" stroke-linejoin="round"><path d="M3 6h18M8 6V4h8v2M6 6l1 14h10l1-14"/></svg>';
const IC_PL_ADD = '<svg viewBox="0 0 24 24" style="fill:none" fill="none" stroke="currentColor" stroke-width="2.4" stroke-linecap="round"><path d="M12 5v14M5 12h14"/></svg>';
const IC_PL_CHECK = '<svg viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="2.8" stroke-linecap="round" stroke-linejoin="round"><path d="M20 6 9 17l-5-5"/></svg>';
let _plBusy = false;

// Catálogo vazio (estrutura segura quando o device fica sem playlist).
function _listaVazia() {
  return { catalogo: { inicio: { trilhos: [] }, filmes: { trilhos: [] }, series: { trilhos: [] } }, canais: [], filmes: [], series: [], indice: {} };
}

// Shell da tela; as playlists chegam async (Dispositivo.listarPlaylists).
function renderPlaylists() {
  return `<div class="secao secao-pl">
    <div class="pl-topo">
      <div class="pl-topo-tit">
        <h2 class="pl-titulo">${escapar(t('Minhas Playlists'))}</h2>
        <div class="pl-sub" id="pl-sub">${escapar(t('Carregando…'))}</div>
      </div>
      <div class="pl-topo-acoes">
        <button class="btn btn-secundario focusable" id="pl-add">${IC_PL_ADD} ${escapar(t('Adicionar Playlist'))}</button>
        <button class="btn btn-secundario focusable" id="pl-atualizar">${IC_PL_REFRESH} ${escapar(t('Atualizar'))}</button>
      </div>
    </div>
    <div class="pl-lista" id="pl-lista"><div class="pl-skel">${escapar(t('Carregando playlists…'))}</div></div>
  </div>`;
}

// Busca as playlists DO DEVICE no Supabase (via Edge Function) e desenha as linhas.
async function preencherPlaylists() {
  const lista = document.getElementById('pl-lista');
  if (!lista) return;
  const pls = await Dispositivo.listarPlaylists();
  if (!document.getElementById('pl-lista')) return; // saiu da tela
  const sub = document.getElementById('pl-sub');
  if (sub) sub.textContent = pls.length ? `${pls.length} ${t(pls.length > 1 ? 'playlists' : 'playlist')}` : t('Nenhuma playlist');
  if (!pls.length) {
    lista.innerHTML = `<div class="pl-vazio">
      <div class="pl-vazio-tit">${escapar(t('Nenhuma playlist neste dispositivo'))}</div>
      <div class="pl-vazio-sub">${escapar(t('Use "Adicionar Playlist" para começar'))}</div>
    </div>`;
    return;
  }
  lista.innerHTML = pls.map((p) => `
    <div class="pl-row${p.selecionada ? ' ativa' : ''}">
      <button class="pl-row-nome focusable" data-acao="selecionar" data-id="${escapar(p.id)}">
        <span class="pl-check">${p.selecionada ? IC_PL_CHECK : ''}</span>
        <span class="pl-nome">${escapar(p.nome || 'Playlist')}</span>
        ${p.tipo ? `<span class="pl-tipo">${escapar(p.tipo)}</span>` : ''}
      </button>
      <button class="pl-row-btn focusable" data-acao="recarregar" data-id="${escapar(p.id)}" title="${escapar(t('Recarregar títulos'))}">${IC_PL_REFRESH}</button>
      <button class="pl-row-btn pl-row-del focusable" data-acao="excluir" data-id="${escapar(p.id)}" title="${escapar(t('Excluir'))}">${IC_PL_TRASH}</button>
    </div>`).join('');
}

// Recarrega o catálogo a partir da playlist ATIVA do device (após selecionar/excluir/add).
async function _recarregarCatalogoAtivo() {
  await Dispositivo.consultar();                 // GET retorna a URL da playlist selecionada
  const reg = Dispositivo.registro();
  // `true` = ignora o cache e re-parseia (é isto que "Recarregar"/trocar playlist
  // deve fazer; o boot normal usa o cache).
  if (reg && reg.lista_url) { const ok = await carregarLista(reg.lista_url, true); if (!ok) aplicarLista(_listaVazia()); }
  else aplicarLista(_listaVazia());
  _heroItem = null;                              // força o hero a atualizar
  limparCacheSecoes();                           // catálogo mudou → descarta o DOM cacheado
  precarregarLogosCanais();                      // re-aquece os ícones da nova lista
}

// Ações das linhas de playlist (selecionar/recarregar ativam a playlist e
// recarregam os títulos; excluir tira do device e apaga do Supabase se órfã).
async function acaoPlaylist(acao, id) {
  if (_plBusy || !id) return;
  _plBusy = true;
  try {
    if (acao === 'excluir') {
      toast(t('Excluindo…'));
      await Dispositivo.excluirPlaylist(id);
      await _recarregarCatalogoAtivo();
      toast(t('Playlist excluída'));
    } else { // selecionar | recarregar
      toast(acao === 'recarregar' ? t('Recarregando títulos…') : t('Selecionando…'));
      await Dispositivo.selecionarPlaylist(id);
      await _recarregarCatalogoAtivo();
      toast(t('Pronto'));
    }
  } finally { _plBusy = false; }
  preencherPlaylists();                          // atualiza ✓/contagem
}

// Deriva o nome da playlist a partir das credenciais (Xtream: usuário; M3U: host).
function _nomeDaPlaylist(modo, lista_url, user) {
  if (modo === 'xtream') return (user || '').trim() || 'Playlist';
  try { const u = new URL(lista_url); return u.searchParams.get('username') || u.hostname || 'Playlist'; } catch (_) { return 'Playlist'; }
}

// Tela "Adicionar Playlist" (overlay estilo onboarding: QR + Xtream/M3U). Ao
// conectar, adiciona a playlist (nome derivado), recarrega e volta p/ Playlists.
function abrirAddPlaylist() {
  const ov = document.createElement('div');
  ov.className = 'nav-modal addpl';
  ov.innerHTML = `
    <div class="ob-wrap ob-grid">
      <div class="ob-top"><div class="logo ob-logo"><img class="logo-mark" src="heroplay-icon.svg" alt="Hero Play"><span class="ob-logo-text"><b>Hero</b> Play</span></div></div>
      <div class="ob-left">
        <h2 class="ob-h2">${escapar(t('Adicionar Playlist'))}</h2>
        <div class="ob-qr" id="ap-qr"></div>
        <div class="ob-left-txt">${t('Adicione e ative <b>tudo pelo site</b>')}</div>
        <div class="ob-link">heroplaytv.com/upload</div>
        <div class="ap-cred"><span>Key <b>${Dispositivo.key()}</b></span><span>MAC <b>${Dispositivo.mac()}</b></span></div>
        <div class="ob-ou"><span>${escapar(t('ou'))}</span></div>
        <div class="ob-hint">${escapar(t('Use as credenciais ou a URL da playlist ao lado'))}</div>
      </div>
      <div class="ob-right">
        <h2 class="ob-h2 ob-right-h">${escapar(t('Adicionar por credenciais ou Link'))}</h2>
        <div class="ob-tabs">
          <button class="ob-tab focusable ativo" data-modo="xtream">Xtream</button>
          <button class="ob-tab focusable" data-modo="m3u">M3U / URL</button>
        </div>
        <div class="ob-form" id="ap-form-xtream">
          <div class="ob-campo"><span class="ob-ico">${IC_GLOBO}</span><input class="ob-input focusable" id="ap-host" placeholder="${escapar(t('Servidor ou código'))}" autocomplete="off" spellcheck="false"></div>
          <div class="ob-campo"><span class="ob-ico">${IC_USER}</span><input class="ob-input focusable" id="ap-user" placeholder="${escapar(t('Usuário'))}" autocomplete="off" spellcheck="false"></div>
          <div class="ob-campo"><span class="ob-ico">${IC_LOCK}</span><input class="ob-input focusable" id="ap-pass" type="password" placeholder="${escapar(t('Senha'))}" autocomplete="off" spellcheck="false"></div>
        </div>
        <div class="ob-form oculto" id="ap-form-m3u">
          <div class="ob-campo"><span class="ob-ico">${IC_LINK}</span><input class="ob-input focusable" id="ap-url" placeholder="https://.../lista.m3u" autocomplete="off" spellcheck="false"></div>
        </div>
        <button class="btn btn-primario focusable" id="ap-add">${escapar(t('Conectar'))}</button>
        <div class="ob-erro" id="ap-erro"></div>
      </div>
    </div>`;
  document.body.appendChild(ov);
  ov._onVoltar = () => { ov.remove(); const f = document.getElementById('pl-add'); if (f) SpatialNav.setFocus(f); };
  gerarQr('ap-qr', Dispositivo.urlAtivacao());
  ov.querySelectorAll('.ob-tab').forEach((t) => t.addEventListener('click', () => {
    ov.querySelectorAll('.ob-tab').forEach((x) => x.classList.toggle('ativo', x === t));
    ov.querySelector('#ap-form-xtream').classList.toggle('oculto', t.dataset.modo !== 'xtream');
    ov.querySelector('#ap-form-m3u').classList.toggle('oculto', t.dataset.modo !== 'm3u');
    SpatialNav.setFocus(document.getElementById(t.dataset.modo === 'xtream' ? 'ap-host' : 'ap-url'));
  }));
  ov.querySelector('#ap-add').addEventListener('click', () => addPlaylistSubmit(ov));
  ov.querySelectorAll('.ob-input').forEach((inp) => inp.addEventListener('click', () => abrirTeclado(inp)));
  SpatialNav.setFocus(document.getElementById('ap-host'));
}

async function addPlaylistSubmit(ov) {
  if (_conferindoServidor) return;
  const val = (id) => (document.getElementById(id).value || '').trim();
  const erro = (m) => { const e = document.getElementById('ap-erro'); if (e) e.textContent = m; };
  const _tab = ov.querySelector('.ob-tab.ativo');
  const modo = (_tab && _tab.dataset.modo) || 'xtream';
  let lista_url, epg_url, user = '';
  if (modo === 'xtream') {
    const campo = val('ap-host'); user = val('ap-user'); const pass = val('ap-pass');
    if (!campo || !user || !pass) return erro(t('Preencha servidor, usuário e senha.'));
    // Mesmo campo "Servidor ou código" do onboarding — ver `hostDoCampo`.
    _conferindoServidor = true;
    try {
      if (_pareceCodigoServidor(campo)) mostrarLoading(t('Conferindo o servidor…'));
      const r = await hostDoCampo(campo);
      if (r.erro) { esconderLoading(); return erro(r.erro); }
      ({ lista_url, epg_url } = ListaUtil.montarXtream(r.host, user, pass));
    } finally { _conferindoServidor = false; }
  } else {
    lista_url = val('ap-url');
    if (!/^https?:\/\//i.test(lista_url)) return erro(t('Informe uma URL M3U válida (http/https).'));
    epg_url = ListaUtil.derivarEpg(lista_url);
  }
  ov.remove();
  mostrarLoading(t('Adicionando playlist…'));
  await Dispositivo.adicionar(lista_url, epg_url, _nomeDaPlaylist(modo, lista_url, user));
  loadingMsg(t('Carregando títulos…'));
  await _recarregarCatalogoAtivo();
  esconderLoading();
  navegar('playlists');
}

// ── Boot ────────────────────────────────────────────────────────────────────
function montarSidebar() {
  document.getElementById('nav-itens').innerHTML = MENU.map((m) =>
    `<div class="nav-item focusable" data-secao="${m.id}">
       <span class="ico">${svg(m.ico)}</span><span class="rotulo">${escapar(t(m.rotulo))}</span>
     </div>`).join('');
  document.getElementById('nav-config').innerHTML =
    `<div class="nav-item focusable" data-secao="config">
       <span class="ico">${svg('config')}</span><span class="rotulo">${escapar(t('Configurações'))}</span>
     </div>`;
  // Indicador do perfil ativo (abaixo da logo) — BOTÃO p/ trocar de perfil.
  const np = document.getElementById('nav-perfil'); const pf = Perfis.ativo();
  if (np) {
    np.innerHTML = pf
      ? `<button class="nav-perfil-btn focusable" aria-label="${escapar(t('Trocar perfil'))}"><span class="perfil-av perfil-av-mini" style="background:${_avBg(pf)}">${escapar(iniciais(pf.nome) || 'P')}</span><span class="rotulo perfil-mini-nome">${escapar(pf.nome)}</span></button>`
      : '';
    const btn = np.querySelector('.nav-perfil-btn');
    if (btn) btn.addEventListener('click', () => trocarPerfilAnimado());
  }

  document.querySelectorAll('.nav-item').forEach((n) =>
    n.addEventListener('click', () => navegar(n.dataset.secao)));
}

// Clicks de conteudo (delegado): poster abre detalhe; "Assistir" do hero idem.
document.addEventListener('click', (e) => {
  if (e.target.closest('[data-acao="tela-voltar"]')) { SpatialNav.voltar(); return; }  // botão Voltar da tela
  const btnBuscaSec = e.target.closest('[data-acao="busca-secao"]');
  if (btnBuscaSec) { abrirBuscaSecao(btnBuscaSec.dataset.escopo, btnBuscaSec); return; }
  if (e.target.closest('#pl-add')) { abrirAddPlaylist(); return; }
  if (e.target.closest('#pl-atualizar')) { toast(t('Atualizando…')); preencherPlaylists(); return; }
  const plac = e.target.closest('.secao-pl [data-acao]');
  if (plac) { acaoPlaylist(plac.dataset.acao, plac.dataset.id); return; }
  const cat = e.target.closest('.tv-cat-item');
  if (cat) { mostrarCanais(cat.dataset.cat); return; }
  const canalFav = e.target.closest('.tv-canal-fav');
  if (canalFav) { alternarFavorito(canalFav.dataset.canal); return; }   // favorita sem abrir
  const canalMain = e.target.closest('.tv-canal-main');
  if (canalMain) {
    const c = LISTA.canais.find((x) => x.id === canalMain.dataset.canal);
    if (c) selecionarPreview(c);
    return;
  }
  const tela = e.target.closest('.tv-tela');
  if (tela) { if (_tvCanalPreview) abrirLive(_tvCanalPreview); return; }
  const favBtn = e.target.closest('.tv-fav-btn');
  if (favBtn) { if (_tvCanalPreview) alternarFavorito(_tvCanalPreview.id); return; }
  // Título de trilho → tela da categoria (todos os itens dela).
  const trTit = e.target.closest('.trilho-titulo[data-cat]');
  if (trTit) {
    const sec = (document.querySelector('.nav-item.ativo') || {}).dataset || {};
    abrirCategoria(sec.secao || 'filmes', trTit.dataset.cat);
    return;
  }
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
      <div class="logo ld-logo"><img class="logo-mark" src="heroplay-icon.svg" alt="Hero Play"><span class="ob-logo-text"><b>Hero</b> Play</span></div>
      <div class="ld-barra"><span></span></div>
      <div class="ld-msg" id="ld-msg">${escapar(msg || t('Carregando…'))}</div>
      <div class="ob-versao">${escapar(etiquetaVersao())}</div>
    </div>`;
  el.style.display = 'grid';
  _ldRearmar();
}
function loadingMsg(m) { const e = document.getElementById('ld-msg'); if (e) e.textContent = m; _ldRearmar(); }
// Progresso REAL (0..100): troca a barra indeterminada por uma determinada.
// Chamada durante o download e o parse fatiado, que reportam o avanço de verdade.
function loadingProgresso(pct, rotulo) {
  const b = document.querySelector('#loading .ld-barra');
  if (!b) return;
  b.classList.add('determinada');
  const s = b.querySelector('span');
  if (s) s.style.width = Math.max(0, Math.min(100, Math.round(pct))) + '%';
  const m = document.getElementById('ld-msg');
  if (m) m.textContent = (rotulo || t('Organizando seus canais…')) + ' ' + Math.round(pct) + '%';
  _ldRearmar();
}
function esconderLoading() { clearTimeout(_ldWatch); _ldWatch = null; const el = document.getElementById('loading'); if (el) el.remove(); }

// ── Saída de emergência da tela de loading ──────────────────────────────────
// Sem isto, qualquer passo que pendure (rede, IndexedDB) deixa o app preso em
// "Baixando sua lista…" PARA SEMPRE — e, como o webOS RESUME o app em vez de
// reiniciá-lo, reabrir volta pra mesma tela travada: só reinstalar resolvia.
// Depois de LD_TRAVADO_MS SEM nenhum avanço (msg/progresso), oferecemos sair.
const LD_TRAVADO_MS = 75000;
let _ldWatch = null;
function _ldRearmar() {
  if (!document.getElementById('loading')) return;
  clearTimeout(_ldWatch);
  _ldWatch = setTimeout(_ldTravado, LD_TRAVADO_MS);
}
function _ldTravado() {
  const card = document.querySelector('#loading .ld-card');
  if (!card || card.querySelector('.ld-saida')) return;
  const div = document.createElement('div');
  div.className = 'ld-saida';
  div.innerHTML = `<div class="ld-saida-msg">${escapar(t('Está demorando mais que o normal.'))}</div>
    <div class="ld-saida-btns">
      <button class="btn btn-primario focusable" data-acao="ld-retry">${escapar(t('Tentar de novo'))}</button>
      <button class="btn btn-secundario focusable" data-acao="ld-pular">${escapar(t('Continuar sem a lista'))}</button>
    </div>`;
  card.appendChild(div);
  // Prende o D-pad nestes dois botões (.nav-modal é só marcador de escopo do
  // SpatialNav, sem estilo) — senão o foco vaza pra sidebar atrás do loading.
  const ld = document.getElementById('loading');
  if (ld) { ld.classList.add('nav-modal'); ld._onVoltar = () => {}; }
  div.querySelector('[data-acao="ld-retry"]').addEventListener('click', () => { try { location.reload(); } catch (_) {} });
  div.querySelector('[data-acao="ld-pular"]').addEventListener('click', () => {
    _bootDesistiu = true;            // o carregamento que ficou pendurado não aplica nada
    esconderLoading();
    // No boot, entra com catálogo vazio (app neutro). Se o app JÁ está aberto
    // (ex.: "Recarregar" que travou), só dispensa o loading — não apaga o que
    // já estava carregado.
    if (!_appIniciado) { aplicarLista(_listaVazia()); abrirGatePerfis(entrarNoApp); }
    toast(t('Sua lista não carregou. Tente Recarregar em Configurações.'));
  });
  try { SpatialNav.setFocus(div.querySelector('[data-acao="ld-retry"]')); } catch (_) {}
}
let _bootDesistiu = false;

// Baixa + parseia a lista do dispositivo e aplica ao catálogo. O parse roda
// após um frame (a barra continua animando). Retorna true se carregou.
// ── Diagnóstico de memória/tamanho (painel em Configurações → Diagnóstico) ────
// `performance.memory` existe no Chromium (inclui o 68 da TV) e dá o LIMITE de
// heap do app — é ele que diz o orçamento real de RAM que temos.
const _diag = { bytesLista: 0, linhas: 0, msParse: 0, heapAntes: 0, heapPico: 0 };
const _heap = () => { try { return (performance.memory || {}).usedJSHeapSize || 0; } catch (_) { return 0; } };
const _heapLimite = () => { try { return (performance.memory || {}).jsHeapSizeLimit || 0; } catch (_) { return 0; } };
const _mb = (b) => (b ? (b / 1048576).toFixed(1) + ' MB' : '—');

// Download da lista com WATCHDOG. `fetch()` NÃO tem timeout: quando o servidor
// do provedor aceita a conexão e não manda byte nenhum (comum na TV, em rede
// ruim ou host fora do ar), a promise NUNCA resolve nem rejeita — o boot ficava
// preso em "Baixando sua lista…" e, como o webOS RESUME o app em vez de
// reiniciar, reabrir caía na mesma tela: só reinstalar destravava.
// XHR resolve os dois problemas: dá progresso REAL (bytes) e permite abortar
// quando o fluxo PARA de andar. Só abortamos por INATIVIDADE — download lento
// mas progredindo continua (uma lista de 46 MB leva minutos em Wi-Fi fraco).
const DL_PARADO_MS = 40000;        // 40s sem chegar 1 byte → desiste
const DL_TETO_MS = 15 * 60000;     // teto absoluto de segurança
function baixarTexto(url, onProgresso) {
  return new Promise((resolve, reject) => {
    let x;
    try { x = new XMLHttpRequest(); } catch (e) { return reject(e); }
    const inicio = Date.now();
    let ultimo = inicio, vigia = null, motivo = '';
    const parar = () => { clearInterval(vigia); vigia = null; };
    vigia = setInterval(() => {
      const parado = Date.now() - ultimo > DL_PARADO_MS;
      const estourou = Date.now() - inicio > DL_TETO_MS;
      if (!parado && !estourou) return;
      parar();
      // `motivo` antes do abort(): o abort dispara onabort, que rejeitaria com
      // 'abortado' e esconderia a causa real no log/diagnóstico.
      motivo = parado ? 'sem resposta do servidor' : 'tempo esgotado';
      try { x.abort(); } catch (_) {}
      reject(new Error(motivo));
    }, 2000);
    x.open('GET', url, true);
    x.onprogress = (e) => {
      ultimo = Date.now();
      if (onProgresso) onProgresso(e.lengthComputable && e.total ? e.loaded / e.total : -1, e.loaded);
    };
    x.onload = () => {
      parar();
      if (x.status >= 200 && x.status < 300) resolve(x.responseText || '');
      else reject(new Error('HTTP ' + x.status));
    };
    x.onerror = () => { parar(); reject(new Error('erro de rede')); };
    x.onabort = () => { parar(); reject(new Error(motivo || 'abortado')); };
    try { x.send(); } catch (e) { parar(); reject(e); }
  });
}

async function carregarLista(url, forcar) {
  if (!url) return false;
  _bootDesistiu = false;
  try {
    // 1) CACHE: catálogo já parseado (IndexedDB). Evita baixar 46 MB e gastar
    //    ~23s parseando de novo a cada boot. Só no 1º boot (ou quando a lista
    //    muda / "Recarregar") pagamos o custo.
    if (!forcar) {
      const cache = await CacheLista.ler(url, null);
      if (cache && !_bootDesistiu) {
        loadingMsg(t('Carregando catálogo salvo…'));
        await new Promise((r) => requestAnimationFrame(r));
        const _tc = Date.now();
        aplicarLista(Lista.montarCatalogo(cache));
        _diag.msParse = Date.now() - _tc;
        _diag.doCache = true;
        _diag.bytesLista = cache.tam || 0;
        return true;
      }
    }
    _diag.doCache = false;
    let _ultPint = 0;
    const txt = await baixarTexto(url, (frac, bytes) => {
      // Progresso do DOWNLOAD (a barra andando é o que prova que não travou).
      // Throttle: o onprogress dispara dezenas de vezes por segundo numa lista
      // de 46 MB e a TV não precisa repintar tudo isso.
      const agora = Date.now();
      if (agora - _ultPint < 250) return;
      _ultPint = agora;
      if (frac >= 0) loadingProgresso(frac * 100, t('Baixando sua lista…'));
      else loadingMsg(t('Baixando sua lista…') + ' ' + (bytes / 1048576).toFixed(1) + ' MB');
    });
    if (_bootDesistiu) return false;   // o usuário já saiu do loading
    loadingMsg(t('Organizando seus canais…'));
    await new Promise((r) => requestAnimationFrame(r)); // deixa a UI respirar
    _diag.bytesLista = txt.length;
    _diag.heapAntes = _heap();
    const _t0 = Date.now();
    // 2) Parse FATIADO com progresso real (não congela a tela).
    const parsed = await Lista.parse(txt, (frac) => loadingProgresso(frac * 100));
    _diag.msParse = Date.now() - _t0;
    _diag.heapPico = _heap();
    // Valida ANTES de gravar: um parse vazio (URL expirada devolvendo HTML de
    // erro, p. ex.) ia parar no cache e todo boot seguinte abria o app vazio
    // sem nem tentar baixar de novo.
    if (!parsed.canais.length && !parsed.filmes.length && !parsed.series.length) {
      throw new Error('lista vazia ou formato não reconhecido');
    }
    // Guarda pro próximo boot (best-effort — falha de IDB não quebra nada). O
    // clone de 167k objetos custa alguns segundos na TV, então avisamos.
    loadingMsg(t('Salvando catálogo para abrir rápido…'));
    await new Promise((r) => requestAnimationFrame(r));
    try { await CacheLista.gravar(url, txt.length, parsed); } catch (_) {}
    if (_bootDesistiu) return false;
    aplicarLista(parsed);
    return true;
  } catch (e) {
    console.warn('[Hero Play] falha ao carregar lista:', e);
    return false;
  }
}

// Metadados do TMDB (pôster/logo/sinopse) persistidos: sem isto o app re-pergunta
// o pôster de CADA título a cada boot — é o "a foto carrega de novo". Gravamos em
// intervalo (só quando há novidade) porque na TV o `beforeunload` não é confiável.
async function restaurarMetaTmdb() {
  try {
    const d = await CacheLista.lerMeta();
    if (d) TMDB.importarCache(d);
  } catch (_) { /* best-effort */ }
}
let _metaGravando = false;
async function salvarMetaTmdb() {
  if (_metaGravando || !TMDB.estaSujo()) return;
  _metaGravando = true;
  TMDB.limparSujo();   // antes de gravar: novidades durante a gravação re-sujam
  try { await CacheLista.gravarMeta(TMDB.exportarCache()); } catch (_) { /* best-effort */ }
  _metaGravando = false;
}
function ligarSalvamentoMeta() {
  setInterval(salvarMetaTmdb, 60000);
  // Melhor esforço ao sair/esconder (webOS manda o app pra background aqui).
  document.addEventListener('visibilitychange', () => { if (document.hidden) salvarMetaTmdb(); });
  window.addEventListener('beforeunload', salvarMetaTmdb);
}

// App foi para SEGUNDO PLANO (botão Home do controle): solta a conexão.
//
// O provedor de IPTV conta SESSÃO, não tela ligada: um preview que continua
// baixando em background ocupa uma "tela" enquanto o usuário nem está no app —
// e depois de algumas idas e voltas o servidor recusa com 403. O webOS e o
// Tizen mandam `visibilitychange` nessa hora (a própria doc da LG recomenda
// pausar mídia aqui).
function ligarLiberarEmBackground() {
  document.addEventListener('visibilitychange', () => {
    if (!document.hidden) return;
    try { pararPreview(); } catch (_) {}      // canal ao vivo: encerra de vez
    // VOD: guarda o ponto e pausa. (Pausado o socket pode seguir aberto — para
    // soltar de verdade seria preciso reabrir na volta; fica anotado.)
    try {
      const v = _videoVod;
      if (v && !v.paused) {
        if (_playerCtx && v.duration) Biblioteca.salvarProgresso(_playerCtx, v.currentTime, v.duration);
        v.pause();
      }
    } catch (_) {}
  });
}

async function iniciarApp() {
  document.getElementById('app').classList.remove('oculto');
  const reg = Dispositivo.registro();
  await restaurarMetaTmdb();
  ligarSalvamentoMeta();
  ligarLiberarEmBackground();
  if (reg && reg.lista_url) {
    mostrarLoading(t('Baixando sua lista…'));
    const ok = await carregarLista(reg.lista_url);
    // O usuário já saiu do loading pela saída de emergência (carregamento travado)
    // e o app já está aberto — não abrir o gate de perfis de novo por cima.
    if (_bootDesistiu) return;
    // TV: NÃO segura a tela pré-carregando banner — eles carregam lazy (observer)
    // e o hero carrega no 1º foco. Dispensa o loading assim que a lista é parseada.
    if (ok && !EH_TV) { loadingMsg(t('Preparando seus banners…')); await precarregarBanners(); precarregarLogosCanais(); }
    esconderLoading();
    if (!ok) toast(t('Não foi possível carregar sua lista. Verifique a URL/conexão.'));
  }
  // Gate de perfis ("Quem está assistindo?") → aplica o perfil e entra no app.
  abrirGatePerfis(entrarNoApp);
}

// Entra no app com o perfil selecionado (usado no boot, no botão de perfil e no config).
// A LISTA/catálogo é a mesma p/ todos os perfis — na TROCA de perfil NÃO
// reconstruímos o Início inteiro; só trocamos os trilhos do perfil (leve).
let _appIniciado = false;
function entrarNoApp() {
  const jaIniciado = _appIniciado;
  aplicarPerfilAtivo();                              // favoritos + idioma + sidebar
  if (jaIniciado) limparCacheSecoes();               // trilhos/Minha Lista mudam por perfil → invalida
  const main = document.getElementById('conteudo');
  const secaoAtiva = (document.querySelector('.nav-item.ativo') || {}).dataset;
  if (jaIniciado && secaoAtiva && secaoAtiva.secao === 'inicio' && main && main.querySelector('.trilhos')) {
    atualizarTrilhosPerfil(main);                    // atualiza a Início VISÍVEL sem rebuild
    _secCacheSet('inicio', main.firstElementChild);  // re-cacheia já com os trilhos do novo perfil
  } else {
    navegar('inicio');                               // 1ª entrada (ou vindo de outra seção)
  }
  _appIniciado = true;
  if (!jaIniciado && Dispositivo.status() === 'trial') mostrarAvisoTeste();
}

// Troca de perfil: recarrega a biblioteca do perfil (favoritos) e re-aplica o
// idioma dele; re-renderiza a sidebar + seção atual. Chamado ao selecionar perfil.
function aplicarPerfilAtivo() {
  recarregarFavoritos();
  try { document.documentElement.lang = idiomaAtual() === 'pt' ? 'pt-BR' : idiomaAtual(); } catch (_) {}
  montarSidebar();
}

// Botão VOLTAR do controle no webOS/Tizen: interceptar por keydown NÃO basta —
// a TV dispara o "voltar do histórico" e FECHA o app antes/independente do
// preventDefault. A forma confiável é prender no history: empilhamos um estado e,
// a cada `popstate` (Back), re-empilhamos e tratamos como "voltar". Assim a TV
// nunca sai sozinha; só saímos quando confirmarSairApp() chama window.close().
function ligarVoltarSistema() {
  try {
    history.pushState({ hp: 1 }, '');
    window.addEventListener('popstate', () => {
      history.pushState({ hp: 1 }, '');   // re-arma o histórico (não deixa esvaziar)
      try { SpatialNav.voltar(); } catch (_) {}
    });
  } catch (_) { /* sem history (dev): fica só o keydown do spatial-nav */ }
}

window.addEventListener('DOMContentLoaded', async () => {
  ligarVoltarSistema();
  montarSidebar();
  // Hero reage ao item em foco (Início/Filmes/Séries).
  SpatialNav.aoFocar((el) => {
    if (!el || !el.classList) return;
    // Lembra o último foco DE CADA camada: é o que permite voltar ao mesmo item
    // ao fechar o player/detalhe (ver focarTopo).
    try { const m = el.closest('.nav-modal'); if (m) m._ultimoFoco = el; } catch (_) {}
    // Campo de texto (onboarding / adicionar playlist): a moldura de destaque é
    // do WRAPPER (.ob-campo) e vinha do `:focus-within`, ou seja, do foco nativo
    // do <input> — que no TV Box deixou de existir de propósito. Marcamos o
    // wrapper na mão pra o campo continuar demarcado ao descer o foco nele.
    // Com o teclado aberto o foco está nas TECLAS: aí o campo que está sendo
    // preenchido continua demarcado (não se apaga o destaque dele).
    if (!document.querySelector('.tv-kb')) {
      document.querySelectorAll('.ob-campo.focado').forEach((c) => c.classList.remove('focado'));
      const campo = el.closest && el.closest('.ob-campo');
      if (campo) campo.classList.add('focado');
    }
    // Detalhe: subir do elenco/semelhantes de volta pros botões tem que trazer a
    // tela INTEIRA de volta ao topo (logo-título e sinopse completos). Isso era
    // feito só por `scroll-margin-top: 100vh` no CSS, que depende de
    // `scroll-margin` — WebView antigo de TV Box/webOS não tem, e aí a tela
    // ficava parada no meio. Aqui é explícito e não depende do motor.
    if (el.closest && el.closest('.det2-topo')) {
      // No frame seguinte: o SpatialNav dá um scrollIntoView('nearest') logo
      // depois deste callback, e ele rolaria só o mínimo, deixando a tela no meio.
      const sc = document.getElementById('det2-scroll');
      if (sc && sc.scrollTop > 0) requestAnimationFrame(() => sc.scrollTo({ top: 0, behavior: _rolagem() }));
    } else if (el.classList.contains('rec-poster') || el.classList.contains('ator')) {
      requestAnimationFrame(() => focarItemDetalhe(el));   // idem: depois do SpatialNav
    }
    if (el.classList.contains('poster')) {
      if (el.closest('.bsc-grid')) {
        el.scrollIntoView({ block: 'nearest', behavior: _rolagem() }); // grade da busca rola sozinha
      } else {
        focarPoster(el);                       // scroll (fila + título sob o hero)
        const fila = el.closest('.trilho-fila'); // lembra a posição neste carrossel
        if (fila) fila.dataset.ultimo = el.dataset.id;
        const it = LISTA.indice[el.dataset.id];
        if (it) atualizarHero(it);
      }
    } else if (el.classList.contains('trilho-titulo')) {
      // Mesmo scroll do pôster: o `scrollIntoView('nearest')` do SpatialNav
      // encostaria o título no topo do #conteudo — ou seja, DEBAIXO do hero
      // fixo. Aqui ele para logo abaixo dele.
      requestAnimationFrame(() => focarTrilho(el));
    } else if (el.classList.contains('cr-item')) {
      mostrarCredito(el);                    // créditos: painel reage ao foco
    } else if (el.classList.contains('ep-temp-item')) {
      if (_epCtrl) _epCtrl.selecionarTemporada(+el.dataset.s); // temporada abre ao focar
    } else if (el.classList.contains('cfg-item')) {
      mostrarConfigPane(el.dataset.pane);    // Config: painel reage ao item em foco
    } else if (el.classList.contains('jogos-data')) {
      selecionarDataJogos(el.dataset.iso, false);  // Jogos: troca a data ao focar a aba
    } else if (el.classList.contains('jogos-liga')) {
      mostrarJogosLiga(el.dataset.liga);           // Jogos: liga reage ao foco
    }
  });
  // Boot BLINDADO: se a consulta à nuvem falhar/pendurar, ou qualquer coisa
  // lançar, ainda assim mostramos uma tela (nunca fica em branco/cinza).
  try {
    await Dispositivo.init();      // resolve identidade ESTÁVEL (mac/key) ANTES de usar
  } catch (e) { console.error('[Hero Play] init()', e); }
  try {
    await Dispositivo.consultar(); // best-effort (offline-first, com timeout)
  } catch (e) { console.error('[Hero Play] consultar()', e); }
  try {
    // Ordem importa: VENCIDO manda em tudo. Com lista em cache o app abriria
    // normalmente e a assinatura não valeria nada.
    if (Dispositivo.expirado()) mostrarExpirado();
    else if (Dispositivo.temLista()) iniciarApp();
    else mostrarOnboarding(); // app neutro: abre vazio ate ter lista (conformidade)
  } catch (e) {
    console.error('[Hero Play] boot', e);
    try { mostrarOnboarding(); } catch (_) {
      document.body.innerHTML = '<div style="color:#fff;padding:60px;font:600 28px sans-serif">'
        + 'Erro ao iniciar: ' + String((e && e.message) || e) + '</div>';
    }
  }
});
