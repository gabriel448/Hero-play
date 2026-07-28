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
  // Nome-base p/ fundir FONTES alternativas: remove os marcadores de backup
  // (asterisco "*", superscritos ²³, sufixo " BR") — mas MANTÉM o número do canal
  // (ex.: "SPORTV 2 *" → "SPORTV 2", que agrupa com "SPORTV 2"; antes virava
  // "SPORTV" e ficava órfão). Também tolera "*" grudado/no meio e múltiplos.
  function nomeFonte(nome) {
    let s = nomeBase(nome).replace(/\*+/g, ' ').replace(_reEsp, ' ').trim(); // tira asteriscos
    s = s.replace(_reSobre, '').trim();   // superscrito no fim = backup
    s = s.replace(_reBR, '').trim();      // " BR" no fim = backup
    s = s.replace(_reBordas, '').trim();
    return s === '' ? nomeBase(nome).trim() : s;
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
    // Sem split('?') — ele alocava um array por URL (167k vezes no boot).
    const q = url.indexOf('?');
    const u = (q === -1 ? url : url.slice(0, q)).toLowerCase();
    if (u.indexOf('/movie/') !== -1 || u.indexOf('/series/') !== -1) return 'filme';
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
  // Cede o event loop (mantém a UI viva durante o parse de listas gigantes).
  const _cede = () => new Promise((r) => setTimeout(r, 0));

  async function parseM3U(texto, prog) {
    // Varre linha a linha SEM split(): num M3U de 46 MB o split alocava um array
    // com ~330 mil strings de uma vez (pico de memória + tempo). Aqui só existe
    // uma linha por vez. FATIADO: cede a UI a cada ~12ms e reporta progresso.
    const s = texto || '';
    const n = s.length;
    const canais = [];
    let cur = null, i = 0, cnt = 0, t0 = Date.now();
    while (i < n) {
      let j = s.indexOf('\n', i);
      if (j === -1) j = n;
      let fim = j;
      if (fim > i && s.charCodeAt(fim - 1) === 13) fim--;   // \r\n
      const ln = s.slice(i, fim).trim();
      i = j + 1;
      if (ln && !ln.startsWith('#EXTM3U')) {
        if (ln.startsWith('#EXTINF:')) cur = parseExtinf(ln);
        else if (ln.charCodeAt(0) !== 35 && cur) {          // '#'
          const grupo = (cur.grupo && cur.grupo.trim()) ? cur.grupo : 'Sem categoria';
          canais.push({ nome: cur.nome, url: ln, logo: cur.logo, grupo, tvgId: cur.tvgId, tipo: classificarTipo(ln) });
          cur = null;
        }
      }
      // Checa o relógio só a cada 2048 linhas (Date.now() por linha custaria caro).
      if ((++cnt & 2047) === 0 && Date.now() - t0 > 12) {
        if (prog) prog(i / n);
        await _cede(); t0 = Date.now();
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
  // Chave de ordenação PRÉ-CALCULADA (minúscula, sem acento). Calcular 1x por item
  // e comparar com < / > é ordens de grandeza mais rápido que chamar
  // toLowerCase()+localeCompare() DENTRO do comparador (que roda O(n log n) vezes).
  const _chaveOrd = (s) => (s || '').toLowerCase().normalize('NFD').replace(/[̀-ͯ]/g, '');
  // Ordena um array por chave pré-calculada (decorate–sort–undecorate).
  function _ordenarPorChave(arr, chaveDe) {
    return arr.map((it) => ({ k: chaveDe(it), it }))
      .sort((a, b) => (a.k < b.k ? -1 : a.k > b.k ? 1 : 0))
      .map((x) => x.it);
  }

  async function agruparVod(vod, prog) {
    const filmes = [], filmeVisto = new Set(), map = {};
    const total = vod.length || 1;
    let cnt = 0, t0 = Date.now();
    for (const c of vod) {
      const nome = nomeSerie(c.nome);
      if (!nome) {
        // Dedup de FILMES: a mesma lista traz o mesmo título várias vezes (outra
        // categoria, ou "HD"/"4K"). Sem isto aparecem pôsteres repetidos. A chave
        // é o nome normalizado (minúsculo/sem acento); fica o 1º que aparece.
        const ch = _chaveOrd(c.nome);
        if (filmeVisto.has(ch)) { cnt++; continue; }
        filmeVisto.add(ch); filmes.push(c);
      } else {
        // Séries agrupadas pela chave NORMALIZADA (antes era o nome cru: "Round 6"
        // e "round 6" viravam duas séries). O nome de exibição é o 1º visto.
        const ch = _chaveOrd(nome);
        if (!map[ch]) map[ch] = { nome, grupo: c.grupo, logo: '', eps: [] };
        map[ch].eps.push(c);
        if (!map[ch].logo && c.logo) map[ch].logo = c.logo;
      }
      if ((++cnt & 2047) === 0 && Date.now() - t0 > 12) {
        if (prog) prog(cnt / total);
        await _cede(); t0 = Date.now();
      }
    }
    // ⚠️ NÃO ordenar os episódios aqui: era o maior custo do boot. O comparador
    // chamava seasonOf()/episodeOf() (regex) A CADA COMPARAÇÃO — ~3 MILHÕES de
    // execuções com 144k episódios. O app já ordena sob demanda em epsOrdenados()
    // quando a série é aberta (dezenas de itens = instantâneo).
    const series = _ordenarPorChave(Object.values(map), (b) => _chaveOrd(b.nome));
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

  // ── Recência: "o que acabou de entrar no catálogo" ────────────────────────
  // A lista M3U não traz data de inclusão, e o ANO do título é o ano de
  // lançamento do FILME — não serve. O sinal que existe é o id numérico do
  // stream na URL Xtream (.../movie/user/pass/123456.mp4): o painel do provedor
  // gera ids crescentes, então id maior = entrou depois.
  function idStream(url) {
    const semQuery = (url || '').split('?')[0];
    const ultimo = semQuery.split('/').pop();
    const ponto = ultimo.lastIndexOf('.');
    const n = parseInt(ponto === -1 ? ultimo : ultimo.slice(0, ponto), 10);
    return isNaN(n) ? null : n;
  }
  // Série: usa o MAIOR id entre os episódios (o episódio mais novo é o que diz
  // se a série teve movimento recente).
  function pesoRecencia(it) {
    if (it.tipo !== 'serie') return idStream(it.url);
    let maior = null;
    for (const e of (it.episodios || [])) {
      const id = idStream(e.url);
      if (id !== null && (maior === null || id > maior)) maior = id;
    }
    return maior;
  }
  // Do mais novo para o mais antigo. Quem não tem id (M3U avulsa) fica depois,
  // na ordem INVERSA da lista — provedor acrescenta no fim do arquivo.
  function ordenarPorRecencia(arr) {
    return arr
      .map((it, i) => ({ it, id: pesoRecencia(it), i }))
      .sort((a, b) => {
        if (a.id !== null && b.id !== null) return b.id - a.id;
        if (a.id !== null) return -1;
        if (b.id !== null) return 1;
        return b.i - a.i;
      })
      .map((x) => x.it);
  }

  // ── Catálogo ──────────────────────────────────────────────────────────────
  // Filmes/Séries: categorias A-Z, com LANÇAMENTOS primeiro (igual ao mobile).
  function trilhosPorGrupo(itens) {
    // Na TV (pouca RAM) limitamos o DOM: menos itens por trilho e menos trilhos.
    const tv = (typeof EH_TV !== 'undefined' && EH_TV);
    const maxItens = tv ? 20 : 40, maxTrilhos = tv ? 40 : 9999;
    const g = {};
    for (const i of itens) { const k = (i.generos && i.generos[0]) || 'Outros'; (g[k] || (g[k] = [])).push(i); }
    const nomes = _ordenarPorChave(Object.keys(g), _chaveOrd);
    const ordenadas = [...nomes.filter(ehLancamento), ...nomes.filter((n) => !ehLancamento(n))];
    return ordenadas.slice(0, maxTrilhos).map((titulo) => ({
      titulo,
      // LANÇAMENTOS: ordem de CHEGADA (mais novo primeiro) — numa fila de
      // lançamentos o que importa é o que acabou de entrar, e o A-Z escondia
      // isso no meio da lista. Demais categorias seguem A-Z, com a chave
      // pré-calculada (1x por item) em vez de toLowerCase()+localeCompare()
      // por comparação — era centenas de milhares de operações lentas no boot.
      itens: (ehLancamento(titulo)
        ? ordenarPorRecencia(g[titulo])
        : _ordenarPorChave(g[titulo], (it) => _chaveOrd(it.titulo))
      ).slice(0, maxItens),
    }));
  }

  // `prog(pct 0..1, rotulo)` — reporta progresso REAL (o parse é fatiado e cede a
  // UI), então a tela de carregamento não congela em listas gigantes.
  async function parse(texto, prog) {
    const p = (frac, rot) => { if (prog) prog(frac, rot); };
    const todos = await parseM3U(texto, (f) => p(f * 0.55, 'ler'));   // scan ≈ 55% do custo
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
    const { filmes: fRaw, series: sRaw } = await agruparVod(vodRaw, (f) => p(0.55 + f * 0.38, 'agrupar'));
    const filmes = fRaw.map((c, i) => ({ id: 'f' + i, titulo: c.nome, url: c.url, logo: c.logo, generos: [c.grupo || 'Filmes'], ano: '', nota: 0, sinopse: '', tipo: 'filme' }));
    const series = sRaw.map((s, i) => ({ id: 's' + i, titulo: s.nome, url: (s.eps[0] || {}).url, logo: s.logo, generos: [s.grupo || 'Séries'], episodios: s.eps.map((e) => ({ nome: e.nome, url: e.url })), ano: '', nota: 0, sinopse: '', tipo: 'serie' }));
    p(0.95, 'montar');
    await _cede();
    const { catalogo, indice } = montarCatalogo({ canais, filmes, series });
    p(1, 'pronto');
    return { canais, filmes, series, catalogo, indice, total: todos.length };
  }

  // Monta catálogo + índice a partir das listas planas. Exportado porque o CACHE
  // guarda só {canais, filmes, series} (leve) e reconstrói isto na leitura — é
  // barato (~25ms num desktop) e evita clonar o grafo de referências.
  function montarCatalogo({ canais, filmes, series }) {
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
    for (const i of filmes) indice[i.id] = i;
    for (const i of series) indice[i.id] = i;
    return { canais, filmes, series, catalogo, indice, total: canais.length + filmes.length + series.length };
  }

  return { parse, parseM3U, montarCatalogo, detectarQualidade };
})();
