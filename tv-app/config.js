/* ============================================================================
   Hero Play TV — Configurações (estilo GTV).
   Coluna de menu agrupada (Interface/Privacidade/Dados/Conta/Jogos/Clima/Info)
   + painel de detalhe à direita que reage ao item EM FOCO (como o GTV).
   Navegação por D-pad: a coluna de menu é uma "área" isolada (spatial-nav.js) —
   ↑/↓ anda no menu; → entra no painel; ← volta ao menu; ←← volta à sidebar.
   Depende de globais do app.js/device.js (LISTA, Dispositivo, TMDB, toast,
   navegar, SpatialNav, gerarQr, categorias, escapar, iniciais, IC_*).
   ============================================================================ */

// ⚠️ NÃO editar à mão. Os empacotadores (build-ipk.sh / build-apk-tv.sh) trocam
// esta linha pela versão do `appinfo.json` na cópia que vai pro pacote — antes
// isto era um `'1.0.0-beta'` fixo que nunca mudou em release nenhuma, e por isso
// não havia como saber, olhando a TV, se o app estava atualizado. O valor aqui é
// só o do fonte/web (dev).
const APP_VERSAO = '0.4.9-dev';

// ── Ícones (pequenos, stroke) ───────────────────────────────────────────────
const CFG_ICO = {
  idioma: '<path d="M4 5h7M9 3v2c0 4-2 7-5 8"/><path d="M5 9c0 3 3 5 6 6"/><path d="m13 20 4-9 4 9M15 17h4"/>',
  lock: '<rect x="4" y="10" width="16" height="11" rx="2"/><path d="M8 10V7a4 4 0 0 1 8 0v3"/>',
  db: '<ellipse cx="12" cy="6" rx="8" ry="3"/><path d="M4 6v6c0 1.7 3.6 3 8 3s8-1.3 8-3V6"/><path d="M4 12v6c0 1.7 3.6 3 8 3s8-1.3 8-3v-6"/>',
  user: '<circle cx="12" cy="8" r="4"/><path d="M4 21c0-4 4-6 8-6s8 2 8 6"/>',
  bell: '<path d="M18 8a6 6 0 0 0-12 0c0 7-3 9-3 9h18s-3-2-3-9"/><path d="M13.7 21a2 2 0 0 1-3.4 0"/>',
  info: '<circle cx="12" cy="12" r="9"/><path d="M12 16v-4M12 8h.01"/>',
  tv: '<rect x="2" y="7" width="20" height="13" rx="2"/><path d="m8 3 4 4 4-4"/>',
};
const cfgSvg = (k) => `<svg class="cfg-item-ico" viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="1.7" stroke-linecap="round" stroke-linejoin="round">${CFG_ICO[k]}</svg>`;

// ── Estrutura do menu (grupos + itens) ──────────────────────────────────────
const CFG_MENU = [
  { grupo: 'Perfil', itens: [{ id: 'perfil', rot: 'Perfis', ico: 'user' }] },
  { grupo: 'Interface',  itens: [{ id: 'idioma', rot: 'Idioma da interface', ico: 'idioma' }] },
  { grupo: 'TV ao vivo', itens: [{ id: 'qualidade', rot: 'Qualidade dos canais', ico: 'tv' }] },
  { grupo: 'Privacidade', itens: [{ id: 'parental', rot: 'Controle dos pais', ico: 'lock' }] },
  { grupo: 'Dados', itens: [
    { id: 'cache', rot: 'Limpar cache', ico: 'db' },
    { id: 'historico', rot: 'Limpar histórico', ico: 'db' },
  ] },
  { grupo: 'Conta', itens: [
    { id: 'playlist', rot: 'Playlist ativa', ico: 'user' },
    { id: 'info', rot: 'Minhas Informações', ico: 'user' },
  ] },
  { grupo: 'Jogos', itens: [{ id: 'alertas', rot: 'Gerenciar alertas', ico: 'bell' }] },
  { grupo: 'Clima', itens: [{ id: 'clima', rot: 'Clima & Horário', ico: 'info' }] },
  { grupo: 'Info', itens: [
    { id: 'sobre', rot: 'Sobre / Versão', ico: 'info' },
    { id: 'termos', rot: 'Termos de uso', ico: 'info' },
    { id: 'velocidade', rot: 'Testar velocidade de conexão', ico: 'info' },
    { id: 'diag', rot: 'Diagnóstico (memória)', ico: 'info' },
  ] },
];

let _cfgPaneAtual = null;

function renderConfig() {
  _cfgPaneAtual = null;
  const menu = CFG_MENU.map((g) => `
    <div class="cfg-grupo">${t(g.grupo).toUpperCase()}</div>
    ${g.itens.map((it) => `
      <button class="cfg-item focusable" data-pane="${it.id}">
        ${cfgSvg(it.ico)}<span class="cfg-item-rot">${escapar(t(it.rot))}</span>
      </button>`).join('')}
  `).join('');
  return `<div class="cfg">
    <div class="cfg-menu" id="cfg-menu">
      <h2 class="cfg-titulo">${escapar(t('Configurações'))}</h2>
      ${menu}
    </div>
    <div class="cfg-pane" id="cfg-pane"></div>
  </div>`;
}

// Chamado pelo callback de foco (app.js): ao focar um item do menu, mostra o
// painel correspondente. Não re-renderiza se já é o painel atual (evita perder
// dados ao ir menu↔painel — ex.: clima já carregado).
function mostrarConfigPane(id) {
  if (id === _cfgPaneAtual) return;
  _cfgPaneAtual = id;
  document.querySelectorAll('.cfg-item').forEach((b) =>
    b.classList.toggle('ativo', b.dataset.pane === id));
  const pane = document.getElementById('cfg-pane');
  if (!pane) return;
  const fn = CFG_PANES[id];
  if (fn) fn(pane);
}

// Volta o foco ao item de seção SELECIONADO (menu) SEM re-renderizar o painel —
// o guard de `mostrarConfigPane` (id === _cfgPaneAtual) mantém o conteúdo como
// estava (ex.: resultado do teste de velocidade, agulha no lugar, clima carregado).
// Usado pela navegação (esquerda / botão Voltar).
function configVoltarSelecao() {
  const it = document.querySelector('.cfg-item.ativo') || document.querySelector('.cfg-item');
  if (!it) return false;
  SpatialNav.setFocus(it);
  return true;
}

// ── Blocos reutilizáveis ────────────────────────────────────────────────────
function cfgCabecalho(titulo, sub) {
  return `<div class="cfg-cab"><h1 class="cfg-h1">${escapar(titulo)}</h1>${sub ? `<p class="cfg-desc">${escapar(sub)}</p>` : ''}</div>`;
}
// Painel "central" com ícone + botão (usado em cache/histórico/playlist/termos/velocidade).
function cfgCentro(iconHTML, botaoHTML, hint) {
  return `<div class="cfg-centro">
    <div class="cfg-centro-ico">${iconHTML}</div>
    ${botaoHTML}
    ${hint ? `<div class="cfg-centro-hint">${escapar(hint)}</div>` : ''}
  </div>`;
}

