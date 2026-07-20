/* Proxy da API-Football (v3.football.api-sports.io).

   Por quê: a chave estava embutida no cliente (tv-app/jogos.js) — qualquer um
   que abrisse o app ou descompactasse o .ipk a lia, e o repositório é público.
   Aqui ela vira um SECRET de servidor (APIFOOTBALL_KEY) e nunca sai daqui.

   Bônus: cache no edge do Vercel. A agenda de um dia é a MESMA para todos os
   devices, então N TVs pedindo a mesma data colapsam em ~1 ida à API — o que
   importa porque o plano grátis tem cota diária apertada.

   Uso: /api/futebol?p=/fixtures&date=2026-07-19&timezone=America/Sao_Paulo */

// Allowlist de endpoints — sem ela isto vira um proxy aberto para a conta toda.
const PERMITIDOS = new Set(['/fixtures', '/leagues', '/teams']);

module.exports = async function handler(req, res) {
  // CORS — o app de TV (web) chama este proxy direto do navegador.
  res.setHeader('Access-Control-Allow-Origin', '*');
  res.setHeader('Access-Control-Allow-Headers', 'content-type');
  res.setHeader('Access-Control-Allow-Methods', 'GET, OPTIONS');
  if (req.method === 'OPTIONS') return res.status(204).end();

  const { p, ...rest } = req.query;
  if (!p) return res.status(400).json({ error: 'missing path' });
  if (!PERMITIDOS.has(p)) return res.status(403).json({ error: 'path not allowed' });

  const chave = process.env.APIFOOTBALL_KEY;
  if (!chave) return res.status(500).json({ error: 'missing APIFOOTBALL_KEY' });

  try {
    const upstream = `https://v3.football.api-sports.io${p}?${new URLSearchParams(rest)}`;
    const r = await fetch(upstream, { headers: { 'x-apisports-key': chave } });
    const body = await r.text();
    // Agenda do dia muda pouco: 10 min fresh + 1h stale-while-revalidate.
    // Erro/429 = cache curto, p/ não "grudar" uma falha por muito tempo.
    res.setHeader('Cache-Control', r.status === 200
      ? 'public, s-maxage=600, stale-while-revalidate=3600'
      : 'public, s-maxage=30');
    return res.status(r.status).setHeader('Content-Type', 'application/json').send(body);
  } catch {
    res.setHeader('Cache-Control', 'public, s-maxage=10');
    return res.status(502).json({ error: 'proxy_error' });
  }
};