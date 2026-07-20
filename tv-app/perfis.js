/* ============================================================================
   Hero Play TV — Perfis (máx 3) + biblioteca por perfil, espelhando o mobile.
   Cada perfil tem sua BIBLIOTECA (favoritos, "continuar assistindo", tags de
   recomendação) e suas CONFIGURAÇÕES (idioma, qualidade, controle dos pais) —
   tudo namespaced por `Perfis.chave(base)` = base__<id>. Local (a TV não tem
   conta/PII; identidade é MAC+Key). Ver [[profiles_feature]] / perfil_provider.dart.
   Usa globais em runtime: TMDB, LISTA, escapar, iniciais, SpatialNav, t, toast,
   abrirTeclado, gradiente.
   ============================================================================ */
const Perfis = (() => {
  const LS = 'tv_perfis', LS_AT = 'tv_perfil_ativo', MAX = 3;
  const CORES = ['#E53935', '#4f8ef7', '#9b7bff', '#2fb67c', '#e8a33a', '#e05aa0'];
  let _lista = [], _ativo = null;
  try { _lista = JSON.parse(localStorage.getItem(LS) || '[]') || []; } catch (_) { _lista = []; }
  try { _ativo = localStorage.getItem(LS_AT) || null; } catch (_) { _ativo = null; }
  const _save = () => { try { localStorage.setItem(LS, JSON.stringify(_lista)); } catch (_) {} };

  const lista = () => _lista.slice();
  const ativoId = () => _ativo;
  const ativo = () => _lista.find((p) => p.id === _ativo) || null;
  function criar(nome, cor) {
    if (_lista.length >= MAX) return null;
    const id = 'p' + Date.now().toString(36) + Math.random().toString(36).slice(2, 5);
    const p = { id, nome: (nome || 'Perfil').trim().slice(0, 20) || 'Perfil', cor: cor || CORES[_lista.length % CORES.length] };
    _lista.push(p); _save(); return p;
  }
  function excluir(id) { _lista = _lista.filter((p) => p.id !== id); _save(); if (_ativo === id) { _ativo = null; localStorage.removeItem(LS_AT); } }
  function renomear(id, nome) { const p = _lista.find((x) => x.id === id); if (p) { p.nome = (nome || '').trim().slice(0, 20) || p.nome; _save(); } }
  function atualizar(id, campos) {
    const p = _lista.find((x) => x.id === id); if (!p) return;
    if (campos.nome != null) p.nome = (campos.nome || '').trim().slice(0, 20) || p.nome;
    if (campos.cor) p.cor = campos.cor;
    _save();
  }
  function selecionar(id) { if (_lista.some((p) => p.id === id)) { _ativo = id; try { localStorage.setItem(LS_AT, id); } catch (_) {} } }
  const chave = (base) => base + '__' + (_ativo || 'default');
  return { lista, ativo, ativoId, criar, excluir, renomear, atualizar, selecionar, chave, CORES, MAX };
})();