const IC_DB_BIG = '<svg viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="1.4" stroke-linecap="round" stroke-linejoin="round"><ellipse cx="10" cy="6" rx="8" ry="3"/><path d="M2 6v6c0 1.7 3.6 3 8 3"/><path d="M2 12v6c0 1.7 3.6 3 8 3"/><circle cx="18" cy="17" r="4.5"/><path d="M18 15v2l1.4 1"/></svg>';
const IC_DOC_BIG = '<svg viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="1.4" stroke-linecap="round" stroke-linejoin="round"><path d="M14 3H7a2 2 0 0 0-2 2v14a2 2 0 0 0 2 2h10a2 2 0 0 0 2-2V8z"/><path d="M14 3v5h5M8 13h6M8 17h4"/></svg>';
const IC_HIST_BIG = '<svg viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="1.4" stroke-linecap="round" stroke-linejoin="round"><path d="M3 12a9 9 0 1 0 3-6.7L3 8"/><path d="M3 3v5h5"/><path d="M12 7v5l3 2"/></svg>';
const IC_PL_BIG = '<svg viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="1.5" stroke-linecap="round" stroke-linejoin="round"><path d="M3 6h13M3 12h13M3 18h9"/><path d="m18 12 4 3-4 3z"/></svg>';
const IC_BELL_BIG = '<svg viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="1.4" stroke-linecap="round" stroke-linejoin="round"><path d="M18 8a6 6 0 0 0-12 0c0 7-3 9-3 9h18s-3-2-3-9"/><path d="M13.7 21a2 2 0 0 1-3.4 0"/></svg>';
const IC_CHECK = '<svg viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="2.4" stroke-linecap="round" stroke-linejoin="round"><path d="M20 6 9 17l-5-5"/></svg>';

// ═══════════════════════════════════════════════════════════════════════════
//  INTERFACE — Idioma
// ═══════════════════════════════════════════════════════════════════════════
const IDIOMAS = [
  { id: 'pt', flag: '🇧🇷', nome: 'Português (BR)' },
  { id: 'en', flag: '🇺🇸', nome: 'English' },
  { id: 'es', flag: '🇪🇸', nome: 'Español' },
];
// ═══════════════════════════════════════════════════════════════════════════
//  PERFIL — perfil ativo, trocar e gerenciar (perfis.js)
// ═══════════════════════════════════════════════════════════════════════════
function panePerfil(pane) {
  const p = Perfis.ativo();
  const av = p ? `linear-gradient(150deg, ${p.cor}, rgba(0,0,0,.4))` : '#333';
  pane.innerHTML = cfgCabecalho(t('Perfis'), t('Perfil ativo e gerenciamento.')) + `
    <div class="cfg-perfil-atual">
      <span class="perfil-av perfil-av-sm" style="background:${av}">${escapar(p ? (iniciais(p.nome) || 'P') : 'P')}</span>
      <span class="cfg-perfil-nome">${escapar(p ? p.nome : '—')}</span>
    </div>
    <div class="cfg-perfil-acoes">
      <button class="btn btn-primario focusable" id="cfg-trocar-perfil">${escapar(t('Trocar perfil'))}</button>
      <button class="btn btn-secundario focusable" id="cfg-gerenciar-perfil">${escapar(t('Gerenciar perfis'))}</button>
    </div>`;
  pane.querySelector('#cfg-trocar-perfil').addEventListener('click', () => trocarPerfilAnimado());
  pane.querySelector('#cfg-gerenciar-perfil').addEventListener('click', () => _gerenciarPerfis(() => panePerfil(pane)));
}

// idiomaAtual() vem do i18n.js.
function paneIdioma(pane) {
  const at = idiomaAtual();
  pane.innerHTML = cfgCabecalho(t('Idioma da interface')) + `
    <div class="cfg-opcoes">
      ${IDIOMAS.map((l) => `
        <button class="cfg-opcao focusable${l.id === at ? ' sel' : ''}" data-id="${l.id}">
          <span class="cfg-opcao-flag">${l.flag}</span>
          <span class="cfg-opcao-nome">${escapar(l.nome)}</span>
          <span class="cfg-opcao-check">${l.id === at ? IC_CHECK : ''}</span>
        </button>`).join('')}
    </div>`;
  pane.querySelectorAll('.cfg-opcao').forEach((b) => b.addEventListener('click', () => {
    const nome = (IDIOMAS.find((l) => l.id === b.dataset.id) || {}).nome || '';
    definirIdioma(b.dataset.id);            // persiste + re-renderiza tudo (sidebar + seção)
    toast(t('Idioma:') + ' ' + nome);
    // Volta o foco para o item "Idioma" do menu (a seção foi re-renderizada).
    const it = document.querySelector('.cfg-item[data-pane="idioma"]'); if (it) SpatialNav.setFocus(it);
  }));
}

// ═══════════════════════════════════════════════════════════════════════════
//  TV AO VIVO — Qualidade dos canais (auto-troca + qualidade padrão)
// ═══════════════════════════════════════════════════════════════════════════
const OPCOES_Q = [
  { id: 'max', nome: 'Máxima' }, { id: 'fhd', nome: 'FHD' }, { id: 'hd', nome: 'HD' }, { id: 'min', nome: 'Mínima' },
];
function paneQualidade(pane) {
  const auto = localStorage.getItem(Perfis.chave('tv_auto_qualidade')) !== '0';  // default ON
  const padrao = localStorage.getItem(Perfis.chave('tv_qualidade_padrao')) || 'max';
  pane.innerHTML = cfgCabecalho(t('Qualidade dos canais'), t('Ajustes de reprodução dos canais ao vivo.')) + `
    <div class="cfg-toggle-linha">
      <button class="cfg-toggle focusable${auto ? ' on' : ''}" id="cfg-q-auto">
        <span class="cfg-toggle-rot">${escapar(t('Troca automática de qualidade'))}</span>
        <span class="cfg-toggle-est">${auto ? t('ATIVADO') : t('DESATIVADO')}</span>
      </button>
    </div>
    <p class="cfg-desc">${escapar(t('Se o canal ficar travando, baixa a qualidade automaticamente. Se o canal cair, troca para outra fonte.'))}</p>
    <div class="cfg-sub-titulo">${escapar(t('Qualidade padrão'))}</div>
    <p class="cfg-desc" style="margin:-6px 0 14px">${escapar(t('Qualidade com prioridade ao abrir um canal.'))}</p>
    <div class="cfg-opcoes">
      ${OPCOES_Q.map((o) => `<button class="cfg-opcao focusable${o.id === padrao ? ' sel' : ''}" data-id="${o.id}">
        <span class="cfg-opcao-nome">${escapar(t(o.nome))}</span>
        <span class="cfg-opcao-check">${o.id === padrao ? IC_CHECK : ''}</span>
      </button>`).join('')}
    </div>`;
  pane.querySelector('#cfg-q-auto').addEventListener('click', () => {
    const novo = localStorage.getItem(Perfis.chave('tv_auto_qualidade')) !== '0' ? '0' : '1';
    localStorage.setItem(Perfis.chave('tv_auto_qualidade'), novo);
    toast(novo === '1' ? t('Troca automática ativada') : t('Troca automática desativada'));
    paneQualidade(pane); const a = pane.querySelector('#cfg-q-auto'); if (a) SpatialNav.setFocus(a);
  });
  pane.querySelectorAll('.cfg-opcao').forEach((b) => b.addEventListener('click', () => {
    localStorage.setItem(Perfis.chave('tv_qualidade_padrao'), b.dataset.id);
    toast(t('Qualidade padrão') + ': ' + t((OPCOES_Q.find((o) => o.id === b.dataset.id) || {}).nome || ''));
    paneQualidade(pane); const s = pane.querySelector('.cfg-opcao.sel'); if (s) SpatialNav.setFocus(s);
  }));
}

