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
  // Se houver um modal (.nav-modal) aberto, navega SO dentro dele.
  const focaveis = () => {
    const escopo = document.querySelector('.nav-modal') || document;
    return [...escopo.querySelectorAll('.focusable')].filter(visivel);
  };
  const rect = (el) => el.getBoundingClientRect();
  const centro = (r) => ({ x: r.left + r.width / 2, y: r.top + r.height / 2 });
  // "Area" do elemento: menu lateral x conteudo. Usado para NAO deixar o foco
  // vertical vazar entre os dois (a sidebar expandida sobrepoe o conteudo).
  const areaDe = (el) => (el.closest && el.closest('#sidebar')) ? 'side' : 'main';

  function aoMudarFoco(el) {
    const sb = document.getElementById('sidebar');
    if (sb) sb.classList.toggle('expandida', el.classList.contains('nav-item'));
  }

  function setFocus(el) {
    if (!el) return;
    if (atual) atual.classList.remove('is-focused');
    atual = el;
    el.classList.add('is-focused');
    aoMudarFoco(el);
    el.scrollIntoView({ block: 'center', inline: 'center', behavior: 'smooth' });
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
      let avanco, desvio;
      switch (dir) {
        case 'right': if (dx <= 1) continue; avanco = dx; desvio = Math.abs(dy); break;
        case 'left':  if (dx >= -1) continue; avanco = -dx; desvio = Math.abs(dy); break;
        case 'down':  if (dy <= 1) continue; avanco = dy; desvio = Math.abs(dx); break;
        case 'up':    if (dy >= -1) continue; avanco = -dy; desvio = Math.abs(dx); break;
      }
      // Movimentos VERTICAIS (cima/baixo) exigem SOBREPOSICAO HORIZONTAL: assim
      // o foco so vai para itens na MESMA coluna. Sem item alinhado abaixo/acima,
      // melhorCandidato retorna null e o foco FICA PRESO (nao pula de coluna nem
      // volta ao menu lateral).
      if (vertical) {
        // Vertical so navega DENTRO da mesma area (sidebar OU conteudo) e em
        // colunas alinhadas (overlap horizontal). Sem isso, o ↓/↑ vazava da
        // sidebar (expandida, sobreposta) para o conteudo, fechando o menu.
        if (areaDe(el) !== areaDe(atual)) continue;
        const overlap = Math.min(ar.right, rr.right) - Math.max(ar.left, rr.left);
        if (overlap <= 0) continue;
      }
      const score = avanco + desvio * (vertical ? 0.3 : 3);
      if (score < melhorScore) { melhorScore = score; melhor = el; }
    }
    return melhor;
  }

  function mover(dir) {
    const alvo = melhorCandidato(dir);
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
    const modal = document.querySelector('.nav-modal');
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

  return { setFocus, focarPrimeiro, focarMenu, refresh: () => atual, get atual() { return atual; } };
})();