// ── Biblioteca por perfil ────────────────────────────────────────────────────
const Biblioteca = (() => {
  const _get = (base, def) => { try { const v = JSON.parse(localStorage.getItem(Perfis.chave(base)) || 'null'); return v == null ? def : v; } catch (_) { return def; } };
  const _set = (base, val) => { try { localStorage.setItem(Perfis.chave(base), JSON.stringify(val)); } catch (_) {} };
  const _norm = (s) => (s || '').normalize('NFD').replace(/[̀-ͯ]/g, '').toLowerCase().trim();

  // Favoritos (Set de ids de canal)
  const favoritos = () => new Set(_get('tv_favoritos', []));
  const salvarFavoritos = (set) => _set('tv_favoritos', [...set]);

  // Minha Lista (filmes/séries, separada por tipo): id -> { id, tipo, titulo, ts }.
  const _ml = () => _get('tv_minha_lista', {});
  const naLista = (id) => !!_ml()[id];
  function alternarLista(item) {
    if (!item || !item.id) return false;
    const m = _ml();
    if (m[item.id]) { delete m[item.id]; _set('tv_minha_lista', m); return false; }
    m[item.id] = { id: item.id, tipo: item.tipo, titulo: item.titulo, ts: Date.now() };
    _set('tv_minha_lista', m); return true;
  }
  // Itens da lista de um tipo ('filme'/'serie'), mais recentes primeiro.
  const minhaLista = (tipo) => Object.values(_ml())
    .filter((x) => !tipo || x.tipo === tipo).sort((a, b) => b.ts - a.ts);

  // Continuar assistindo: id -> { id, tipo, titulo, logo, url, pos, dur, ts, ep }
  const _prog = () => _get('tv_progresso', {});
  function salvarProgresso(ctx, pos, dur) {
    if (!ctx || !ctx.id || !dur || pos < 15) return;
    if (pos / dur > 0.92) { concluir(ctx); return; }         // terminou → conclui + aprende
    const m = _prog();
    m[ctx.id] = { id: ctx.id, tipo: ctx.tipo, titulo: ctx.titulo, logo: ctx.logo || '', url: ctx.url, pos, dur, ts: Date.now(), ep: ctx.ep || '' };
    _set('tv_progresso', m);
  }
  const progressoDe = (id) => _prog()[id] || null;
  function removerProgresso(id) { const m = _prog(); if (m[id]) { delete m[id]; _set('tv_progresso', m); } }
  const continuarAssistindo = () => Object.values(_prog()).sort((a, b) => b.ts - a.ts);
  function concluir(ctx) { if (ctx && ctx.id) removerProgresso(ctx.id); aprender(ctx); }

  // Recomendação: pesos por gênero do TMDB (id) do que o perfil assistiu.
  const recTags = () => _get('tv_rec_tags', {});
  async function aprender(ctx) {
    if (!ctx) return;
    let ids = ctx.generoIds;
    if (!ids) { try { const inf = await TMDB.info(ctx.titulo, ctx.tipo === 'serie'); ids = (inf && inf.genero_ids) || []; } catch (_) { ids = []; } }
    const w = recTags();
    const chaves = (ids && ids.length) ? ids.map(String) : (ctx.generos || []).map((g) => 'n:' + _norm(g));
    for (const k of chaves) w[k] = (w[k] || 0) + 1;
    _set('tv_rec_tags', w);
  }
  // Recomenda do catálogo local por afinidade de gênero (TMDB do cache; senão nome).
  function _tagsDoItem(it) {
    const inf = TMDB.infoCache(it.titulo, it.tipo === 'serie');
    if (inf && inf.genero_ids && inf.genero_ids.length) return inf.genero_ids.map(String);
    return (it.generos || []).map((g) => 'n:' + _norm(g));
  }
  function recomendacoes(n) {
    const w = recTags(); if (!Object.keys(w).length) return [];
    const prog = _prog();
    const cand = [...(LISTA.filmes || []), ...(LISTA.series || [])];
    return cand.filter((it) => !prog[it.id])
      .map((it) => ({ it, s: _tagsDoItem(it).reduce((acc, k) => acc + (w[k] || 0), 0) }))
      .filter((x) => x.s > 0)
      .sort((a, b) => b.s - a.s).slice(0, n || 18).map((x) => x.it);
  }
  return { favoritos, salvarFavoritos, naLista, alternarLista, minhaLista, salvarProgresso, progressoDe, removerProgresso, continuarAssistindo, concluir, aprender, recTags, recomendacoes };
})();

// ── Avatar / gate "Quem está assistindo?" ───────────────────────────────────
const _avBg = (p) => `linear-gradient(150deg, ${p.cor}, rgba(0,0,0,.4))`;
const _inicialPerfil = (nome) => (iniciais(nome) || (nome || 'P')[0] || 'P').toUpperCase();

