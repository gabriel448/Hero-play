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
    res.status(response.status).setHeader('Content-Type', 'application/json').send(body);
  } catch {
    res.status(502).json({ error: 'proxy_error' });
  }
};
