/* ============================================================================
   Parser + organização de lista — PORTADO do app mobile (Flutter):
     lib/services/parser_m3u.dart · agrupador_canais.dart · utils/qualidade.dart
     · models/serie.dart
   Pipeline:
     1. parse M3U -> canais {nome,url,logo,grupo,tvgId,tipo}
     2. classifica VOD (filme/série) x AO VIVO (mesma heurística do mobile)
     3. AO VIVO: agrupa por categoria, funde variantes de QUALIDADE e FONTES
        alternativas num único canal (canal.variantes / canal.fontes)
     4. VOD: separa filmes puros de SÉRIES (agrupa episódios SxxExx)
   Tudo local. URL/EPG nunca sobem daqui.
   ============================================================================ */
const Lista = (() => {
  // ── Qualidade (utils/qualidade.dart) ──────────────────────────────────────
  const _reUhd = /\b(4K|UHD|2160P?|ULTRA\s?HD)\b/i;
  const _reFhd = /\b(FHD|FULL\s?HD|1080P?)\b/i;
  const _reHd = /\b(HD|HDTV|720P?)\b/i;
  const _reSd = /\b(SD|480P?|360P?)\b/i;
  const _reTags = /\b(4K|UHD|2160P?|ULTRA\s?HD|FHD|FULL\s?HD|1080P?|HDTV|HD|720P?|SD|480P?|360P?|H\.?265|HEVC|H\.?264|AVC)\b/gi;
  const _reParen = /[\[\]\(\)]/g;
  const _reEsp = /\s+/g;
  const _reBordas = /^[\s\-|•·:]+|[\s\-|•·:]+$/g;
  const _reSobre = /[²³¹⁰-⁹ᴬ-ᵫ]+$/;
  const _reBR = /\s+BR$/i;

  function detectarQualidade(t) {
    if (_reUhd.test(t)) return { rank: 4, rotulo: '4K' };
    if (_reFhd.test(t)) return { rank: 3, rotulo: 'FHD' };
    if (_reHd.test(t)) return { rank: 2, rotulo: 'HD' };
    if (_reSd.test(t)) return { rank: 1, rotulo: 'SD' };
    return { rank: 0, rotulo: 'Padrão' };
  }
  function semTags(t) {
    let s = (t || '').replace(_reTags, ' ').replace(_reParen, ' ').replace(_reEsp, ' ').replace(_reBordas, '');
    return s.trim() === '' ? (t || '').trim() : s;
  }
  const nomeBase = (n) => semTags(n);
  const categoriaBase = (g) => semTags(g);
  function nomeFonte(nome) {
    let s = nomeBase(nome);
    const ast = s.includes('*');
    s = s.replace(/\*+/g, '').trim();
    if (ast) s = s.replace(/\s+\d+$/, '').trim();
    s = s.replace(_reSobre, '').trim().replace(_reBR, '').trim();
    return s === '' ? nomeBase(nome) : s;
  }
  function temMarcadorBackup(nome) {
    const b = nomeBase(nome).trim();
    return b.includes('*') || _reSobre.test(b) || _reBR.test(b);
  }

  // ── Parse M3U (parser_m3u.dart) ────────────────────────────────────────────
  const EXT_FILME = ['.mp4', '.mkv', '.avi', '.mov', '.flv', '.wmv', '.webm', '.m4v'];

  // VOD x AO VIVO pela URL (confiável no Xtream): VOD tem /movie/ ou /series/ no
  // path, ou termina em extensão de vídeo. O resto é AO VIVO — mesmo que o grupo
  // se chame "FILMES" (ex.: "GLOBOSAT FILMES" é categoria de CANAIS de filme,
  // não VOD). Por isso NÃO usamos palavra do group-title aqui: dava falso
  // positivo (Telecine/TC Premium caíam em Filmes).
  function classificarTipo(url) {
    const u = url.toLowerCase().split('?')[0];
    if (u.includes('/movie/') || u.includes('/series/')) return 'filme';
    for (const e of EXT_FILME) if (u.endsWith(e)) return 'filme';
    return 'live';
  }
  function parseExtinf(ln) {
    // Vírgula separadora = a 1ª FORA de aspas. Valores de atributo (ex.:
    // tvg-name="MEU FILHO, NOSSO MUNDO") podem ter vírgula — um indexOf(',')
    // simples quebrava no meio do atributo e jogava o resto da linha no nome.
    let i = -1, dentro = false;
    for (let k = 0; k < ln.length; k++) {
      const ch = ln[k];
      if (ch === '"') dentro = !dentro;
      else if (ch === ',' && !dentro) { i = k; break; }
    }
    let nome = 'Sem nome', antes = ln;
    if (i !== -1) { nome = ln.slice(i + 1).trim(); antes = ln.slice(0, i); }
    const attrs = {};
    const re = /([\w-]+)="([^"]*)"/g;
    let m;
    while ((m = re.exec(antes))) attrs[m[1].toLowerCase()] = m[2];
    return { nome, logo: attrs['tvg-logo'] || '', grupo: attrs['group-title'] || '', tvgId: attrs['tvg-id'] || '' };
  }
  function parseM3U(texto) {
    const linhas = (texto || '').split(/\r?\n/);
    const canais = [];
    let cur = null;
    for (const raw of linhas) {
      const ln = raw.trim();
      if (!ln || ln.startsWith('#EXTM3U')) continue;
      if (ln.startsWith('#EXTINF:')) { cur = parseExtinf(ln); continue; }
      if (ln.startsWith('#')) continue;
      if (cur) {
        const grupo = (cur.grupo && cur.grupo.trim()) ? cur.grupo : 'Sem categoria';
        canais.push({ nome: cur.nome, url: ln, logo: cur.logo, grupo, tvgId: cur.tvgId, tipo: classificarTipo(ln) });
        cur = null;
      }
    }
    return canais;
  }

  // ── Agrupamento AO VIVO (agrupador_canais.dart) ────────────────────────────
  function montarCanal(cat, variantesRaw) {
    if (variantesRaw.length === 1) {
      const u = variantesRaw[0];
      return { nome: nomeBase(u.nome) || u.nome, url: u.url, logo: u.logo, grupo: cat, tvgId: u.tvgId, variantes: [] };
    }
    const ord = [...variantesRaw].sort((a, b) => detectarQualidade(b.nome).rank - detectarQualidade(a.nome).rank);
    const melhor = ord[0];
    const base = nomeBase(melhor.nome) || melhor.nome;
    const comLogo = ord.find((v) => v.logo) || melhor;
    return {
      nome: base, url: melhor.url, logo: comLogo.logo, grupo: cat, tvgId: melhor.tvgId,
      variantes: ord.map((v) => ({ rotulo: detectarQualidade(v.nome).rotulo, url: v.url })),
    };
  }
  function montarFontes(fontes) {
    if (fontes.length === 1) return fontes[0];
    const ord = [...fontes].sort((a, b) => {
      const ap = !temMarcadorBackup(a.nome), bp = !temMarcadorBackup(b.nome);
      if (ap && !bp) return -1;
      if (!ap && bp) return 1;
      return a.nome.length - b.nome.length;
    });
    const principal = ord[0];
    const comLogo = ord.find((f) => f.logo) || principal;
    return {
      ...principal, logo: comLogo.logo,
      fontes: ord.map((f) => ({ nome: f.nome, url: f.url, variantes: f.variantes || [] })),
    };
  }
  function agruparAoVivo(canais) {
    const mapa = {}, ordemCat = [], ordemCanal = {};
    for (const c of canais) {
      const cat = categoriaBase(c.grupo) || 'Sem categoria';
      const chave = nomeBase(c.nome).toLowerCase();
      if (!mapa[cat]) { mapa[cat] = {}; ordemCat.push(cat); ordemCanal[cat] = []; }
      if (!mapa[cat][chave]) { mapa[cat][chave] = []; ordemCanal[cat].push(chave); }
      mapa[cat][chave].push(c);
    }
    const porCat = {};
    for (const cat of ordemCat) porCat[cat] = ordemCanal[cat].map((ch) => montarCanal(cat, mapa[cat][ch]));
    // 2º passo: funde fontes alternativas.
    const result = {};
    for (const cat of ordemCat) {
      const grupos = {}, ordem = [];
      for (const c of porCat[cat]) {
        const ch = nomeFonte(c.nome).toLowerCase();
        if (!grupos[ch]) { grupos[ch] = []; ordem.push(ch); }
        grupos[ch].push(c);
      }
      result[cat] = ordem.map((ch) => montarFontes(grupos[ch]));
    }
    return result;
  }

  // ── Séries (models/serie.dart) ─────────────────────────────────────────────
  const _reEp = /\bS(\d{1,2})\s?E(\d{1,3})\b/i;
  const _reEp2 = /\b(\d{1,2})x(\d{2,3})\b/;
  function limparNomeSerie(nome) {
    return nome
      .replace(/[\[\(][A-Za-z]{2,5}(?:[\-\s][A-Za-z]{2,3})?[\]\)]/g, '')
      .replace(/[\[\(](?:\d{3,4}[pi]|4K|HD|FHD|UHD)[\]\)]/gi, '')
      .replace(/[\[\(]\d{4}[\]\)]/g, '')
      .replace(/[._]/g, ' ').replace(/\s+/g, ' ').trim();
  }
  function nomeSerie(nome) {
    const m = nome.match(_reEp) || nome.match(_reEp2);
    if (!m) return null;
    const raw = nome.slice(0, m.index).trim().replace(/[-–:|\s]+$/, '').trim();
    const n = limparNomeSerie(raw);
    return n || null;
  }
  const seasonOf = (n) => { const m = n.match(_reEp) || n.match(_reEp2); return m ? (parseInt(m[1]) || 0) : 0; };
  const episodeOf = (n) => { const m = n.match(_reEp) || n.match(_reEp2); return m ? (parseInt(m[2]) || 0) : 0; };
  function agruparVod(vod) {
    const filmes = [], map = {};
    for (const c of vod) {
      const nome = nomeSerie(c.nome);
      if (!nome) { filmes.push(c); continue; }
      if (!map[nome]) map[nome] = { nome, grupo: c.grupo, logo: '', eps: [] };
      map[nome].eps.push(c);
      if (!map[nome].logo && c.logo) map[nome].logo = c.logo;
    }
    const series = Object.values(map).map((b) => {
      b.eps.sort((a, z) => { const sa = seasonOf(a.nome), sz = seasonOf(z.nome); return sa !== sz ? sa - sz : episodeOf(a.nome) - episodeOf(z.nome); });
      return b;
    }).sort((a, b) => a.nome.localeCompare(b.nome));
    return { filmes, series };
  }

  // ── Ordenação de categorias (popularidade_categorias.dart + lançamentos) ────
  const _regras = [
    [1, ['ESPORTE']], [2, ['ESPORTE', 'PAYPERVIEW']], [2, ['ESPORTE', 'PPV']],
    [3, ['PREMIERE', 'ESPORTE']], [4, ['ABERTO']], [5, ['SPORTS', 'WORLD']],
    [6, ['UFC']], [6, ['BJJ']],
    [10, ['GLOBO', 'CAPITAI']], [11, ['GLOBO', 'SUDESTE']], [12, ['GLOBO', 'SUL']],
    [13, ['GLOBO', 'NORDESTE']], [14, ['GLOBO', 'NORTE']], [15, ['GLOBO', 'CENTRO']],
    [16, ['GLOBO']], [17, ['HBO', 'MAX', 'PPV']], [18, ['HBO']], [19, ['RECORD']],
    [20, ['SBT']], [21, ['BAND']],
    [30, ['ESTADOS', 'UNIDOS']], [30, ['EUA']], [31, ['ESPECIAI', '24']],
    [32, ['NOTICIA']], [33, ['VARIEDADE']], [34, ['PARAMOUNT']], [35, ['PRIME', 'VIDEO']],
    [36, ['DISNEY']], [37, ['DESENHO']], [38, ['INFANTI']], [38, ['KIDS']],
    [39, ['DOCUMENT']], [40, ['PORTUGAL']], [41, ['CANADA']], [42, ['ANIME']],
    [43, ['LEGENDADO']], [44, ['CLIP', 'MUSICA']], [45, ['MUSICA']], [45, ['MUSIC']],
    [46, ['RELIGIO']], [46, ['GOSPEL']],
    [60, ['YOUTUBER']], [61, ['CASA', 'PATRAO']], [62, ['LATINO']], [63, ['ESTADUA']], [64, ['EUROPA']],
  ].sort((a, b) => b[1].length - a[1].length); // mais específicas primeiro
  const NAO_RANK = 9999;
  const _semAcento = (s) => s.normalize('NFD').replace(/[̀-ͯ]/g, '');
  // Normaliza p/ tokens de popularidade: maiúsculo, só letras/dígitos.
  const _normCat = (s) => _semAcento(s || '').toUpperCase().replace(/[^A-Z0-9]/g, '');
  function rankPopularidade(nome) {
    const n = _normCat(nome);
    for (const [pos, tokens] of _regras) if (tokens.every((t) => n.includes(_normCat(t)))) return pos;
    return NAO_RANK;
  }
  function ordenarPorPopularidade(nomes) {
    return [...nomes].sort((a, b) => {
      const ra = rankPopularidade(a), rb = rankPopularidade(b);
      return ra !== rb ? ra - rb : a.toLowerCase().localeCompare(b.toLowerCase());
    });
  }
  // Lançamentos: normaliza mantendo espaços (p/ casar "em alta").
  const _normVod = (s) => _semAcento((s || '').toLowerCase());
  const _kwLancamento = ['lanca', 'cinema', 'estreia', 'cartaz', 'em alta'];
  const ehLancamento = (nome) => { const n = _normVod(nome); return _kwLancamento.some((k) => n.includes(k)); };

  // ── Catálogo ──────────────────────────────────────────────────────────────
  // Filmes/Séries: categorias A-Z, com LANÇAMENTOS primeiro (igual ao mobile).
  function trilhosPorGrupo(itens) {
    const g = {};
    for (const i of itens) { const k = (i.generos && i.generos[0]) || 'Outros'; (g[k] || (g[k] = [])).push(i); }
    const nomes = Object.keys(g).sort((a, b) => a.toLowerCase().localeCompare(b.toLowerCase()));
    const ordenadas = [...nomes.filter(ehLancamento), ...nomes.filter((n) => !ehLancamento(n))];
    return ordenadas.map((titulo) => ({
      titulo,
      itens: g[titulo].slice().sort((a, b) => a.titulo.toLowerCase().localeCompare(b.titulo.toLowerCase())).slice(0, 40),
    }));
  }

  function parse(texto) {
    const todos = parseM3U(texto);
    const aoVivoRaw = todos.filter((c) => c.tipo === 'live');
    const vodRaw = todos.filter((c) => c.tipo === 'filme');

    // AO VIVO agrupado -> lista plana (categorias em ordem de POPULARIDADE)
    const porCat = agruparAoVivo(aoVivoRaw);
    const canais = [];
    let num = 100;
    for (const cat of ordenarPorPopularidade(Object.keys(porCat))) {
      for (const c of porCat[cat]) {
        canais.push({
          id: 'c' + canais.length, num: String(++num), nome: c.nome, categoria: cat,
          logo: c.logo, url: c.url, variantes: c.variantes || [], fontes: c.fontes || [],
          agora: '', prox: '', proxIni: '',
        });
      }
    }

    // VOD -> filmes / séries
    const { filmes: fRaw, series: sRaw } = agruparVod(vodRaw);
    const filmes = fRaw.map((c, i) => ({ id: 'f' + i, titulo: c.nome, url: c.url, logo: c.logo, generos: [c.grupo || 'Filmes'], ano: '', nota: 0, sinopse: '', tipo: 'filme' }));
    const series = sRaw.map((s, i) => ({ id: 's' + i, titulo: s.nome, url: (s.eps[0] || {}).url, logo: s.logo, generos: [s.grupo || 'Séries'], episodios: s.eps.map((e) => ({ nome: e.nome, url: e.url })), ano: '', nota: 0, sinopse: '', tipo: 'serie' }));

    const catalogo = {
      inicio: {
        destaque: filmes[0] || series[0] || null,
        trilhos: [
          { titulo: 'Filmes', itens: filmes.slice(0, 18) },
          { titulo: 'Séries', itens: series.slice(0, 18) },
        ].filter((t) => t.itens.length),
      },
      filmes: { destaque: filmes[0] || null, trilhos: trilhosPorGrupo(filmes) },
      series: { destaque: series[0] || null, trilhos: trilhosPorGrupo(series) },
    };
    const indice = {};
    [...filmes, ...series].forEach((i) => { indice[i.id] = i; });
    return { canais, filmes, series, catalogo, indice, total: todos.length };
  }

  return { parse, parseM3U, detectarQualidade };
})();