// Gate: se não houver perfil, cria "Perfil 1". Ao escolher, seleciona e chama cb.
function abrirGatePerfis(cb) {
  if (!Perfis.lista().length) { const p = Perfis.criar('Perfil 1'); if (p) Perfis.selecionar(p.id); }
  const ov = document.createElement('div');
  ov.className = 'nav-modal perfis-gate';
  document.body.appendChild(ov);
  ov._onVoltar = () => {};   // gate é a raiz — sem "voltar"
  const render = () => {
    const perfis = Perfis.lista();
    const tiles = perfis.map((p) => `
      <button class="perfil-tile focusable" data-id="${p.id}">
        <span class="perfil-av" style="background:${_avBg(p)}">${escapar(_inicialPerfil(p.nome))}</span>
        <span class="perfil-nome">${escapar(p.nome)}</span>
      </button>`).join('');
    const add = perfis.length < Perfis.MAX ? `
      <button class="perfil-tile perfil-add focusable" data-add="1">
        <span class="perfil-av perfil-av-add">+</span>
        <span class="perfil-nome">${escapar(t('Adicionar perfil'))}</span>
      </button>` : '';
    ov.innerHTML = `<div class="perfis-wrap">
      <div class="logo perfis-logo"><img class="logo-mark" src="heroplay-icon.svg" alt="Hero Play"></div>
      <h1 class="perfis-titulo">${escapar(t('Quem está assistindo?'))}</h1>
      <div class="perfis-grade">${tiles}${add}</div>
      ${perfis.length ? `<button class="perfil-gerenciar focusable" data-ger="1">${escapar(t('Gerenciar perfis'))}</button>` : ''}
    </div>`;
    ov.querySelectorAll('.perfil-tile[data-id]').forEach((b) => b.addEventListener('click', () => {
      const perfil = Perfis.lista().find((p) => p.id === b.dataset.id);
      Perfis.selecionar(b.dataset.id);
      animarEntradaPerfil(perfil, b, ov, cb);   // ícone → centro (loading) → canto do sidebar
    }));
    const addBtn = ov.querySelector('[data-add]'); if (addBtn) addBtn.addEventListener('click', () => _formPerfil(null, () => render()));
    const ger = ov.querySelector('[data-ger]'); if (ger) ger.addEventListener('click', () => _gerenciarPerfis(render));
    const f = ov.querySelector('.perfil-tile'); if (f) SpatialNav.setFocus(f);
  };
  render();
}

// Animação de entrada (igual ao mobile): o avatar do perfil vai ao CENTRO com um
// spinner (loading), depois "voa" para o indicador no canto do sidebar (abaixo da
// logo Hero Play). O app é renderizado atrás; o indicador aparece ao pousar.
// Bloqueia o D-pad/Enter DURANTE a animação (senão o foco fica no app/gate atrás
// do overlay preto e a tecla abre o item focado / navega o gate invisível).
let _inputTravado = null;
function _travarInput() {
  if (_inputTravado) return;
  _inputTravado = (e) => { e.stopImmediatePropagation(); e.preventDefault(); };
  window.addEventListener('keydown', _inputTravado, true);
}
function _destravarInput() {
  if (_inputTravado) { window.removeEventListener('keydown', _inputTravado, true); _inputTravado = null; }
}

// O avatar flutuante tem caixa FIXA de 150px (a fonte cabe); posição/tamanho vêm
// só do transform (translate + scale) — assim escala suave e sem cortar.
const _FLY_BASE = 150;
function _flyTransform(rect) {
  const cx = window.innerWidth / 2, cy = window.innerHeight / 2;
  const rcx = rect.left + rect.width / 2, rcy = rect.top + rect.height / 2;
  return `translate(${(rcx - cx).toFixed(1)}px, ${(rcy - cy).toFixed(1)}px) scale(${(rect.width / _FLY_BASE).toFixed(3)})`;
}
function _criarFly(perfil, rectInicial) {
  const fly = document.createElement('div');
  fly.className = 'perfil-fly';
  fly.style.background = _avBg(perfil);
  fly.innerHTML = `<span class="perfil-fly-ini">${escapar(_inicialPerfil(perfil.nome))}</span>`;
  fly.style.transition = 'none';
  fly.style.transform = _flyTransform(rectInicial);   // posição inicial SEM transição
  return fly;
}