// ═══════════════════════════════════════════════════════════════════════════
//  PRIVACIDADE — Controle dos pais (toggle + PIN + bloqueio por categoria)
// ═══════════════════════════════════════════════════════════════════════════
function lerParental() {
  try { return Object.assign({ on: false, pin: '', canais: [], filmes: [], series: [] }, JSON.parse(localStorage.getItem(Perfis.chave('tv_parental')) || '{}')); }
  catch (_) { return { on: false, pin: '', canais: [], filmes: [], series: [] }; }
}
function salvarParental(p) { try { localStorage.setItem(Perfis.chave('tv_parental'), JSON.stringify(p)); } catch (_) {} }

// Categorias reais da lista, por tipo (canais = categorias dos canais;
// filmes/séries = títulos dos trilhos do catálogo).
function catsDoTipo(tipo) {
  if (tipo === 'canais') return (typeof categorias === 'function') ? categorias() : [];
  const cat = LISTA.catalogo && LISTA.catalogo[tipo];
  return (cat && cat.trilhos) ? cat.trilhos.map((t) => t.titulo) : [];
}

function paneParental(pane) {
  const p = lerParental();
  const linhaTipo = (tipo, rot) => {
    const n = (p[tipo] || []).length;
    const txt = n ? t(n > 1 ? '{n} bloqueadas' : '{n} bloqueada').replace('{n}', n) : t('Nenhuma bloqueada');
    return `<button class="cfg-linha focusable" data-tipo="${tipo}">
      <span class="cfg-linha-rot">${escapar(t(rot))}</span>
      <span class="cfg-linha-val${n ? ' alerta' : ' ok'}">${txt}</span>
    </button>`;
  };
  pane.innerHTML = cfgCabecalho(t('Controle dos pais')) + `
    <div class="cfg-toggle-linha">
      <button class="cfg-toggle focusable${p.on ? ' on' : ''}" id="cfg-parental-toggle">
        <span class="cfg-toggle-rot">${escapar(t('Controle dos pais'))}</span>
        <span class="cfg-toggle-est">${p.on ? t('ATIVADO') : t('DESATIVADO')}</span>
      </button>
      ${p.on ? `<button class="btn btn-secundario focusable" id="cfg-parental-pin">${p.pin ? t('Alterar PIN') : t('Definir PIN')}</button>` : ''}
    </div>
    ${p.on ? `
      <div class="cfg-sub-titulo">${escapar(t('Bloqueios por categoria'))}</div>
      <div class="cfg-linhas">
        ${linhaTipo('canais', 'Canais')}
        ${linhaTipo('filmes', 'Filmes')}
        ${linhaTipo('series', 'Séries')}
      </div>` : ''}`;
  const refocarToggle = () => { const a = pane.querySelector('#cfg-parental-toggle'); if (a) SpatialNav.setFocus(a); };
  pane.querySelector('#cfg-parental-toggle').addEventListener('click', () => {
    const q = lerParental();
    if (!q.on) {
      // Ativar EXIGE um PIN definido — sem PIN os bloqueios não têm efeito.
      if (!q.pin) {
        definirPin(() => { const r = lerParental(); r.on = true; salvarParental(r); toast(t('Controle dos pais ativado')); paneParental(pane); refocarToggle(); });
        return;
      }
      q.on = true;
    } else { q.on = false; }
    salvarParental(q);
    toast(q.on ? t('Controle dos pais ativado') : t('Controle dos pais desativado'));
    paneParental(pane); refocarToggle();
  });
  const btnPin = pane.querySelector('#cfg-parental-pin');
  if (btnPin) btnPin.addEventListener('click', () => {
    const refoca = () => { paneParental(pane); const a = pane.querySelector('#cfg-parental-pin'); if (a) SpatialNav.setFocus(a); };
    const atual = lerParental();
    // ALTERAR PIN exige o PIN ATUAL antes (senão qualquer um trocava o bloqueio).
    // DEFINIR (1ª vez, sem PIN) vai direto.
    if (atual.pin) pedirPin(() => definirPin(refoca), t('Digite o PIN atual'));
    else definirPin(refoca);
  });
  pane.querySelectorAll('.cfg-linha[data-tipo]').forEach((b) =>
    b.addEventListener('click', () => abrirBloqueios(pane, b.dataset.tipo)));
}

// Sub-tela: lista as categorias do tipo; OK bloqueia/desbloqueia. "Voltar" no topo.
function abrirBloqueios(pane, tipo) {
  const rotTipo = t({ canais: 'Canais', filmes: 'Filmes', series: 'Séries' }[tipo] || tipo);
  const cats = catsDoTipo(tipo);
  const render = () => {
    const p = lerParental();
    const bloq = new Set(p[tipo] || []);
    pane.innerHTML = `
      <div class="cfg-bloq-cab">
        <button class="cfg-voltar focusable" id="cfg-bloq-voltar">${escapar(t('‹ Voltar'))}</button>
        <h1 class="cfg-h1">${escapar(t('{rot} — Categorias bloqueadas').replace('{rot}', rotTipo))}</h1>
      </div>
      <div class="cfg-hint-centro">${escapar(t('OK para bloquear / desbloquear'))}</div>
      <div class="cfg-bloq-lista">
        ${cats.length ? cats.map((c) => {
          const on = bloq.has(c);
          return `<button class="cfg-bloq-item focusable${on ? ' bloqueada' : ''}" data-cat="${escapar(c)}">
            <span class="cfg-bloq-nome">${escapar(c)}</span>
            <span class="cfg-bloq-est">${on ? t('bloqueada') : t('livre')}</span>
          </button>`;
        }).join('') : `<div class="cfg-vazio">${escapar(t('Nenhuma categoria nesta lista'))}</div>`}
      </div>`;
    pane.querySelector('#cfg-bloq-voltar').addEventListener('click', () => {
      paneParental(pane);
      const a = pane.querySelector('.cfg-linha[data-tipo="' + tipo + '"]'); if (a) SpatialNav.setFocus(a);
    });
    pane.querySelectorAll('.cfg-bloq-item').forEach((b) => b.addEventListener('click', () => {
      const q = lerParental();
      // Sem PIN definido, o bloqueio não vale — obriga a definir um antes.
      if (!q.pin) { definirPin(() => abrirBloqueios(pane, tipo)); return; }
      const set = new Set(q[tipo] || []);
      if (set.has(b.dataset.cat)) set.delete(b.dataset.cat); else set.add(b.dataset.cat);
      q[tipo] = [...set]; salvarParental(q);
      b.classList.toggle('bloqueada');
      b.querySelector('.cfg-bloq-est').textContent = set.has(b.dataset.cat) ? t('bloqueada') : t('livre');
    }));
  };
  render();
  const primeiro = pane.querySelector('.cfg-bloq-item') || pane.querySelector('#cfg-bloq-voltar');
  if (primeiro) SpatialNav.setFocus(primeiro);
}

