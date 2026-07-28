/* ============================================================================
   Cliente TMDB (via proxy Vercel) — portado de lib/services/tmdb_service.dart.
   Busca poster (vertical), backdrop (horizontal), sinopse, nota, ano e elenco
   para filmes/séries, por NOME. Caches em memória (1 request por título/sessão).
   O proxy injeta a API key e libera CORS (API/api/tmdb.js).
   ============================================================================ */
const TMDB = (() => {
  const PROXY = 'https://iptv-zeta-navy.vercel.app/api/tmdb';
  const IMG = 'https://image.tmdb.org/t/p/';
  const IDIOMA = 'pt-BR';
  const poster500 = (p) => (p ? IMG + 'w500' + p : '');
  const backdropImg = (p) => (p ? IMG + 'w1280' + p : '');
  const perfilImg = (p) => (p ? IMG + 'w185' + p : '');

  const _cacheInfo = {};
  const _cachePoster = {};
  // Marca que há metadado novo ainda não persistido (ver exportarCache/CacheLista).
  let _sujo = false;

  function prepararQuery(nome) {
    return (nome || '')
      .replace(/[\[\(][A-Za-z]{2,5}(?:[\-\s][A-Za-z]{2,3})?[\]\)]/g, ' ')
      .replace(/[\[\(]\d{4}[\]\)]/g, ' ')
      .replace(/\b(?:4K|UHD|FHD|QHD|HDR|HD|SD|2160P|1080P|720P|480P|WEB[\s\-]?DL|BLURAY|BRRIP|DVDRIP|HDCAM|CAM)\b/gi, ' ')
      .replace(/\b(?:LEG|DUB|VOST|DUAL|LEGENDADO|DUBLADO)\b/gi, ' ')
      .replace(/[._]/g, ' ').replace(/[\[\]\(\)]/g, ' ')
      // Pontuação separadora QUEBRA a busca do TMDB (ex.: ':' faz "Título: Subtítulo"
      // retornar 0 resultados). Troca por espaço. Mantém apóstrofo/hífen (funcionam:
      // "Grey's Anatomy", "Spider-Man") e '&' (escolher() trata como " e ").
      .replace(/[:;!?,|/\\*"“”]/g, ' ')
      .replace(/\s+/g, ' ').trim();
  }
  // Stop/conectores (PT+EN) p/ fallback quando a busca completa não acha nada —
  // listas às vezes inserem conectores que não estão no título real (ex.: a lista
  // traz "100 Days Para a indy"; o TMDB tem "100 Days to Indy"). Tirar os conectores
  // ("100 Days indy") faz casar. Só usado como 2ª tentativa.
  const STOP = new Set(['a', 'o', 'as', 'os', 'um', 'uma', 'de', 'do', 'da', 'dos', 'das',
    'e', 'que', 'para', 'pra', 'por', 'com', 'em', 'no', 'na', 'nos', 'nas', 'ao', 'aos',
    'the', 'to', 'of', 'and', 'in', 'on', 'for', 'la', 'el', 'le', 'les', 'un', 'una']);
  function reduzir(q) {
    const w = (q || '').split(' ').filter((x) => x && !STOP.has(semAcento(x).toLowerCase()));
    const r = w.join(' ');
    return r && r !== q ? r : '';
  }
  // Remove acentos TRANSLITERANDO (á→a, ç→c, ñ→n) via decomposição NFD — assim
  // "Pokémon" e "Pokemon" casam. (O mobile apaga o acento em vez de transliterar,
  // o que quebrava esses casos; aqui corrigimos.)
  const semAcento = (s) => (s || '').normalize('NFD').replace(/[̀-ͯ]/g, '');
  // Normaliza p/ COMPARAÇÃO: sem acento, minúsculo, sem pontuação/símbolos,
  // espaços simples. Cobre caracteres especiais (':', '!', '’', '-', '/'...).
  const norm = (s) => semAcento(s).toLowerCase()
    .replace(/[._]/g, ' ')
    .replace(/&/g, ' e ')
    .replace(/[^a-z0-9\s]/g, '')
    .replace(/\s+/g, ' ').trim();

  async function get(p, params) {
    const u = new URL(PROXY);
    u.searchParams.set('p', p);
    for (const k in params) u.searchParams.set(k, params[k]);
    const r = await fetch(u.toString());
    if (!r.ok) throw new Error('tmdb ' + r.status);
    return r.json();
  }
  // `estrito`: NÃO cai no results[0] quando nada casa por título. Sem isso o TMDB
  // devolve "o primeiro que veio" — foi o que fazia a busca mostrar o pôster de
  // OUTRO filme (ex.: "Interestelar" pegando um programa de TV qualquer).
  function escolher(results, query, ehTv, estrito) {
    if (!results || !results.length) return null;
    const cn = ehTv ? 'name' : 'title';
    const co = ehTv ? 'original_name' : 'original_title';
    const q = norm(query);
    const words = q.split(' ').filter(Boolean);
    const match = (it, test) => test(norm(it[cn] || '')) || test(norm(it[co] || ''));
    const tk = results.slice(0, 10);
    return tk.find((it) => match(it, (s) => s === q))
      || tk.find((it) => match(it, (s) => s.startsWith(q)))
      || tk.find((it) => match(it, (s) => s.includes(q)))
      || (words.length > 1 ? tk.find((it) => match(it, (s) => words.every((w) => s.includes(w)))) : null)
      || (estrito ? null : results[0]);
  }
  async function buscarItem(endpoint, query, ehTv, idioma) {
    try {
      const b = await get(endpoint, { query, language: idioma || IDIOMA, include_adult: 'false' });
      return escolher(b.results, query, ehTv);
    } catch (_) { return null; }
  }
  // Busca com fallback: tenta a query completa; se não achar, tenta sem os
  // conectores (reduzir). Passa a query REDUZIDA p/ escolher() na 2ª tentativa,
  // pra a comparação ser coerente com o que foi buscado.
  async function buscar(endpoint, query, ehTv, idioma) {
    let it = await buscarItem(endpoint, query, ehTv, idioma);
    if (it) return it;
    const r = reduzir(query);
    if (r) {
      try {
        const b = await get(endpoint, { query: r, language: idioma || IDIOMA, include_adult: 'false' });
        it = escolher(b.results, r, ehTv);
      } catch (_) { /* ignore */ }
    }
    return it;
  }

  // Info completa por nome. ehSerie decide a ordem de busca (tv/movie) com fallback.
  async function info(nome, ehSerie) {
    const chave = (ehSerie ? 'tv|' : 'mv|') + nome;
    if (_cacheInfo[chave]) return _cacheInfo[chave];
    const query = prepararQuery(nome);
    let item, ehTv;
    if (ehSerie) {
      item = await buscar('/3/search/tv', query, true); ehTv = true;
      if (!item) { item = await buscar('/3/search/movie', query, false); ehTv = false; }
    } else {
      item = await buscar('/3/search/movie', query, false); ehTv = false;
      if (!item) { item = await buscar('/3/search/tv', query, true); ehTv = true; }
    }
    let out;
    if (!item) {
      out = { vazio: true };
    } else {
      const data = item.release_date || item.first_air_date || '';
      out = {
        id: item.id, ehTv,
        poster: poster500(item.poster_path),
        backdrop: backdropImg(item.backdrop_path),
        sinopse: (item.overview || '').trim(),
        nota: item.vote_average > 0 ? Math.round(item.vote_average * 10) / 10 : null,
        ano: data.length >= 4 ? parseInt(data.slice(0, 4)) : null,
        // Nome traduzido (pt-BR) e nome ORIGINAL — usados pela busca p/ achar por
        // referência/tradução (ex.: anime que na lista vem em inglês/japonês).
        nome: (item.name || item.title || '').trim(),
        original: (item.original_name || item.original_title || '').trim(),
        // Gêneros do TMDB (IDs canônicos) — usados como "tags" p/ recomendação por perfil.
        genero_ids: Array.isArray(item.genre_ids) ? item.genre_ids.slice() : [],
      };
    }
    _cacheInfo[chave] = out;
    _sujo = true;
    return out;
  }

  // Só o pôster — usado por séries (que não têm capa boa na lista) e como FALLBACK
  // de filme cujo logo da lista não abre. Busca SEMPRE no endpoint do tipo certo
  // primeiro (série→tv, filme→movie): procurar em /search/tv um filme trazia
  // programas de TV homônimos e o pôster saía trocado.
  // Idioma: pt-BR primeiro (o título da lista costuma ser o traduzido — "Interestelar"
  // só casa com language=pt-BR); en-US como 2ª tentativa (anime/série que a lista
  // traz pelo nome em inglês). Sempre ESTRITO: sem casar por título, sem pôster.
  // Busca que PROPAGA falha de rede/rate-limit (get lança em !ok) mas retorna null
  // em resultado vazio — p/ o poster() distinguir "TMDB não tem" de "falhou".
  async function buscarStrict(endpoint, query, ehTv, idioma) {
    let it = escolher((await get(endpoint, { query, language: idioma || IDIOMA, include_adult: 'false' })).results, query, ehTv, true);
    if (it) return it;
    const r = reduzir(query);
    if (r) it = escolher((await get(endpoint, { query: r, language: idioma || IDIOMA, include_adult: 'false' })).results, r, ehTv, true);
    return it;
  }
  const _inflightPoster = {};   // dedupe: 1 requisição por título mesmo com N pedidos simultâneos
  const chavePoster = (nome, ehSerie) => (ehSerie ? 'tv|' : 'mv|') + nome;
  function poster(nome, ehSerie) {
    const chave = chavePoster(nome, ehSerie);
    if (chave in _cachePoster) return Promise.resolve(_cachePoster[chave]);
    if (_inflightPoster[chave]) return _inflightPoster[chave];
    const p = (async () => {
      const query = prepararQuery(nome);
      const principal = ehSerie ? '/3/search/tv' : '/3/search/movie';
      const outro = ehSerie ? '/3/search/movie' : '/3/search/tv';
      let url = '', falhou = false;
      try {
        const item = (await buscarStrict(principal, query, !!ehSerie, IDIOMA))
          || (await buscarStrict(principal, query, !!ehSerie, 'en-US'))
          || (await buscarStrict(outro, query, !ehSerie, IDIOMA));
        url = item ? poster500(item.poster_path) : '';
      } catch (_) { falhou = true; }   // rede/rate-limit → NÃO cacheia (permite retry)
      if (!falhou) { _cachePoster[chave] = url; _sujo = true; }
      delete _inflightPoster[chave];
      return url;
    })();
    _inflightPoster[chave] = p;
    return p;
  }

  // Logo-título (PNG transparente, estilo Netflix). Prefere pt, depois en, depois
  // qualquer. '' se o TMDB não tiver.
  const _cacheLogo = {};
  async function tituloLogo(id, ehTv) {
    const k = (ehTv ? 'tv' : 'mv') + id;
    if (k in _cacheLogo) return _cacheLogo[k];
    let url = '';
    try {
      const b = await get(ehTv ? `/3/tv/${id}/images` : `/3/movie/${id}/images`, { include_image_language: 'pt,en,null' });
      // Só logos-TÍTULO de verdade: horizontais (aspect_ratio largo). Evita pegar
      // pôster/banner vertical que às vezes vem na lista de logos.
      const todos = (b.logos || []).filter((l) => l.file_path && (l.aspect_ratio || 0) >= 1.3);
      const pick = todos.find((l) => l.iso_639_1 === 'pt') || todos.find((l) => l.iso_639_1 === 'en') || todos[0];
      if (pick) url = IMG + 'w500' + pick.file_path;
    } catch (_) { /* ignore */ }
    _cacheLogo[k] = url;
    _sujo = true;
    return url;
  }

  async function elenco(id, ehTv) {
    try {
      const b = await get(ehTv ? `/3/tv/${id}/credits` : `/3/movie/${id}/credits`, { language: IDIOMA });
      return (b.cast || []).slice(0, 12).map((c) => ({ nome: (c.name || '').trim(), foto: perfilImg(c.profile_path) })).filter((a) => a.nome);
    } catch (_) { return []; }
  }

  // Créditos: elenco (com foto/personagem) + direção (crew).
  const _cacheCred = {};
  async function creditos(id, ehTv) {
    const k = (ehTv ? 'tv' : 'mv') + id;
    if (_cacheCred[k]) return _cacheCred[k];
    let out = { elenco: [], direcao: [] };
    try {
      const b = await get(ehTv ? `/3/tv/${id}/credits` : `/3/movie/${id}/credits`, { language: IDIOMA });
      out.elenco = (b.cast || []).slice(0, 20)
        .map((c) => ({ nome: (c.name || '').trim(), personagem: (c.character || '').trim(), foto: perfilImg(c.profile_path) }))
        .filter((a) => a.nome);
      const dir = (b.crew || []).filter((c) => c.job === 'Director' || c.department === 'Directing').map((c) => c.name);
      out.direcao = [...new Set(dir.filter(Boolean))].slice(0, 4);
    } catch (_) { /* ignore */ }
    _cacheCred[k] = out;
    return out;
  }

  // Recomendados (TMDB) — usados como fallback; o app prioriza a própria lista.
  async function recomendados(id, ehTv) {
    try {
      const b = await get(ehTv ? `/3/tv/${id}/recommendations` : `/3/movie/${id}/recommendations`, { language: IDIOMA });
      return (b.results || []).slice(0, 18)
        .map((r) => ({ titulo: r.title || r.name || '', poster: poster500(r.poster_path), tipo: ehTv ? 'serie' : 'filme' }))
        .filter((x) => x.poster);
    } catch (_) { return []; }
  }

  // Episódios de uma temporada: nº do episódio -> { still (capa), nome, sinopse }.
  const _cacheTemp = {};
  async function temporada(id, s) {
    const k = id + '|' + s;
    if (_cacheTemp[k]) return _cacheTemp[k];
    const map = {};
    try {
      const b = await get(`/3/tv/${id}/season/${s}`, { language: IDIOMA });
      for (const e of (b.episodes || [])) {
        map[e.episode_number] = {
          still: e.still_path ? IMG + 'w300' + e.still_path : '',
          nome: (e.name || '').trim(), sinopse: (e.overview || '').trim(),
        };
      }
    } catch (_) { /* ignore */ }
    _cacheTemp[k] = map;
    return map;
  }

  // Acesso síncrono ao cache (pré-carregamento): null = ainda não buscado.
  const infoCache = (nome, ehSerie) => _cacheInfo[(ehSerie ? 'tv|' : 'mv|') + nome] || null;
  const logoCache = (id, ehTv) => { const k = (ehTv ? 'tv' : 'mv') + id; return k in _cacheLogo ? _cacheLogo[k] : null; };
  const posterCache = (nome, ehSerie) => { const k = chavePoster(nome, ehSerie); return k in _cachePoster ? _cachePoster[k] : null; };
  const temporadaCache = (id, s) => _cacheTemp[id + '|' + s] || null; // já pré-carregada?

  // ── Persistência dos metadados (IndexedDB, via CacheLista) ─────────────────
  // Sem isto os caches acima são só de memória: a cada boot o app re-pergunta o
  // pôster de CADA título ao TMDB. Guardamos os mais RECENTES (as chaves de
  // objeto preservam ordem de inserção) para o dump não crescer sem limite.
  const LIM_INFO = 4000, LIM_POSTER = 40000, LIM_LOGO = 8000;
  function _ultimos(o, n) {
    const ks = Object.keys(o);
    if (ks.length <= n) return o;
    const out = {};
    for (const k of ks.slice(ks.length - n)) out[k] = o[k];
    return out;
  }
  function exportarCache() {
    return {
      v: 1,
      info: _ultimos(_cacheInfo, LIM_INFO),
      poster: _ultimos(_cachePoster, LIM_POSTER),
      logo: _ultimos(_cacheLogo, LIM_LOGO),
    };
  }
  function importarCache(d) {
    if (!d || d.v !== 1) return 0;
    // Assign: o que já foi buscado nesta sessão é mais novo — não sobrescreve.
    for (const k in (d.info || {})) if (!(k in _cacheInfo)) _cacheInfo[k] = d.info[k];
    // Só chaves no formato novo ("tv|nome"/"mv|nome"). As antigas (só o nome) vêm
    // da época em que o pôster era procurado em /search/tv p/ tudo — podem estar
    // TROCADAS; descartar aqui limpa o cache persistido de quem já atualizou.
    for (const k in (d.poster || {})) if (/^(tv|mv)\|/.test(k) && !(k in _cachePoster)) _cachePoster[k] = d.poster[k];
    for (const k in (d.logo || {})) if (!(k in _cacheLogo)) _cacheLogo[k] = d.logo[k];
    return Object.keys(d.poster || {}).length;
  }
  const estaSujo = () => _sujo;
  const limparSujo = () => { _sujo = false; };

  return { info, poster, elenco, tituloLogo, creditos, recomendados, temporada, infoCache, logoCache, posterCache, temporadaCache, exportarCache, importarCache, estaSujo, limparSujo };
})();
