module.exports = async function handler(req, res) {
  // CORS — o app de TV (web) chama este proxy direto do navegador.
  res.setHeader('Access-Control-Allow-Origin', '*');
  res.setHeader('Access-Control-Allow-Headers', 'content-type');
  res.setHeader('Access-Control-Allow-Methods', 'GET, OPTIONS');
  if (req.method === 'OPTIONS') return res.status(204).end();

  const { p, ...rest } = req.query;

  if (!p) return res.status(400).json({ error: 'missing path' });

  const params = new URLSearchParams(rest);
  params.set('api_key', process.env.TMDB_API_KEY);

  try {
    const upstream = `https://api.themoviedb.org${p}?${params}`;
    const response = await fetch(upstream);
    const body = await response.text();
    // CACHE NO EDGE (CDN do Vercel): metadado do TMDB é ~estático. Respostas OK
    // ficam 1 dia "fresh" + 7 dias stale-while-revalidate → N devices pedindo o
    // MESMO título colapsam em ~1 ida ao TMDB (a chave de cache é a query inteira;
    // a api_key é injetada no server, fora da chave). Erros/429 = cache curto p/
    // não "grudar" um 429 por um dia. Isso corta drasticamente a carga no TMDB.
    res.setHeader('Cache-Control', response.status === 200
      ? 'public, s-maxage=86400, stale-while-revalidate=604800'
      : 'public, s-maxage=30');
    res.status(response.status).setHeader('Content-Type', 'application/json').send(body);
  } catch {
    res.setHeader('Cache-Control', 'public, s-maxage=10');
    res.status(502).json({ error: 'proxy_error' });
  }
};
