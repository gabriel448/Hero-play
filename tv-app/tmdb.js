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

  function prepararQuery(nome) {
    return (nome || '')
      .replace(/[\[\(][A-Za-z]{2,5}(?:[\-\s][A-Za-z]{2,3})?[\]\)]/g, ' ')
      .replace(/[\[\(]\d{4}[\]\)]/g, ' ')
      .replace(/\b(?:4K|UHD|FHD|QHD|HDR|HD|SD|2160P|1080P|720P|480P|WEB[\s\-]?DL|BLURAY|BRRIP|DVDRIP|HDCAM|CAM)\b/gi, ' ')
      .replace(/\b(?:LEG|DUB|VOST|DUAL|LEGENDADO|DUBLADO)\b/gi, ' ')
      .replace(/[._]/g, ' ').replace(/[\[\]\(\)]/g, ' ').replace(/\s+/g, ' ').trim();
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
  function escolher(results, query, ehTv) {
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
      || results[0];
  }
  async function buscarItem(endpoint, query, ehTv, idioma) {
    try {
      const b = await get(endpoint, { query, language: idioma || IDIOMA, include_adult: 'false' });
      return escolher(b.results, query, ehTv);
    } catch (_) { return null; }
  }

  // Info completa por nome. ehSerie decide a ordem de busca (tv/movie) com fallback.
  async function info(nome, ehSerie) {
    const chave = (ehSerie ? 'tv|' : 'mv|') + nome;
    if (_cacheInfo[chave]) return _cacheInfo[chave];
    const query = prepararQuery(nome);
    let item, ehTv;
    if (ehSerie) {
      item = await buscarItem('/3/search/tv', query, true); ehTv = true;
      if (!item) { item = await buscarItem('/3/search/movie', query, false); ehTv = false; }
    } else {
      item = await buscarItem('/3/search/movie', query, false); ehTv = false;
      if (!item) { item = await buscarItem('/3/search/tv', query, true); ehTv = true; }
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
      };
    }
    _cacheInfo[chave] = out;
    return out;
  }

  // Só o poster (trilhos de série, que não têm logo na lista). Igual ao mobile
  // (posterSerie): busca em EN-US — nomes de série em listas costumam ser em
  // inglês, casa melhor — TV primeiro, depois movie (cobre anime/OVA).
  async function poster(nome) {
    if (nome in _cachePoster) return _cachePoster[nome];
    const query = prepararQuery(nome);
    const item = (await buscarItem('/3/search/tv', query, true, 'en-US'))
      || (await buscarItem('/3/search/movie', query, false, 'en-US'));
    const url = item ? poster500(item.poster_path) : '';
    _cachePoster[nome] = url;
    return url;
  }

  async function elenco(id, ehTv) {
    try {
      const b = await get(ehTv ? `/3/tv/${id}/credits` : `/3/movie/${id}/credits`, { language: IDIOMA });
      return (b.cast || []).slice(0, 12).map((c) => ({ nome: (c.name || '').trim(), foto: perfilImg(c.profile_path) })).filter((a) => a.nome);
    } catch (_) { return []; }
  }

  return { info, poster, elenco };
})();
