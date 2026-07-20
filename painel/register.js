// Cadastro público de revendedor por LINK DE INDICAÇÃO (?ref=CODIGO).
// Chama a ação pública `registrar_indicacao` da Edge Function `painel`.
const SUPABASE_URL = 'https://mlafyphpntjssmxagyhc.supabase.co'
const ANON = 'sb_publishable_MlxtdbBT4UJWhBVJ5Krtww_AvZHXa3I'
const FN = SUPABASE_URL + '/functions/v1/painel'

const app = document.getElementById('app')
const ano = new Date().getFullYear()
const ref = (new URLSearchParams(location.search).get('ref') || '').trim()
const esc = (s) => String(s ?? '').replace(/[&<>"]/g, (c) => ({ '&': '&amp;', '<': '&lt;', '>': '&gt;', '"': '&quot;' }[c]))

const brand = (h1, sub) => `<div class="login2-brand"><div class="brand-inner">
  <img class="brand-logo" src="heroplay-icon.svg" alt="Hero Play">
  <div class="brand-label">Cadastro de Revendedor</div>
  <h1 class="brand-h1">${h1}</h1>
  <p class="brand-sub">${sub}</p>
</div><div class="brand-rodape">Hero Play © ${ano}</div></div>`

function render(msg) {
  app.innerHTML = `<div class="login2">
    ${brand('Comece a <b>revender</b> hoje.', 'Crie sua conta pelo convite e gerencie clientes, dispositivos e playlists.')}
    <div class="login2-form"><div class="form-inner">
      <h2>Criar conta</h2>
      <p class="form-sub">${ref ? 'Convite válido — preencha seus dados' : 'Link de convite inválido ou ausente'}</p>
      ${ref ? `
        <label>Nome</label><input id="nome" placeholder="Seu nome" autocomplete="name">
        <label>E-mail (login)</label><input id="email" type="email" placeholder="seu@email.com" autocomplete="username">
        <label>Senha (mín. 6)</label><input id="senha" type="password" placeholder="••••••••" autocomplete="new-password">
        <button class="btn" id="criar">Criar conta</button>
        <div class="erro" id="erro">${msg ? esc(msg) : ''}</div>
      ` : '<div class="erro">Peça o link de indicação a um revendedor Hero Play.</div>'}
    </div><div class="form-rodape">Hero Play © ${ano}</div></div>
  </div>`
  if (!ref) return
  const err = (m) => { document.getElementById('erro').textContent = m }
  const criar = async () => {
    const nome = document.getElementById('nome').value.trim()
    const email = document.getElementById('email').value.trim()
    const senha = document.getElementById('senha').value
    if (!email || senha.length < 6) return err('Informe e-mail e senha (mín. 6).')
    const btn = document.getElementById('criar'); btn.disabled = true; err('')
    try {
      const r = await fetch(FN, {
        method: 'POST',
        headers: { 'content-type': 'application/json', apikey: ANON, authorization: 'Bearer ' + ANON },
        body: JSON.stringify({ acao: 'registrar_indicacao', ref, nome, email, senha }),
      })
      const j = await r.json().catch(() => ({}))
      if (!r.ok || j.ok === false || j.erro) throw new Error(j.erro || ('erro ' + r.status))
      sucesso()
    } catch (e) { err(e.message); btn.disabled = false }
  }
  document.getElementById('criar').onclick = criar
  document.getElementById('senha').onkeydown = (e) => { if (e.key === 'Enter') criar() }
}

function sucesso() {
  app.innerHTML = `<div class="login2">
    ${brand('Conta <b>criada</b>!', 'Agora é só entrar no painel com seu e-mail e senha.')}
    <div class="login2-form"><div class="form-inner">
      <h2>Tudo pronto ✅</h2>
      <p class="form-sub">Sua conta de revendedor foi criada e já está vinculada a quem te indicou.</p>
      <a class="btn" href="index.html" style="text-decoration:none;margin-top:8px">Ir para o login</a>
    </div><div class="form-rodape">Hero Play © ${ano}</div></div>
  </div>`
}

render()