/* Proxy de IMAGEM.

   Por quê: TVs antigas (webOS 5 = Chromium 68) falham em carregar imagens de
   alguns hosts — tipicamente por cadeia de certificado/TLS que o firmware não
   aceita mais. Os escudos de time/liga (media.api-sports.io) caem nesse caso.
   Servir pelo NOSSO domínio (o mesmo do proxy TMDB, que já funciona nessas TVs)
   resolve. Usado só como 2ª tentativa: o app tenta o host original primeiro.

   Allowlist obrigatória — sem ela isto vira um open proxy. */
const PERMITIDOS = new Set(['media.api-sports.io', 'image.tmdb.org']);

module.exports = async function handler(req, res) {
  const u = req.query.u;
  if (!u) return res.status(400).send('missing u');
  let alvo;
  try { alvo = new URL(u); } catch { return res.status(400).send('bad url'); }
  if (alvo.protocol !== 'https:' || !PERMITIDOS.has(alvo.hostname)) {
    return res.status(403).send('host not allowed');
  }
  try {
    const r = await fetch(alvo.toString());
    if (!r.ok) return res.status(r.status).send('upstream ' + r.status);
    const buf = Buffer.from(await r.arrayBuffer());
    res.setHeader('Content-Type', r.headers.get('content-type') || 'image/png');
    // Escudo de time não muda — cacheia forte na edge e no cliente.
    res.setHeader('Cache-Control', 'public, max-age=604800, s-maxage=2592000');
    res.setHeader('Access-Control-Allow-Origin', '*');
    return res.status(200).send(buf);
  } catch {
    return res.status(502).send('proxy error');
  }
};