// Teclado numérico (PIN de 4 dígitos). onOk() ao salvar.
function definirPin(onOk) {
  let val = '';
  const ov = document.createElement('div');
  ov.className = 'nav-modal cfg-pin';
  const teclas = ['1', '2', '3', '4', '5', '6', '7', '8', '9', 'del', '0', 'ok'];
  ov.innerHTML = `<div class="cfg-pin-card">
    <div class="cfg-pin-tit">${escapar(t('Defina um PIN de 4 dígitos'))}</div>
    <div class="cfg-pin-dots" id="cfg-pin-dots"></div>
    <div class="cfg-pin-grade">
      ${teclas.map((k) => `<button class="cfg-pin-key focusable${k === 'ok' ? ' cfg-pin-ok' : ''}${k === 'del' ? ' cfg-pin-del' : ''}" data-k="${k}">${k === 'del' ? '⌫' : k === 'ok' ? 'OK' : k}</button>`).join('')}
    </div>
  </div>`;
  document.body.appendChild(ov);
  const anterior = SpatialNav.atual;
  ov._onVoltar = () => { ov.remove(); if (anterior && document.contains(anterior)) SpatialNav.setFocus(anterior); };
  const dots = () => { const d = ov.querySelector('#cfg-pin-dots'); if (d) d.innerHTML = [0, 1, 2, 3].map((i) => `<span class="cfg-pin-dot${i < val.length ? ' on' : ''}"></span>`).join(''); };
  dots();
  ov.querySelectorAll('.cfg-pin-key').forEach((b) => b.addEventListener('click', () => {
    const k = b.dataset.k;
    if (k === 'del') { val = val.slice(0, -1); dots(); return; }
    if (k === 'ok') {
      if (val.length !== 4) { toast(t('O PIN deve ter 4 dígitos')); return; }
      const p = lerParental(); p.pin = val; salvarParental(p);
      ov.remove(); if (anterior && document.contains(anterior)) SpatialNav.setFocus(anterior);
      toast(t('PIN definido')); if (onOk) onOk();
      return;
    }
    if (val.length < 4) { val += k; dots(); }
  }));
  SpatialNav.setFocus(ov.querySelector('.cfg-pin-key'));
}

// Pede o PIN p/ liberar conteúdo bloqueado. onOk() se acertar. Sem PIN definido → libera.
// `titulo` opcional troca o texto (ex.: "Digite o PIN atual" ao alterar o PIN).
function pedirPin(onOk, titulo) {
  const p = lerParental();
  if (!p.on || !p.pin) { onOk(); return; }
  let val = '';
  const ov = document.createElement('div');
  ov.className = 'nav-modal cfg-pin';
  const teclas = ['1', '2', '3', '4', '5', '6', '7', '8', '9', 'del', '0', 'ok'];
  ov.innerHTML = `<div class="cfg-pin-card">
    <div class="cfg-pin-tit">${escapar(titulo || t('Conteúdo bloqueado — digite o PIN'))}</div>
    <div class="cfg-pin-dots" id="cfg-pin-dots"></div>
    <div class="cfg-pin-grade">
      ${teclas.map((k) => `<button class="cfg-pin-key focusable${k === 'ok' ? ' cfg-pin-ok' : ''}${k === 'del' ? ' cfg-pin-del' : ''}" data-k="${k}">${k === 'del' ? '⌫' : k === 'ok' ? 'OK' : k}</button>`).join('')}
    </div>
  </div>`;
  document.body.appendChild(ov);
  const anterior = SpatialNav.atual;
  ov._onVoltar = () => { ov.remove(); if (anterior && document.contains(anterior)) SpatialNav.setFocus(anterior); };
  const dots = () => { const d = ov.querySelector('#cfg-pin-dots'); if (d) d.innerHTML = [0, 1, 2, 3].map((i) => `<span class="cfg-pin-dot${i < val.length ? ' on' : ''}"></span>`).join(''); };
  dots();
  ov.querySelectorAll('.cfg-pin-key').forEach((b) => b.addEventListener('click', () => {
    const k = b.dataset.k;
    if (k === 'del') { val = val.slice(0, -1); dots(); return; }
    if (k === 'ok') {
      if (val === p.pin) { ov.remove(); if (anterior && document.contains(anterior)) SpatialNav.setFocus(anterior); onOk(); }
      else { toast(t('PIN incorreto')); val = ''; dots(); }
      return;
    }
    if (val.length < 4) { val += k; dots(); }
  }));
  SpatialNav.setFocus(ov.querySelector('.cfg-pin-key'));
}

// Enforcement usado pelo app.js
function canalCatBloqueada(cat) {
  const p = lerParental();
  return !!(p.on && (p.canais || []).includes(cat));
}
function conteudoBloqueado(item) {
  const p = lerParental();
  if (!p.on || !item) return false;
  const tipo = item.tipo === 'serie' ? 'series' : 'filmes';
  const bl = (p[tipo] || []).map((x) => x.toLowerCase());
  if (!bl.length) return false;
  return (item.generos || []).some((g) => bl.includes((g || '').toLowerCase()));
}

// ═══════════════════════════════════════════════════════════════════════════
//  DADOS — Limpar cache / Limpar histórico
// ═══════════════════════════════════════════════════════════════════════════
function paneCache(pane) {
  pane.innerHTML = cfgCabecalho(t('Limpar cache'),
    t('Limpa o cache de dados do app (início, canais, filmes, séries). O conteúdo será baixado novamente na próxima abertura.')) +
    cfgCentro(IC_DB_BIG, `<button class="btn btn-primario focusable" id="cfg-cache-btn">${escapar(t('Limpar Cache'))}</button>`);
  pane.querySelector('#cfg-cache-btn').addEventListener('click', () =>
    confirmarAcao(t('Limpar cache?'), t('O conteúdo será baixado novamente.'), () => {
      toast(t('Cache limpo — recarregando…'));
      setTimeout(() => location.reload(), 700);
    }));
}
function paneHistorico(pane) {
  pane.innerHTML = cfgCabecalho(t('Limpar histórico'),
    t('Apaga o histórico de reprodução. Todo o progresso de episódios e filmes será perdido.')) +
    cfgCentro(IC_HIST_BIG, `<button class="btn btn-primario focusable" id="cfg-hist-btn">${escapar(t('Limpar Histórico'))}</button>`);
  pane.querySelector('#cfg-hist-btn').addEventListener('click', () =>
    confirmarAcao(t('Limpar histórico?'), t('Todo o progresso será perdido.'), () => {
      try { localStorage.removeItem('tv_historico'); localStorage.removeItem('tv_progresso'); } catch (_) {}
      toast(t('Histórico limpo'));
    }));
}

// Modal de confirmação (reusa o visual do menu de opções).
function confirmarAcao(titulo, msg, onSim) {
  const ov = document.createElement('div');
  ov.className = 'nav-modal cfg-confirm';
  ov.innerHTML = `<div class="cfg-conf-card">
    <div class="cfg-conf-tit">${escapar(titulo)}</div>
    <div class="cfg-conf-msg">${escapar(msg)}</div>
    <div class="cfg-conf-acoes">
      <button class="btn btn-secundario focusable" data-r="nao">${escapar(t('Cancelar'))}</button>
      <button class="btn btn-primario focusable" data-r="sim">${escapar(t('Confirmar'))}</button>
    </div>
  </div>`;
  document.body.appendChild(ov);
  const anterior = SpatialNav.atual;
  const fechar = () => { ov.remove(); if (anterior && document.contains(anterior)) SpatialNav.setFocus(anterior); };
  ov._onVoltar = fechar;
  ov.querySelector('[data-r="nao"]').addEventListener('click', fechar);
  ov.querySelector('[data-r="sim"]').addEventListener('click', () => { fechar(); onSim(); });
  SpatialNav.setFocus(ov.querySelector('[data-r="nao"]'));
}

