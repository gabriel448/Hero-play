export const config = { runtime: 'edge' };

export default async function handler(request) {
  const url = new URL(request.url);
  const tmdbPath = url.pathname.replace(/^\/api\/tmdb/, '');

  const params = new URLSearchParams(url.search);
  params.set('api_key', process.env.TMDB_API_KEY);

  try {
    const upstream = `https://api.themoviedb.org${tmdbPath}?${params}`;
    const res = await fetch(upstream);
    const body = await res.text();

    return new Response(body, {
      status: res.status,
      headers: { 'Content-Type': 'application/json' },
    });
  } catch {
    return new Response('{"error":"proxy_error"}', {
      status: 502,
      headers: { 'Content-Type': 'application/json' },
    });
  }
}
