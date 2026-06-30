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
    if (top && top.classList.contains('busca-secao')) {
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
    return 'main';
  };

  let aoFocarCb = null; // callback externo (ex.: atualizar hero ao focar poster)

  function aoMudarFoco(el) {
    const sb = document.getElementById('sidebar');
    if (sb) sb.classList.toggle('expandida', el.classList.contains('nav-item'));
    if (aoFocarCb) { try { aoFocarCb(el); } catch (_) {} }
  }

  function setFocus(el) {
    if (!el) return;
    if (atual) atual.classList.remove('is-focused');
    atual = el;
    el.classList.add('is-focused');
    aoMudarFoco(el);
    // Campos de texto: foco NATIVO p/ digitar (e abrir o teclado on-screen na TV).
    if (el.tagName === 'INPUT' || el.tagName === 'TEXTAREA') {
      try { el.focus({ preventScroll: true }); } catch (_) { el.focus(); }
    } else if (document.activeElement && document.activeElement.blur) {
      document.activeElement.blur();
    }
    // Pôster tem scroll próprio (focarPoster: fila + título sob o hero fixo).
    // 'nearest' (não 'center'): só rola se o item NÃO estiver visível, e o mínimo
    // — assim focar uma tecla já visível não "desce a tela"; só rola onde há
    // overflow real (ex.: menu de categorias).
    if (!el.classList.contains('poster')) {
      el.scrollIntoView({ block: 'nearest', inline: 'nearest', behavior: 'smooth' });
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
    let alvo = melhorCandidato(dir);
    // Ao voltar do conteudo para o menu lateral (seta esquerda), focar SEMPRE a
    // seção ativa — nao o item geometricamente mais proximo.
    if (alvo && dir === 'left' && areaDe(atual) !== 'side' && areaDe(alvo) === 'side') {
      alvo = document.querySelector('.nav-item.ativo') || alvo;
    }
    if (alvo) setFocus(alvo);
  }

  function ativar() {
    if (atual) atual.click();
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

  // "Voltar": se um modal estiver aberto, fecha-o (via _onVoltar); senao, menu.
  function voltar() {
    const modal = modalTopo();
    if (modal && typeof modal._onVoltar === 'function') { modal._onVoltar(); return; }
    focarMenu();
  }

  window.addEventListener('keydown', (e) => {
    switch (e.key) {
      case 'ArrowRight': e.preventDefault(); mover('right'); break;
      case 'ArrowLeft':  e.preventDefault(); mover('left'); break;
      case 'ArrowDown':  e.preventDefault(); mover('down'); break;
      case 'ArrowUp':    e.preventDefault(); mover('up'); break;
      case 'Enter':      e.preventDefault(); ativar(); break;
      // Voltar do controle: webOS=461 / Tizen=10009 chegam como 'Backspace' aqui
      case 'Backspace':  e.preventDefault(); voltar(); break;
    }
  });

  return {
    setFocus, focarPrimeiro, focarMenu, refresh: () => atual,
    aoFocar: (fn) => { aoFocarCb = fn; },
    get atual() { return atual; },
  };
})();
