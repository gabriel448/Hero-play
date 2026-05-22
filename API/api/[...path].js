module.exports = async function handler(req, res) {
  const segments = req.query.path || [];
  const tmdbPath = '/' + (Array.isArray(segments) ? segments.join('/') : segments);

  const params = new URLSearchParams();
  for (const [key, value] of Object.entries(req.query)) {
    if (key !== 'path') params.set(key, value);
  }
  params.set('api_key', process.env.TMDB_API_KEY);

  try {
    const upstream = `https://api.themoviedb.org${tmdbPath}?${params}`;
    const response = await fetch(upstream);
    const body = await response.text();
    res.status(response.status).setHeader('Content-Type', 'application/json').send(body);
  } catch {
    res.status(502).json({ error: 'proxy_error' });
  }
};