function animarEntradaPerfil(perfil, tileEl, gateOv, cb) {
  _travarInput();                                     // trava D-pad/Enter até a tela aparecer
  const av = tileEl && tileEl.querySelector('.perfil-av');
  const rTile = av ? av.getBoundingClientRect() : { left: innerWidth / 2 - 75, top: innerHeight / 2 - 75, width: 150, height: 150 };
  const bg = document.createElement('div');
  bg.className = 'perfil-anim';                        // preto opaco (esconde o app até o fim)
  const spin = document.createElement('div'); spin.className = 'perfil-anim-spin';
  const fly = _criarFly(perfil, rTile);
  bg.appendChild(fly); bg.appendChild(spin);
  document.body.appendChild(bg);
  fly.getBoundingClientRect(); fly.style.transition = '';   // habilita a transição do CSS
  if (gateOv && gateOv.parentNode) gateOv.remove();
  try { if (cb) cb(); } catch (e) { console.warn('[perfil] entrar', e); }   // renderiza o app atrás
  const ind = document.getElementById('nav-perfil'); if (ind) ind.style.opacity = '0';

  // Revelação GARANTIDA: seja qual for o caminho (transitionend, estágio 2 ou o
  // timer-mestre), a tela aparece e o input é liberado UMA vez só.
  let feito = false;
  const revelar = () => {
    if (feito) return; feito = true;
    if (ind) ind.style.opacity = '';
    bg.classList.add('revelar');
    _destravarInput();
    setTimeout(() => { if (bg.parentNode) bg.remove(); }, 550);
  };
  setTimeout(revelar, 2600);                           // timer-mestre (à prova de falha)

  requestAnimationFrame(() => {                         // estágio 1: → CENTRO (loading)
    fly.style.transform = 'translate(0px,0px) scale(1.25)';
    setTimeout(() => { spin.classList.add('on'); }, 260);
  });
  setTimeout(() => {                                    // estágio 2: → CANTO (sidebar)
    try {
      spin.classList.remove('on');
      const mini = document.querySelector('#nav-perfil .perfil-av-mini');
      const rMini = mini ? mini.getBoundingClientRect() : { left: 34, top: 96, width: 46, height: 46 };
      fly.style.transform = _flyTransform(rMini);
      fly.addEventListener('transitionend', revelar, { once: true });
      setTimeout(revelar, 850);
    } catch (e) { console.warn('[perfil] estágio2', e); revelar(); }
  }, 1500);
}

// Trocar de perfil (reverso da entrada): escurece a tela, o ícone volta do canto
// da sidebar para o seu lugar na tela de perfis, e o gate aparece com fade-in.
function trocarPerfilAnimado() {
  const pf = Perfis.ativo(); if (!pf) { abrirGatePerfis(entrarNoApp); return; }
  _travarInput();                                     // trava D-pad/Enter até o gate aparecer
  const mini = document.querySelector('#nav-perfil .perfil-av-mini');
  const rMini = mini ? mini.getBoundingClientRect() : { left: 34, top: 96, width: 46, height: 46 };
  // Overlay que ESCURECE (transparente → preto) sobre o app.
  const bg = document.createElement('div');
  bg.className = 'perfil-anim escurece';
  const fly = _criarFly(pf, rMini);                    // começa na sidebar (pequeno)
  bg.appendChild(fly);
  document.body.appendChild(bg);
  fly.getBoundingClientRect(); fly.style.transition = '';
  requestAnimationFrame(() => bg.classList.add('preto'));   // escurece

  // Revelação GARANTIDA (mesma lógica da entrada): some o preto e libera o input
  // uma vez só, seja pelo transitionend, pela etapa ou pelo timer-mestre.
  let feito = false, tileAvRef = null;
  const fim = () => {
    if (feito) return; feito = true;
    if (tileAvRef) tileAvRef.style.visibility = '';    // avatar do tile idêntico ao fly, no mesmo lugar
    bg.classList.remove('preto');                      // preto (com o fly dentro) faz fade-out
    _destravarInput();
    setTimeout(() => { if (bg.parentNode) bg.remove(); }, 400);
  };
  setTimeout(fim, 2600);                               // timer-mestre (à prova de falha)

  setTimeout(() => {                                   // já 100% preto → renderiza o gate ATRÁS
    // O gate (z 600, fundo opaco) fica ESCONDIDO atrás do preto (z 700). A revelação
    // é feita sumindo o PRETO: atrás dele só há o gate (cobre os filmes) — sem flash.
    try {
      abrirGatePerfis(entrarNoApp);
      const gate = document.querySelector('.perfis-gate');
      if (!gate) { fim(); return; }
      tileAvRef = gate.querySelector(`.perfil-tile[data-id="${pf.id}"] .perfil-av`) || gate.querySelector('.perfil-av');
      const rTile = tileAvRef ? tileAvRef.getBoundingClientRect() : { left: innerWidth / 2 - 75, top: innerHeight / 2 - 75, width: 150, height: 150 };
      if (tileAvRef) tileAvRef.style.visibility = 'hidden';   // o fly faz o papel do avatar até pousar
      requestAnimationFrame(() => { fly.style.transform = _flyTransform(rTile); });   // cresce GRADUAL até o tile
      fly.addEventListener('transitionend', fim, { once: true });
      setTimeout(fim, 850);
    } catch (e) { console.warn('[perfil] trocar', e); fim(); }
  }, 400);
}