// ═══════════════════════════════════════════════════════════════════════════
//  CONTA — Playlist ativa / Minhas Informações
// ═══════════════════════════════════════════════════════════════════════════
function panePlaylist(pane) {
  pane.innerHTML = cfgCabecalho(t('Playlist ativa'),
    t('Adicione, remova ou troque sua playlist ativa na aba de Playlists.')) +
    cfgCentro(IC_PL_BIG, `<button class="btn btn-primario focusable" id="cfg-pl-btn">${escapar(t('Gerenciar Playlists'))}</button>`);
  pane.querySelector('#cfg-pl-btn').addEventListener('click', () => navegar('playlists'));
}

// Credenciais Xtream a partir da URL da playlist ativa (se houver).
function xtreamCreds() {
  const reg = Dispositivo.registro();
  const url = reg && reg.lista_url;
  if (!url) return null;
  try {
    const u = new URL(url);
    const user = u.searchParams.get('username');
    const pass = u.searchParams.get('password');
    if (!user || !pass) return null;
    return { base: `${u.protocol}//${u.host}`, user, pass };
  } catch (_) { return null; }
}
const dataBR = (unix) => { const n = Number(unix); if (!n) return '—'; const d = new Date(n * 1000); return isNaN(d) ? '—' : d.toLocaleDateString('pt-BR'); };

// Consulta a conta Xtream (player_api) da playlist ativa. Resolve com user_info
// ou null (sem Xtream / erro de rede/CORS). Fonte única p/ "Minhas Informações"
// E "Sobre / Versão" — assim a licença exibida é a MESMA nas duas telas.
function buscarContaXtream() {
  const cr = xtreamCreds();
  if (!cr) return Promise.resolve(null);
  const u = `${cr.base}/player_api.php?username=${encodeURIComponent(cr.user)}&password=${encodeURIComponent(cr.pass)}`;
  return fetch(u).then((r) => r.json()).then((j) => (j && j.user_info) ? j.user_info : null).catch(() => null);
}
// Cache de 3 min p/ Minhas Informações — sem isso, a conta Xtream era re-buscada
// na rede a CADA foco (ao entrar/sair do painel). Após o TTL, o próximo acesso
// força a atualização; os botões "Verificar status" forçam na hora.
const INFO_TTL = 3 * 60 * 1000;
let _contaXt = null, _contaXtEm = 0, _licConsultaEm = 0;

function licBlocoInfoHTML(lic) {
  return `<div class="cfg-lic ${lic.ok ? 'ok' : 'alerta'}">
    <div class="cfg-lic-rot">${escapar(t('Ativação do dispositivo — feita pelo revendedor no painel (MAC + Key)'))}</div>
    <div class="cfg-lic-tit">${escapar(lic.tit)}</div>
    <div class="cfg-lic-sub">${escapar(lic.sub)}</div>
    <div class="cfg-lic-ids"><span>MAC <b>${escapar(Dispositivo.mac())}</b></span><span>Key <b>${escapar(Dispositivo.key())}</b></span></div>
  </div>`;
}
// Desenha a conta Xtream (ou o estado vazio/erro) dentro do corpo da playlist.
function pintarPlaylistXt(corpo, i, cr) {
  if (!i) { corpo.innerHTML = `<div class="cfg-vazio">${escapar(t('Não foi possível carregar os dados da playlist (servidor fora do ar ou bloqueio do navegador).'))}</div>`; return; }
  const ativo = String(i.status || '').toLowerCase() === 'active';
  const linhas = [
    [t('Status'), `<span class="${ativo ? 'cfg-ok' : 'cfg-alerta'}">${ativo ? t('Ativo') : escapar(i.status || '—')}</span>`],
    [t('Usuário'), escapar(i.username || cr.user)],
    [t('Conex. máximas'), escapar(i.max_connections || '—')],
    [t('Conex. ativas'), escapar(i.active_cons != null ? String(i.active_cons) : '—')],
    [t('Conta trial'), i.is_trial === '1' ? t('Sim') : t('Não')],
    [t('Criado em'), dataBR(i.created_at)],
  ];
  corpo.innerHTML = `
    <div class="cfg-venc"><span class="cfg-venc-rot">${escapar(t('VENCIMENTO DA PLAYLIST'))}</span><span class="cfg-venc-data">${dataBR(i.exp_date)}</span></div>
    <div class="cfg-tab">${linhas.map(([k, v]) => `<div class="cfg-tab-row"><span class="cfg-tab-k">${escapar(k)}</span><span class="cfg-tab-v">${v}</span></div>`).join('')}</div>`;
}
// Playlist: usa o cache de 3 min; `force` (ou cache vencido) busca na rede.
function atualizarPlaylistInfo(pane, force) {
  const corpo = pane.querySelector('#cfg-info-corpo');
  if (!corpo) return;
  const cr = xtreamCreds();
  if (!cr) { corpo.innerHTML = `<div class="cfg-vazio">${escapar(t('Sem conta de provedor para esta playlist (lista M3U sem login Xtream).'))}</div>`; return; }
  const fresca = _contaXtEm > 0 && (Date.now() - _contaXtEm) < INFO_TTL;
  if (!force && fresca) { pintarPlaylistXt(corpo, _contaXt, cr); return; }
  if (force) toast(t('Verificando playlist…'));
  corpo.innerHTML = `<div class="cfg-carregando">${escapar(t('Carregando dados da playlist…'))}</div>`;
  buscarContaXtream().then((i) => {
    _contaXt = i; _contaXtEm = Date.now();
    const c = pane.querySelector('#cfg-info-corpo'); if (!c) return;
    pintarPlaylistXt(c, i, cr);
    if (force) toast(i ? t('Playlist atualizada') : t('Não foi possível verificar'));
  });
}
// Licença: re-consulta a nuvem (silenciosa quando o cache venceu; com feedback no botão).
async function atualizarLicencaInfo(pane, feedback) {
  const btn = pane.querySelector('#cfg-btn-lic');
  if (feedback) { toast(t('Verificando licença…')); if (btn) btn.textContent = t('Verificando…'); }
  await Dispositivo.consultar();
  _licConsultaEm = Date.now();
  const area = pane.querySelector('#cfg-lic-area'); if (area) area.innerHTML = licBlocoInfoHTML(licencaTxt());
  if (btn) btn.textContent = t('Verificar status da Licença');
  if (feedback) toast(t('Licença atualizada'));
}

