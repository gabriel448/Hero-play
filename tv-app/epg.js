/* ============================================================================
   Hero Play TV — EPG (guia de programação) a partir do XMLTV do Xtream.

   Fonte: `xmltv.php` do provedor (URL em Dispositivo.registro().epg_url, ou
   derivada de lista_url via ListaUtil.derivarEpg). Baixa 1x, parseia <channel> e
   <programme> por regex, e casa cada canal da lista por **tvg-id** e, como
   fallback, por **nome** (<display-name>). Sem EPG/CORS/erro/sem-casar → fallback.
   ============================================================================ */
const EPG = (() => {
  let _prog = {};            // idXmltv(minúsculo) -> [{ ini, fim, titulo }] (ordenado)
  let _idPorNome = {};       // nome normalizado -> idXmltv (do <display-name>)
  let _urlCarregada = '';
  let _carregando = null;

  // "20260708190000 -0300" | "...+0000" | "20260708190000" → ms epoch
  function _ts(s) {
    const m = /(\d{4})(\d{2})(\d{2})(\d{2})(\d{2})(\d{2})(?:\s*([+-]\d{4}))?/.exec(s || '');
    if (!m) return 0;
    let t = Date.UTC(+m[1], +m[2] - 1, +m[3], +m[4], +m[5], +m[6]);
    if (m[7]) { const sinal = m[7][0] === '-' ? -1 : 1; t -= sinal * ((+m[7].slice(1, 3)) * 60 + (+m[7].slice(3, 5))) * 60000; }
    return t;
  }
  const _dec = (s) => (s || '').replace(/<!\[CDATA\[([\s\S]*?)\]\]>/g, '$1')
    .replace(/&lt;/g, '<').replace(/&gt;/g, '>').replace(/&quot;/g, '"')
    .replace(/&#3[49];|&apos;/g, "'").replace(/&amp;/g, '&').trim();
  // Normaliza nome de canal p/ casar (sem acento, minúsculo, sem qualidade/pontuação).
  const _norm = (s) => (s || '').normalize('NFD').replace(/[̀-ͯ]/g, '')
    .toLowerCase().replace(/[^a-z0-9]+/g, ' ')
    .replace(/\b(hd|fhd|uhd|sd|4k|h265|h264|fullhd|full)\b/g, '').replace(/\s+/g, ' ').trim();

  // Parse FATIADO NO TEMPO: um EPG completo tem dezenas de milhares de <programme>.
  // Parsear tudo de uma vez trava a UI por segundos na TV. Processamos em lotes,
  // cedendo o event loop a cada ~12ms → a UI continua fluida enquanto carrega.
  function _parse(xml, canais) {
    return new Promise((resolve) => {
      _prog = {}; _idPorNome = {};
      // 1) <channel id> → display-name (p/ casar por nome) — loop menor, síncrono.
      const reCh = /<channel\b[^>]*\bid="([^"]*)"[^>]*>([\s\S]*?)<\/channel>/g;
      let mc;
      while ((mc = reCh.exec(xml))) {
        const id = mc[1].toLowerCase();
        const nm = _dec((/<display-name\b[^>]*>([\s\S]*?)<\/display-name>/.exec(mc[2]) || [])[1]);
        const k = _norm(nm);
        if (k && !(k in _idPorNome)) _idPorNome[k] = id;
      }
      // 2) ids que nos interessam (tvg-id direto OU nome casado)
      const alvo = new Set();
      for (const c of (canais || [])) {
        const a = String(c.tvgId || '').toLowerCase(); if (a) alvo.add(a);
        const byN = _idPorNome[_norm(c.nome)]; if (byN) alvo.add(byN);
      }
      const filtrar = alvo.size > 0;
      // 3) <programme channel> → programas, EM LOTES (cede a UI a cada ~12ms).
      const reP = /<programme\b([^>]*)>([\s\S]*?)<\/programme>/g;
      function lote() {
        const t0 = Date.now();
        let m;
        while ((m = reP.exec(xml))) {
          const ch = (/channel="([^"]*)"/.exec(m[1]) || [])[1];
          if (ch) {
            const key = ch.toLowerCase();
            if (!(filtrar && !alvo.has(key))) {
              const tit = _dec((/<title\b[^>]*>([\s\S]*?)<\/title>/.exec(m[2]) || [])[1]);
              if (tit) (_prog[key] = _prog[key] || []).push({
                ini: _ts((/start="([^"]*)"/.exec(m[1]) || [])[1]),
                fim: _ts((/stop="([^"]*)"/.exec(m[1]) || [])[1]),
                titulo: tit,
              });
            }
          }
          if (Date.now() - t0 > 12) { setTimeout(lote, 0); return; }   // cede o event loop
        }
        for (const k in _prog) _prog[k].sort((a, b) => a.ini - b.ini);
        console.log('[EPG] parse:', Object.keys(_idPorNome).length, 'canais no XMLTV ·', Object.keys(_prog).length, 'casados');
        resolve();
      }
      lote();
    });
  }

  function carregar(url, canais) {
    if (!url) return Promise.resolve(false);
    if (_urlCarregada === url && Object.keys(_prog).length) return Promise.resolve(true);
    if (_carregando) return _carregando;
    console.log('[EPG] baixando', url);
    _carregando = fetch(url).then((r) => { if (!r.ok) throw new Error('HTTP ' + r.status); return r.text(); })
      .then((txt) => {
        console.log('[EPG] baixado', txt.length, 'chars');
        return _parse(txt, canais).then(() => { _urlCarregada = url; return Object.keys(_prog).length > 0; });
      })
      .catch((e) => { console.warn('[EPG] falha:', e && e.message || e); return false; })
      .finally(() => { _carregando = null; });
    return _carregando;
  }

  // Resolve o id XMLTV de um canal: por tvg-id, senão por nome (display-name).
  function _lista(canal) {
    if (!canal) return [];
    const a = String(canal.tvgId || '').toLowerCase();
    if (a && _prog[a]) return _prog[a];
    const byN = _idPorNome[_norm(canal.nome)];
    return (byN && _prog[byN]) ? _prog[byN] : [];
  }
  function agora(canal) {
    const now = Date.now(), l = _lista(canal);
    for (let i = 0; i < l.length; i++) if (l[i].ini <= now && now < l[i].fim) return { atual: l[i], prox: l[i + 1] || null };
    return { atual: null, prox: l.find((p) => p.ini > now) || null };
  }
  function proximos(canal, n) {
    const now = Date.now();
    return _lista(canal).filter((p) => p.fim > now).slice(0, n || 6);
  }
  const temEpg = () => Object.keys(_prog).length > 0;

  return { carregar, agora, proximos, temEpg };
})();