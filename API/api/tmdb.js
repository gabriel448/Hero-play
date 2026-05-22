module.exports = async function handler(req, res) {
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