function paneInfo(pane) {
  // Duas coisas DIFERENTES, rotuladas: (1) Licença do app = ativação do device
  // (MAC+Key) feita no painel; (2) Playlist = conta do provedor (Xtream).
  // Ambas em cache de 3 min → não re-buscam a cada foco.
  pane.innerHTML = cfgCabecalho(t('Minhas Informações'),
    t('A licença do app (ativada pelo revendedor) e a conta da sua playlist (do provedor) são coisas diferentes — veja cada uma abaixo.')) + `
    <div class="cfg-sub-titulo">${escapar(t('Licença do app (Hero Play)'))}</div>
    <div id="cfg-lic-area">${licBlocoInfoHTML(licencaTxt())}</div>
    <button class="btn btn-secundario focusable cfg-scroll-topo" id="cfg-btn-lic" style="margin:16px 0 4px">${escapar(t('Verificar status da Licença'))}</button>

    <div class="cfg-sub-titulo" style="margin-top:30px">${escapar(t('Playlist (conta do seu provedor)'))}</div>
    <div class="cfg-info-corpo" id="cfg-info-corpo"><div class="cfg-carregando">${escapar(t('Carregando dados da playlist…'))}</div></div>
    <button class="btn btn-secundario focusable" id="cfg-btn-pl" style="margin:16px 0 4px">${escapar(t('Verificar status da playlist'))}</button>`;

  // Licença: se passou do TTL desde a última consulta, atualiza silenciosamente.
  if ((Date.now() - _licConsultaEm) > INFO_TTL) atualizarLicencaInfo(pane, false);
  // Playlist: usa cache (ou busca se vencido).
  atualizarPlaylistInfo(pane, false);

  pane.querySelector('#cfg-btn-lic').addEventListener('click', () => atualizarLicencaInfo(pane, true));
  pane.querySelector('#cfg-btn-pl').addEventListener('click', () => atualizarPlaylistInfo(pane, true));
}

// ═══════════════════════════════════════════════════════════════════════════
//  JOGOS — Gerenciar alertas
// ═══════════════════════════════════════════════════════════════════════════
function paneAlertas(pane) {
  pane.innerHTML = cfgCabecalho(t('Gerenciar alertas')) + `
    <div class="cfg-aviso"><b>${escapar(t('Como funcionam os alertas:'))}</b> ${escapar(t('você será notificado 30 min, 15 min, 5 min e na hora da partida. Adicione alertas na aba Futebol.'))}</div>
    <div class="cfg-centro">
      <div class="cfg-centro-ico">${IC_BELL_BIG}</div>
      <div class="cfg-centro-tit">${escapar(t('Nenhum alerta salvo'))}</div>
      <div class="cfg-centro-sub">${escapar(t('Adicione alertas na aba Futebol.'))}</div>
      <button class="btn btn-secundario focusable" id="cfg-alerta-btn" style="margin-top:22px">${escapar(t('Testar Notificação'))}</button>
    </div>`;
  pane.querySelector('#cfg-alerta-btn').addEventListener('click', () => {
    if ('Notification' in window) {
      Notification.requestPermission().then((p) => {
        if (p === 'granted') { try { new Notification('Hero Play', { body: t('Notificação de teste ✔') }); } catch (_) {} toast(t('Notificação enviada ✔')); }
        else toast(t('Notificações bloqueadas neste dispositivo'));
      });
    } else toast(t('Notificação de teste ✔'));
  });
}

// ═══════════════════════════════════════════════════════════════════════════
//  CLIMA — Clima & Horário (open-meteo, sem chave)
// ═══════════════════════════════════════════════════════════════════════════
const CLIMA_COND = { 0: 'Ensolarado', 1: 'Predom. limpo', 2: 'Parcial. nublado', 3: 'Nublado', 45: 'Nevoeiro', 48: 'Nevoeiro', 51: 'Garoa leve', 53: 'Garoa', 55: 'Garoa forte', 61: 'Chuva leve', 63: 'Chuva', 65: 'Chuva forte', 71: 'Neve leve', 73: 'Neve', 75: 'Neve forte', 80: 'Pancadas', 81: 'Pancadas', 82: 'Pancadas fortes', 95: 'Tempestade', 96: 'Tempestade', 99: 'Tempestade' };
const bussola = (g) => ['N', 'NE', 'L', 'SE', 'S', 'SO', 'O', 'NO'][Math.round(((g || 0) % 360) / 45) % 8];

function paneClima(pane) {
  pane.innerHTML = cfgCabecalho(t('Clima & Horário')) + `<div id="cfg-clima-corpo"><div class="cfg-carregando">${escapar(t('Carregando clima…'))}</div></div>`;
  carregarClima(pane);
}
async function carregarClima(pane) {
  const corpo = pane.querySelector('#cfg-clima-corpo');
  if (!corpo) return;
  corpo.innerHTML = `<div class="cfg-carregando">${escapar(t('Carregando clima…'))}</div>`;
  try {
    const loc = await fetch('https://ipapi.co/json/').then((r) => r.json());
    const lat = loc.latitude, lon = loc.longitude;
    const cidade = [loc.city, loc.region, loc.country_name].filter(Boolean).join(', ');
    const wu = `https://api.open-meteo.com/v1/forecast?latitude=${lat}&longitude=${lon}&current=temperature_2m,apparent_temperature,relative_humidity_2m,wind_speed_10m,wind_direction_10m,surface_pressure,precipitation,visibility,weather_code,uv_index&timezone=auto`;
    const w = await fetch(wu).then((r) => r.json());
    if (!pane.querySelector('#cfg-clima-corpo')) return;
    const c = w.current || {};
    const cond = CLIMA_COND[c.weather_code] ? t(CLIMA_COND[c.weather_code]) : '—';
    const card = (rot, val) => `<div class="cfg-clima-card"><div class="cfg-clima-card-rot">${escapar(rot)}</div><div class="cfg-clima-card-val">${val}</div></div>`;
    corpo.innerHTML = `
      <div class="cfg-clima-local">${escapar(cidade || t('Localização desconhecida'))}</div>
      <div class="cfg-clima-temp"><span class="cfg-clima-graus">${Math.round(c.temperature_2m)} C°</span><span class="cfg-clima-cond">${escapar(cond)}</span></div>
      <div class="cfg-clima-grid">
        ${card(t('Sensação térmica'), Math.round(c.apparent_temperature) + ' C')}
        ${card(t('Humidade'), (c.relative_humidity_2m != null ? c.relative_humidity_2m : '—') + '%')}
        ${card(t('Vento'), bussola(c.wind_direction_10m) + ' ' + Math.round(c.wind_speed_10m) + ' km/h')}
        ${card(t('Índice UV'), c.uv_index != null ? Math.round(c.uv_index) : '—')}
        ${card(t('Visibilidade'), c.visibility != null ? Math.round(c.visibility / 1000) + ' km' : '—')}
        ${card(t('Pressão'), (c.surface_pressure != null ? Math.round(c.surface_pressure) : '—') + ' hPa')}
        ${card(t('Precipitação'), (c.precipitation != null ? c.precipitation : 0).toFixed(1) + ' mm')}
      </div>
      <button class="btn btn-secundario focusable" id="cfg-clima-att" style="margin-top:26px">${escapar(t('Atualizar'))}</button>`;
    corpo.querySelector('#cfg-clima-att').addEventListener('click', () => carregarClima(pane));
  } catch (_) {
    if (!pane.querySelector('#cfg-clima-corpo')) return;
    corpo.innerHTML = `<div class="cfg-vazio">${escapar(t('Não foi possível obter o clima.'))}</div>
      <button class="btn btn-secundario focusable" id="cfg-clima-att" style="margin-top:20px">${escapar(t('Tentar de novo'))}</button>`;
    const b = corpo.querySelector('#cfg-clima-att'); if (b) b.addEventListener('click', () => carregarClima(pane));
  }
}