// Form de criar/editar perfil (nome + cor). onDone re-renderiza o gate.
function _formPerfil(perfil, onDone) {
  const ov = document.createElement('div');
  ov.className = 'nav-modal perfil-form';
  const editar = !!perfil;
  const corSel = perfil ? perfil.cor : Perfis.CORES[Perfis.lista().length % Perfis.CORES.length];
  ov.innerHTML = `<div class="perfil-form-card">
    <div class="perfil-form-tit">${escapar(editar ? t('Editar perfil') : t('Novo perfil'))}</div>
    <input class="perfil-form-input focusable" id="pf-nome" placeholder="${escapar(t('Nome do perfil'))}" maxlength="20" autocomplete="off" spellcheck="false" value="${escapar(perfil ? perfil.nome : '')}">
    <div class="perfil-form-cores">${Perfis.CORES.map((c) => `<button class="pf-cor focusable${c === corSel ? ' sel' : ''}" data-cor="${c}" style="background:${c}"></button>`).join('')}</div>
    <div class="perfil-form-acoes">
      ${editar ? `<button class="btn btn-secundario focusable pf-del" id="pf-del">${escapar(t('Excluir'))}</button>` : ''}
      <button class="btn btn-primario focusable" id="pf-ok">${escapar(editar ? t('Salvar') : t('Criar'))}</button>
    </div>
  </div>`;
  document.body.appendChild(ov);
  const anterior = SpatialNav.atual;
  const fechar = () => { ov.remove(); if (anterior && document.contains(anterior)) SpatialNav.setFocus(anterior); };
  ov._onVoltar = fechar;
  let cor = corSel;
  ov.querySelectorAll('.pf-cor').forEach((b) => b.addEventListener('click', () => { cor = b.dataset.cor; ov.querySelectorAll('.pf-cor').forEach((x) => x.classList.toggle('sel', x === b)); }));
  ov.querySelector('#pf-nome').addEventListener('click', function () { abrirTeclado(this); });
  ov.querySelector('#pf-ok').addEventListener('click', () => {
    const nome = (ov.querySelector('#pf-nome').value || '').trim();
    if (editar) { Perfis.atualizar(perfil.id, { nome, cor }); }
    else { Perfis.criar(nome, cor); }
    fechar(); if (onDone) onDone();
  });
  const del = ov.querySelector('#pf-del'); if (del) del.addEventListener('click', () => { Perfis.excluir(perfil.id); fechar(); if (onDone) onDone(); });
  SpatialNav.setFocus(ov.querySelector('#pf-nome'));
}

// Gerenciar: lista os perfis p/ editar/excluir. onDone re-renderiza o gate.
function _gerenciarPerfis(onDone) {
  const ov = document.createElement('div');
  ov.className = 'nav-modal perfil-form';
  const perfis = Perfis.lista();
  ov.innerHTML = `<div class="perfil-form-card">
    <div class="perfil-form-tit">${escapar(t('Gerenciar perfis'))}</div>
    <div class="perfil-ger-lista">${perfis.map((p) => `
      <button class="perfil-ger-item focusable" data-id="${p.id}">
        <span class="perfil-av perfil-av-sm" style="background:${_avBg(p)}">${escapar(_inicialPerfil(p.nome))}</span>
        <span class="perfil-nome">${escapar(p.nome)}</span>
      </button>`).join('')}</div>
    <button class="btn btn-secundario focusable" id="pg-fechar">${escapar(t('Fechar'))}</button>
  </div>`;
  document.body.appendChild(ov);
  const fechar = () => { ov.remove(); if (onDone) onDone(); };
  ov._onVoltar = fechar;
  ov.querySelectorAll('.perfil-ger-item').forEach((b) => b.addEventListener('click', () => { const p = Perfis.lista().find((x) => x.id === b.dataset.id); ov.remove(); _formPerfil(p, onDone); }));
  ov.querySelector('#pg-fechar').addEventListener('click', fechar);
  SpatialNav.setFocus(ov.querySelector('.perfil-ger-item') || ov.querySelector('#pg-fechar'));
}

// Contexto de progresso p/ o player (movie ou episódio de série).
function ctxProgresso(item, url, ep) {
  return { id: item.id, tipo: item.tipo, titulo: item.titulo, logo: item.logo || '', url: url || item.url, generos: item.generos || [], ep: ep || '' };
}
