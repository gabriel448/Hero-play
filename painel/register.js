// Cadastro público de revendedor por LINK DE INDICAÇÃO (?ref=CODIGO).
// Chama a ação pública `registrar_indicacao` da Edge Function `painel`.
const SUPABASE_URL = 'https://cfwmeeksnwampfdkicye.supabase.co'
const ANON = 'eyJhbGciOiJIUzI1NiIsInR5cCI6IkpXVCJ9.eyJpc3MiOiJzdXBhYmFzZSIsInJlZiI6ImNmd21lZWtzbndhbXBmZGtpY3llIiwicm9sZSI6ImFub24iLCJpYXQiOjE3ODQ5MDIwMjksImV4cCI6MjEwMDQ3ODAyOX0.oFd0yNhE4I0uqrGzkmetVQllZs6loUrpsoXzvY9C2Tg'
const FN = SUPABASE_URL + '/functions/v1/painel'

const app = document.getElementById('app')
const ano = new Date().getFullYear()
const ref = (new URLSearchParams(location.search).get('ref') || '').trim()
const esc = (s) => String(s ?? '').replace(/[&<>"]/g, (c) => ({ '&': '&amp;', '<': '&lt;', '>': '&gt;', '"': '&quot;' }[c]))
const IC_EYE = '<svg viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="1.9" stroke-linecap="round" stroke-linejoin="round"><path d="M2 12s3.5-7 10-7 10 7 10 7-3.5 7-10 7-10-7-10-7z"/><circle cx="12" cy="12" r="3"/></svg>'
const IC_EYEOFF = '<svg viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="1.9" stroke-linecap="round" stroke-linejoin="round"><path d="M9.9 4.24A9.1 9.1 0 0 1 12 4c6.5 0 10 7 10 7a13.2 13.2 0 0 1-1.67 2.68"/><path d="M6.1 6.1A13.3 13.3 0 0 0 2 11s3.5 7 10 7a9.1 9.1 0 0 0 3.4-.66"/><path d="M14.12 14.12A3 3 0 1 1 9.88 9.88"/><line x1="2" x2="22" y1="2" y2="22"/></svg>'

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
        <label>Usuário (login)</label><input id="usuario" type="text" placeholder="ex: revenda_joao" autocomplete="username" autocapitalize="none" spellcheck="false">
        <label>Senha (mín. 6)</label>
        <div class="senha-wrap"><input id="senha" type="password" placeholder="••••••••" autocomplete="new-password"><button type="button" class="olho" id="olho" aria-label="Mostrar senha">${IC_EYE}</button></div>
        <button class="btn" id="criar">Criar conta</button>
        <div class="erro" id="erro">${msg ? esc(msg) : ''}</div>
      ` : '<div class="erro">Peça o link de indicação a um revendedor Hero Play.</div>'}
    </div><div class="form-rodape">Hero Play © ${ano}</div></div>
  </div>`
  if (!ref) return
  const err = (m) => { document.getElementById('erro').textContent = m }
  const criar = async () => {
    const nome = document.getElementById('nome').value.trim()
    const usuario = document.getElementById('usuario').value.trim().toLowerCase()
    const senha = document.getElementById('senha').value
    if (!/^[a-z0-9._-]{3,30}$/.test(usuario)) return err('Usuário: 3-30 letras/números . _ - (sem espaços).')
    if (senha.length < 6) return err('Senha de no mínimo 6 caracteres.')
    const btn = document.getElementById('criar'); btn.disabled = true; err('')
    try {
      const r = await fetch(FN, {
        method: 'POST',
        headers: { 'content-type': 'application/json', apikey: ANON, authorization: 'Bearer ' + ANON },
        body: JSON.stringify({ acao: 'registrar_indicacao', ref, nome, usuario, senha }),
      })
      const j = await r.json().catch(() => ({}))
      if (!r.ok || j.ok === false || j.erro) throw new Error(j.erro || ('erro ' + r.status))
      sucesso()
    } catch (e) { err(e.message); btn.disabled = false }
  }
  document.getElementById('criar').onclick = criar
  document.getElementById('senha').onkeydown = (e) => { if (e.key === 'Enter') criar() }
  const olho = document.getElementById('olho')
  if (olho) olho.onclick = () => {
    const inp = document.getElementById('senha'); const ver = inp.type === 'password'
    inp.type = ver ? 'text' : 'password'; olho.innerHTML = ver ? IC_EYEOFF : IC_EYE
    olho.setAttribute('aria-label', ver ? 'Ocultar senha' : 'Mostrar senha'); inp.focus()
  }
}

function sucesso() {
  app.innerHTML = `<div class="login2">
    ${brand('Conta <b>criada</b>!', 'Agora é só entrar no painel com seu usuário e senha.')}
    <div class="login2-form"><div class="form-inner">
      <h2>Tudo pronto ✅</h2>
      <p class="form-sub">Sua conta de revendedor foi criada e já está vinculada a quem te indicou.</p>
      <a class="btn" href="index.html" style="text-decoration:none;margin-top:8px">Ir para o login</a>
    </div><div class="form-rodape">Hero Play © ${ano}</div></div>
  </div>`
}

render()