// ═══════════════════════════════════════════════════════════════════════════
//  INFO — Sobre / Termos / Velocidade
// ═══════════════════════════════════════════════════════════════════════════
const SITE_URL = 'https://heroplaytv.com';
// Licença de fallback (quando não há conta Xtream p/ consultar): status local do
// device. Retorna { ok, tit, sub }.
function licencaTxt() {
  const s = Dispositivo.status();
  if (s === 'ativo') return { ok: true, tit: t('Licença Ativa'), sub: t('Vitalícia') };
  if (s === 'trial') return { ok: true, tit: t('Em teste'), sub: t('Restam {n} dia(s)').replace('{n}', Dispositivo.diasTeste()) };
  if (s === 'expirado') return { ok: false, tit: t('Licença expirada'), sub: t('Renove pelo site') };
  return { ok: false, tit: t('Sem licença'), sub: t('Adicione uma playlist') };
}
function licBlocoHTML(lic) {
  return `<div class="cfg-lic ${lic.ok ? 'ok' : 'alerta'}" id="cfg-lic-block">
    <div class="cfg-lic-rot">${escapar(t('Licença do App'))}</div>
    <div class="cfg-lic-tit">${escapar(lic.tit)}</div>
    <div class="cfg-lic-sub">${escapar(lic.sub)}</div>
  </div>`;
}
// Diagnóstico de memória: mostra o ORÇAMENTO real de heap da TV e onde ele é
// gasto (lista crua vs. catálogo em memória). Base p/ decidir as otimizações.
function paneDiag(pane) {
  const nEp = (LISTA.series || []).reduce((s, x) => s + ((x.episodios || []).length), 0);
  const itens = (LISTA.canais || []).length + (LISTA.filmes || []).length + (LISTA.series || []).length;
  const limite = _heapLimite();
  const agora = _heap();
  const pct = limite ? Math.min(100, Math.round((agora / limite) * 100)) : 0;
  const linhas = [
    [t('Heap em uso agora'), _mb(agora)],
    [t('Limite de heap (orçamento da TV)'), _mb(limite)],
    [t('Uso'), limite ? pct + '%' : '—'],
    [t('Heap antes do parse'), _mb(_diag.heapAntes)],
    [t('Heap logo após o parse'), _mb(_diag.heapPico)],
    [t('Custo do parse'), _diag.heapPico && _diag.heapAntes ? _mb(_diag.heapPico - _diag.heapAntes) : '—'],
    [t('Origem do catálogo'), _diag.doCache ? t('Cache (rápido)') : t('Parse da lista')],
    [t('Cache — leitura'), (CacheLista.status.ler || '—') + (CacheLista.status.msLer ? ' (' + CacheLista.status.msLer + ' ms)' : '')],
    [t('Cache — gravação'), (CacheLista.status.gravar || '—') + (CacheLista.status.msGravar ? ' (' + CacheLista.status.msGravar + ' ms)' : '')],
    [t('Cache — capas (TMDB)'), CacheLista.status.meta || '—'],
    [t('Tempo do parse'), _diag.msParse ? _diag.msParse + ' ms' : '—'],
    [t('Tamanho da lista (texto)'), _mb(_diag.bytesLista)],
    [t('Canais'), String((LISTA.canais || []).length)],
    [t('Filmes'), String((LISTA.filmes || []).length)],
    [t('Séries'), String((LISTA.series || []).length)],
    [t('Episódios'), String(nEp)],
    [t('Total de itens'), String(itens + nEp)],
  ];
  pane.innerHTML = cfgCabecalho(t('Diagnóstico (memória)')) + `
    <div class="cfg-tab cfg-tab-sobre">${linhas.map(([k, v]) =>
      `<div class="cfg-tab-row"><span class="cfg-tab-k">${escapar(k)}</span><span class="cfg-tab-v">${escapar(v)}</span></div>`).join('')}</div>
    <div class="cfg-aviso">${escapar(t('Se o "Uso" passa de ~70% do limite, a TV pode encerrar o app. Use estes números para decidir as otimizações.'))}</div>
    <button class="btn btn-secundario focusable" id="diag-att" style="margin-top:22px">${escapar(t('Atualizar'))}</button>`;
  const b = pane.querySelector('#diag-att');
  if (b) b.addEventListener('click', () => paneDiag(pane));
}

