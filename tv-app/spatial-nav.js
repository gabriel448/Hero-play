/* ============================================================================
   Navegacao espacial (D-pad) — vanilla, sem framework.
   Move o foco entre elementos `.focusable` pela GEOMETRIA: ao apertar uma seta,
   escolhe o candidato naquela direcao com menor distancia (penalizando desvio
   no eixo cruzado). Enter = ativar (click). Backspace = voltar ao menu.
   ============================================================================ */

const SpatialNav = (() => {
  let atual = null;

  const visivel = (el) => {
    const r = el.getBoundingClientRect();
    return r.width > 0 && r.height > 0;
  };
  // Se houver modal(is) (.nav-modal), navega SO dentro do mais recente (topo da
  // pilha) — suporta menu de qualidade/fonte sobreposto ao player.
  const modalTopo = () => { const ms = document.querySelectorAll('.nav-modal'); return ms.length ? ms[ms.length - 1] : null; };
  const focaveis = () => {
    const top = modalTopo();
    let els = [...(top || document).querySelectorAll('.focusable')];
    // Busca de seção: a sidebar continua navegável (como na busca normal), mesmo
    // sendo um modal — inclui os itens do menu no escopo.
    if (top && (top.classList.contains('busca-secao') || top.classList.contains('addpl'))) {
      const sb = document.getElementById('sidebar');
      if (sb) els = els.concat([...sb.querySelectorAll('.focusable')]);
    }
    return els.filter(visivel);
  };
  const rect = (el) => el.getBoundingClientRect();
  const centro = (r) => ({ x: r.left + r.width / 2, y: r.top + r.height / 2 });
  // "Area" do elemento. O ↑/↓ so navega DENTRO da mesma area — isola as regioes
  // em COLUNA (sidebar, coluna de temporadas, colunas da TV ao vivo) p/ o foco
  // vertical nao vazar de uma coluna para outra. O conteudo em LINHAS (detalhe,
  // home) fica todo em 'main', onde ↑/↓ anda entre as secoes livremente.
  const areaDe = (el) => {
    if (!el.closest) return 'main';
    if (el.closest('#sidebar')) return 'side';
    if (el.closest('.ep-temps')) return 'temps';      // seletor de temporadas (esq.)
    if (el.closest('.tv-col-esq')) return 'tv-esq';   // TV ao vivo: categorias/canais
    if (el.closest('.tv-col-dir')) return 'tv-dir';   // TV ao vivo: preview/EPG
    if (el.closest('.bsc-esq')) return 'bsc-kb';      // Busca: teclado on-screen
    if (el.closest('.bsc-dir')) return 'bsc-res';     // Busca: grade de resultados
    if (el.closest('.cfg-menu')) return 'cfg-menu';   // Config: coluna de menu (esq.)
    if (el.closest('.jogos-datas')) return 'jg-datas';// Jogos: abas de data (topo)
    if (el.closest('.jogos-ligas')) return 'jg-ligas';// Jogos: coluna de ligas (esq.)
    if (el.closest('#jogos-jogos')) return 'jg-jogos';// Jogos: lista de jogos/canais (dir.)
    // Onboarding: QR/Recarregar (esq.) e formulario (dir.) sao areas SEPARADAS.
    // Na mesma area o ←/→ exige estar na mesma LINHA, e o Recarregar fica ABAIXO
    // dos campos — sem isto nao dava para chegar nele indo para a esquerda.
    if (el.closest('.ob-left')) return 'ob-esq';
    if (el.closest('.ob-right')) return 'ob-dir';
    return 'main';
  };

  let aoFocarCb = null; // callback externo (ex.: atualizar hero ao focar poster)

  /**
   * Como rolar: INSTANTÂNEO na TV, suave no desktop.
   *
   * Segurando o D-pad o foco anda a cada ~150 ms, e cada troca pedia um scroll
   * ANIMADO. As animações se atropelavam: a próxima posição era calculada com a
   * lista ainda em movimento, o delta saía errado e a tela "pulava" — é o
   * travamento que se vê ao segurar a direção. O CSS do modo TV já dizia
   * `scroll-behavior: auto` justamente por isso, mas a opção `behavior` do
   * scrollTo/scrollIntoView do JS ignora o CSS. Aqui a intenção é respeitada.
   */
  const rolagem = () => {
    try { return document.documentElement.classList.contains('tv') ? 'auto' : 'smooth'; }
    catch (_) { return 'smooth'; }
  };
  window.HP_rolagem = rolagem;   // app.js usa a mesma decisão nos scrolls dele

  function aoMudarFoco(el) {
    const sb = document.getElementById('sidebar');
    // Expande a sidebar ao focar QUALQUER item dela (menu OU o botão de perfil).
    if (sb) sb.classList.toggle('expandida', !!(el.closest && el.closest('#sidebar')));
    if (aoFocarCb) { try { aoFocarCb(el); } catch (_) {} }
  }

  function setFocus(el) {
    if (!el) return;
    if (atual) atual.classList.remove('is-focused');
    atual = el;
    el.classList.add('is-focused');
    aoMudarFoco(el);
    // Campos de texto: foco NATIVO p/ digitar (e abrir o teclado on-screen na TV).
    // EXCETO na casca Android (TV Box/Fire TV): lá o foco nativo faz o IME do
    // sistema abrir SOZINHO, só de passar o D-pad pelo campo — e ele cobre o app
    // sem que o Voltar do controle feche. Lá o teclado é o do próprio app e abre
    // no Enter (ver abrirTeclado em app.js).
    const androidTv = (function () { try { return !!window.HeroPlayAndroid; } catch (_) { return false; } })();
    if ((el.tagName === 'INPUT' || el.tagName === 'TEXTAREA') && !androidTv) {
      try { el.focus({ preventScroll: true }); } catch (_) { el.focus(); }
    } else if (document.activeElement && document.activeElement.blur) {
      document.activeElement.blur();
    }
    // Pôster e TÍTULO de trilho têm scroll próprio (focarPoster/focarTrilho:
    // fila + trilho sob o hero fixo) — o 'nearest' daqui encostaria o título no
    // topo do #conteudo, ou seja, escondido DEBAIXO do hero.
    // 'nearest' (não 'center'): só rola se o item NÃO estiver visível, e o mínimo
    // — assim focar uma tecla já visível não "desce a tela"; só rola onde há
    // overflow real (ex.: menu de categorias).
    if (!el.classList.contains('poster') && !el.classList.contains('trilho-titulo')) {
      el.scrollIntoView({ block: 'nearest', inline: 'nearest', behavior: rolagem() });
    }
  }

  function melhorCandidato(dir) {
    if (!atual) return null;
    const ar = rect(atual);
    const a = centro(ar);
    const vertical = dir === 'up' || dir === 'down';
    let melhor = null;
    let melhorScore = Infinity;

    for (const el of focaveis()) {
      if (el === atual) continue;
      const rr = rect(el);
      const c = centro(rr);
      const dx = c.x - a.x;
      const dy = c.y - a.y;
      let avanco, desvio, overlap;
      switch (dir) {
        // overlap = sobreposicao no eixo CRUZADO (vertical p/ ←/→, horizontal p/ ↑/↓).
        case 'right': if (dx <= 1) continue; avanco = dx; desvio = Math.abs(dy);
          overlap = Math.min(ar.bottom, rr.bottom) - Math.max(ar.top, rr.top); break;
        case 'left':  if (dx >= -1) continue; avanco = -dx; desvio = Math.abs(dy);
          overlap = Math.min(ar.bottom, rr.bottom) - Math.max(ar.top, rr.top); break;
        case 'down':  if (dy <= 1) continue; avanco = dy; desvio = Math.abs(dx);
          overlap = Math.min(ar.right, rr.right) - Math.max(ar.left, rr.left); break;
        case 'up':    if (dy >= -1) continue; avanco = -dy; desvio = Math.abs(dx);
          overlap = Math.min(ar.right, rr.right) - Math.max(ar.left, rr.left); break;
      }
      const mesmaArea = areaDe(el) === areaDe(atual);
      let score;
      if (vertical) {
        // Vertical so navega DENTRO da mesma area (sidebar OU conteudo) — sem isso
        // o ↓/↑ vazava da sidebar (expandida, sobreposta) para o conteudo.
        if (!mesmaArea) continue;
        // PREFERE a mesma coluna (overlap horizontal). Mas sem nenhuma coluna
        // alinhada (ex.: trilho/elenco rolado p/ a direita) NAO trava: cai p/ o
        // item mais proximo acima/abaixo — assim ↑ SEMPRE sobe p/ a secao de cima.
        score = avanco + desvio * 0.3 + (overlap > 0 ? 0 : 1e6);
      } else {
        // Horizontal: na MESMA area so anda na MESMA LINHA (overlap vertical) — ao
        // chegar no limite da linha o foco FICA (nao pula p/ outra secao/linha de
        // baixo). Entre areas (conteudo↔sidebar) e livre (entrar/sair do menu).
        if (mesmaArea && overlap <= 0) continue;
        score = avanco + desvio * 3;
      }
      if (score < melhorScore) { melhorScore = score; melhor = el; }
    }
    return melhor;
  }

  function mover(dir) {
    // Config: da ESQUERDA no painel de detalhe, se NÃO houver vizinho à esquerda
    // dentro do próprio painel, volta ao item de seção SELECIONADO (não ao vizinho
    // geométrico) — preserva a seção escolhida. Se houver vizinho no painel (ex.:
    // toggle + "Definir PIN" na mesma linha), anda normalmente.
    if (dir === 'left' && atual && atual.closest && atual.closest('.cfg-pane')) {
      const cand = melhorCandidato('left');
      if (!(cand && cand.closest && cand.closest('.cfg-pane'))) {
        if (typeof configVoltarSelecao === 'function' && configVoltarSelecao()) return;
      }
    }
    let alvo = melhorCandidato(dir);
    // Ao voltar do conteudo para o menu lateral (seta esquerda), focar SEMPRE a
    // seção ativa — nao o item geometricamente mais proximo.
    if (alvo && dir === 'left' && areaDe(atual) !== 'side' && areaDe(alvo) === 'side') {
      alvo = document.querySelector('.nav-item.ativo') || alvo;
    }
    if (alvo) setFocus(alvo);
  }

  // Enter. Com PROTEÇÃO contra disparo duplo: no controle de TV é comum o OK
  // registrar dois eventos (ou o usuário apertar rápido duas vezes), e aí abria
  // DOIS overlays de detalhe empilhados, ou dois streams de canal em sequência.
  // Uma janela curta por elemento resolve sem atrasar nada perceptível: o 1º
  // toque age na hora, o eco é engolido.
  let _ultAtivar = 0, _ultAlvo = null;
  const ATIVAR_MIN_MS = 400;
  function ativar() {
    if (!atual) return;
    const agora = Date.now();
    if (atual === _ultAlvo && agora - _ultAtivar < ATIVAR_MIN_MS) return;
    _ultAtivar = agora; _ultAlvo = atual;
    atual.click();
  }

  function focarPrimeiro(selector) {
    const el = selector
      ? document.querySelector(selector)
      : focaveis()[0];
    if (el) setFocus(el);
  }

  // Foca o item de menu ativo (usado no "voltar").
  function focarMenu() {
    const el = document.querySelector('.nav-item.ativo') ||
               document.querySelector('.nav-item');
    if (el) setFocus(el);
  }

  // "Voltar": sobe UM nível — modal aberto fecha; dentro do conteúdo de uma seção
  // volta à SELEÇÃO de seção (não à sidebar); na seleção de seção, aí sim vai à
  // sidebar. Vale p/ Configurações e p/ TV ao vivo (categorias/canais/preview).
  // NA RAIZ (sidebar, seção Início) o Voltar pergunta se quer SAIR do app — as
  // lojas LG/Samsung exigem que o Back na raiz devolva ao launcher (ver
  // confirmarSairApp em app.js). Fora do Início, o Voltar leva ao Início 1º.
  let _ultimoVoltar = 0;
  function voltar() {
    // Anti-duplo: no webOS o Back pode chegar por keydown E por popstate quase ao
    // mesmo tempo — sem isto o "voltar" pularia 2 níveis / fecharia o modal de sair.
    const agora = Date.now();
    if (agora - _ultimoVoltar < 250) return;
    _ultimoVoltar = agora;
    const modal = modalTopo();
    if (modal && typeof modal._onVoltar === 'function') { modal._onVoltar(); return; }
    if (atual && atual.closest) {
      // Config: dentro do painel → volta ao menu de seções (item selecionado).
      if (atual.closest('.cfg-pane')) {
        if (typeof configVoltarSelecao === 'function' && configVoltarSelecao()) return;
      }
      // TV ao vivo: preview/EPG → lista de canais (canal selecionado).
      if (atual.closest('.tv-col-dir')) {
        const pane = document.getElementById('tv-pane-canais');
        const canal = pane && (pane.querySelector('.tv-canal-main.sel') || pane.querySelector('.tv-canal-main'));
        if (canal) { setFocus(canal); return; }
      }
      // TV ao vivo: lista de canais → categorias (categoria selecionada).
      if (atual.closest('.tv-pane-canais')) {
        if (typeof mostrarCategorias === 'function') { mostrarCategorias(); return; }
      }
    }
    // Foco no CONTEÚDO (não na sidebar) → recolhe p/ a sidebar (1º nível).
    const naSidebar = atual && atual.closest && atual.closest('#sidebar');
    if (!naSidebar) { focarMenu(); return; }
    // Já na sidebar. Se NÃO está no Início → vai p/ o Início.
    const secao = document.querySelector('.nav-item.ativo');
    const ehInicio = secao && secao.dataset && secao.dataset.secao === 'inicio';
    if (!ehInicio) {
      if (typeof navegar === 'function') { navegar('inicio'); focarMenu(); return; }
    }
    // Raiz de verdade (sidebar + Início) → pergunta se quer sair do app.
    if (typeof confirmarSairApp === 'function') { confirmarSairApp(); return; }
    focarMenu();
  }

  // Limite de velocidade da troca de foco: segurando o D-pad, o firmware repete o
  // keydown muito rápido — sem limite o foco "voa", os banners não carregam e o
  // hero de destaque trava. Limitamos a ~1 troca a cada MOVER_MIN_MS (contínuo,
  // porém devagar o bastante p/ carregar). A 1ª pressão (após pausa) passa direto.
  let _ultimoMover = 0;
  const MOVER_MIN_MS = 150;
  function moverThrottle(dir) {
    const agora = Date.now();
    if (agora - _ultimoMover < MOVER_MIN_MS) return;   // engole a repetição rápida
    _ultimoMover = agora;
    mover(dir);
  }

  window.addEventListener('keydown', (e) => {
    // Campo de texto focado (teclado NATIVO da TV ativo): não sequestrar o
    // Backspace nem o Enter — deixar o input APAGAR/confirmar. Só o Back do
    // controle sai do campo.
    const foco = document.activeElement;
    const emTexto = foco && (foco.tagName === 'INPUT' || foco.tagName === 'TEXTAREA');
    // Botão VOLTAR do controle: webOS = keyCode 461, Tizen = 10009. Dependendo do
    // firmware vem como e.key 'Back'/'BrowserBack'/'XF86Back'/'GoBack' — ou, no
    // navegador/teclado, 'Backspace' (mas Backspace NUM CAMPO = apagar, não voltar).
    if (e.keyCode === 461 || e.keyCode === 10009 ||
        e.key === 'Back' || e.key === 'BrowserBack' || e.key === 'XF86Back' || e.key === 'GoBack' ||
        (e.key === 'Backspace' && !emTexto)) {
      e.preventDefault(); voltar(); return;
    }
    if (emTexto && (e.key === 'Backspace' || e.key === 'Delete' || e.key === 'Enter')) return; // deixa o input tratar
    switch (e.key) {
      case 'ArrowRight': e.preventDefault(); moverThrottle('right'); break;
      case 'ArrowLeft':  e.preventDefault(); moverThrottle('left'); break;
      case 'ArrowDown':  e.preventDefault(); moverThrottle('down'); break;
      case 'ArrowUp':    e.preventDefault(); moverThrottle('up'); break;
      case 'Enter':      e.preventDefault(); if (!e.repeat) ativar(); break;
    }
  });

  return {
    setFocus, focarPrimeiro, focarMenu, voltar, refresh: () => atual,
    aoFocar: (fn) => { aoFocarCb = fn; },
    get atual() { return atual; },
  };
})();