function paneSobre(pane) {
  // Android TV/TV Box entra ANTES: a casca manda "SmartTV" no userAgent, então
  // sem esta checagem um TV Box aparecia como "Web / Navegador".
  const ehAndroid = (function () { try { return !!window.HeroPlayAndroid; } catch (_) { return false; } })();
  const disp = ehAndroid ? 'Android TV / TV Box'
    : /Tizen/i.test(navigator.userAgent) ? 'Samsung Tizen'
    : /Web0S|webOS/i.test(navigator.userAgent) ? 'LG webOS'
    : t('Web / Navegador');
  // VIEWPORT: quantos px de CSS a tela tem. O app é desenhado para 1600 (ver o
  // <meta viewport> do index.html). Se aparecer um número bem menor aqui, a TV
  // está IGNORANDO o meta — e é isso que espreme as colunas (nome de categoria
  // cortado em duas letras). Serve pra diagnosticar por foto, sem adb.
  const vp = `${window.innerWidth}×${window.innerHeight}`;
  const linhas = [
    [t('Versão do App'), APP_VERSAO],
    [t('Dispositivo'), disp],
    [t('Tela (viewport)'), vp + (window.innerWidth < 1400 ? ' ⚠' : '')],
    [t('Endereço MAC'), Dispositivo.mac()],
    [t('Device Key'), Dispositivo.key()],
  ];
  pane.innerHTML = cfgCabecalho(t('Sobre / Versão')) + `
    <div class="cfg-tab cfg-tab-sobre">${linhas.map(([k, v]) => `<div class="cfg-tab-row"><span class="cfg-tab-k">${escapar(k)}</span><span class="cfg-tab-v">${escapar(v)}</span></div>`).join('')}</div>
    ${licBlocoHTML(licencaTxt())}
    <div class="cfg-qr-bloco">
      <div class="cfg-qr-txt">${escapar(t('Escaneie para acessar o site:'))}</div>
      <div class="cfg-qr" id="cfg-sobre-qr"></div>
      <div class="cfg-qr-link">${SITE_URL.replace('https://', '')}</div>
    </div>
    <div class="cfg-copy">© ${new Date().getFullYear()} Hero Play. ${escapar(t('Todos os direitos reservados.'))}</div>`;
  gerarQr('cfg-sobre-qr', SITE_URL);
}
function paneTermos(pane) {
  pane.innerHTML = cfgCabecalho(t('Termos de uso'), t('Leia os Termos de Uso e a Política de Privacidade do Hero Play.')) +
    cfgCentro(IC_DOC_BIG, `<button class="btn btn-primario focusable" id="cfg-termos-btn">${escapar(t('Abrir Termos de Uso'))}</button>`);
  pane.querySelector('#cfg-termos-btn').addEventListener('click', () => abrirTermos());
}
function abrirTermos() {
  const ov = document.createElement('div');
  ov.className = 'nav-modal cfg-termos';
  ov.innerHTML = `<div class="cfg-termos-card">
    <div class="cfg-termos-tit">${escapar(t('Termos de uso e Privacidade'))}</div>
    <div class="cfg-termos-txt">${escapar(t('Escaneie o código para ler os Termos de Uso e a Política de Privacidade no site.'))}</div>
    <div class="cfg-qr" id="cfg-termos-qr"></div>
    <div class="cfg-qr-link">${SITE_URL.replace('https://', '')}/termos</div>
    <button class="btn btn-secundario focusable" id="cfg-termos-fechar" style="margin-top:22px">${escapar(t('Fechar'))}</button>
  </div>`;
  document.body.appendChild(ov);
  const anterior = SpatialNav.atual;
  const fechar = () => { ov.remove(); if (anterior && document.contains(anterior)) SpatialNav.setFocus(anterior); };
  ov._onVoltar = fechar;
  gerarQr('cfg-termos-qr', SITE_URL + '/termos');
  ov.querySelector('#cfg-termos-fechar').addEventListener('click', fechar);
  SpatialNav.setFocus(ov.querySelector('#cfg-termos-fechar'));
}
// ── Velocímetro (SVG) ────────────────────────────────────────────────────────
// Escala do medidor: 0 → GAUGE_MAX Mbps num semicírculo. Ponto na borda p/ o
// fração t∈[0,1] (0 = esq./lento, 1 = dir./rápido); segmentos coloridos e agulha.
const GAUGE_CX = 110, GAUGE_CY = 112, GAUGE_R = 90, GAUGE_MAX = 100;
function _ptGauge(t) {
  const th = (180 - t * 180) * Math.PI / 180;
  return [GAUGE_CX + GAUGE_R * Math.cos(th), GAUGE_CY - GAUGE_R * Math.sin(th)];
}
function _arcoGauge(a, b) {
  const [x1, y1] = _ptGauge(a), [x2, y2] = _ptGauge(b);
  return `M ${x1.toFixed(1)} ${y1.toFixed(1)} A ${GAUGE_R} ${GAUGE_R} 0 0 1 ${x2.toFixed(1)} ${y2.toFixed(1)}`;
}
function gaugeHTML() {
  const seg = (a, b, cor) => `<path d="${_arcoGauge(a, b)}" stroke="${cor}" stroke-width="16" fill="none" stroke-linecap="butt"/>`;
  return `<svg class="cfg-gauge" viewBox="0 0 220 132">
    <path d="${_arcoGauge(0, 1)}" stroke="rgba(255,255,255,.06)" stroke-width="16" fill="none"/>
    ${seg(0.02, 0.32, '#E5484D')}${seg(0.35, 0.65, '#E8B23A')}${seg(0.68, 0.98, '#4FB477')}
    <polygon id="cfg-gauge-needle" points="${GAUGE_CX - 5},${GAUGE_CY} ${GAUGE_CX + 5},${GAUGE_CY} ${GAUGE_CX},${GAUGE_CY - GAUGE_R + 6}"
      fill="#F5F1EC" transform="rotate(-90 ${GAUGE_CX} ${GAUGE_CY})"/>
    <circle cx="${GAUGE_CX}" cy="${GAUGE_CY}" r="11" fill="#F5F1EC"/>
    <circle cx="${GAUGE_CX}" cy="${GAUGE_CY}" r="4" fill="#0F0E0D"/>
  </svg>`;
}
function classificarConexao(mbps) {
  if (mbps >= 30) return { txt: 'Conexão Boa', cls: 'boa' };
  if (mbps >= 10) return { txt: 'Conexão Média', cls: 'media' };
  return { txt: 'Conexão Ruim', cls: 'ruim' };
}
// Anima a agulha (rotate) + a contagem do número até `mbps` (transform-only, 60fps).
function animarGauge(pane, mbps) {
  const t = Math.max(0, Math.min(1, mbps / GAUGE_MAX));
  const alvo = t * 180 - 90;               // -90 (0) … +90 (max)
  const needle = pane.querySelector('#cfg-gauge-needle');
  const num = pane.querySelector('#cfg-gauge-num');
  const dur = 1300, t0 = performance.now();
  const easeOut = (x) => 1 - Math.pow(1 - x, 3);
  (function frame(now) {
    if (!pane.querySelector('#cfg-gauge-num')) return;   // saiu da tela
    const p = Math.min(1, (now - t0) / dur), e = easeOut(p);
    if (needle) needle.setAttribute('transform', `rotate(${(-90 + (alvo + 90) * e).toFixed(2)} ${GAUGE_CX} ${GAUGE_CY})`);
    if (num) num.textContent = (mbps * e).toFixed(1);
    if (p < 1) requestAnimationFrame(frame);
  })(t0);
}
function paneVelocidade(pane) {
  pane.innerHTML = cfgCabecalho(t('Testar velocidade de conexão'), t('Baixa ~5 MB de um servidor de teste e mede a velocidade de download da sua conexão.')) +
    `<div class="cfg-centro">
      <div class="cfg-gauge-wrap">${gaugeHTML()}</div>
      <div class="cfg-gauge-val"><span id="cfg-gauge-num">0.0</span><span class="cfg-gauge-un">Mbps</span></div>
      <div class="cfg-gauge-rot" id="cfg-gauge-rot">${escapar(t('Pressione OK para medir sua conexão'))}</div>
      <button class="btn btn-primario focusable" id="cfg-speed-btn">${escapar(t('Iniciar Teste de Velocidade'))}</button>
    </div>`;
  pane.querySelector('#cfg-speed-btn').addEventListener('click', () => testarVelocidade(pane));
}
async function testarVelocidade(pane) {
  const btn = pane.querySelector('#cfg-speed-btn');
  const rot = pane.querySelector('#cfg-gauge-rot');
  if (!btn) return;
  btn.textContent = t('Testando…');
  const needle = pane.querySelector('#cfg-gauge-needle'); if (needle) needle.setAttribute('transform', `rotate(-90 ${GAUGE_CX} ${GAUGE_CY})`);
  const num = pane.querySelector('#cfg-gauge-num'); if (num) num.textContent = '0.0';
  if (rot) { rot.className = 'cfg-gauge-rot medindo'; rot.textContent = t('Medindo sua conexão…'); }
  const bytes = 5000000;
  try {
    const t0 = performance.now();
    const r = await fetch(`https://speed.cloudflare.com/__down?bytes=${bytes}&r=${Math.random()}`, { cache: 'no-store' });
    await r.arrayBuffer();
    const secs = (performance.now() - t0) / 1000;
    const mbps = (bytes * 8 / 1e6) / secs;
    if (!pane.querySelector('#cfg-gauge-num')) return;
    animarGauge(pane, mbps);
    const c = classificarConexao(mbps);
    const r2 = pane.querySelector('#cfg-gauge-rot'); if (r2) { r2.className = 'cfg-gauge-rot ' + c.cls; r2.textContent = t(c.txt); }
  } catch (_) {
    const r2 = pane.querySelector('#cfg-gauge-rot'); if (r2) { r2.className = 'cfg-gauge-rot ruim'; r2.textContent = t('Falha no teste. Verifique a conexão.'); }
  } finally {
    if (btn && document.contains(btn)) btn.textContent = t('Testar de novo');
  }
}

// ── Mapa id → função de painel ──────────────────────────────────────────────
const CFG_PANES = {
  perfil: panePerfil, idioma: paneIdioma, qualidade: paneQualidade, parental: paneParental, cache: paneCache, historico: paneHistorico,
  playlist: panePlaylist, info: paneInfo, alertas: paneAlertas, clima: paneClima,
  sobre: paneSobre, termos: paneTermos, velocidade: paneVelocidade, diag: paneDiag,
};