import { createClient } from 'https://esm.sh/@supabase/supabase-js@2'

// ── Config (projeto Supabase ATUAL — temporário; trocar ao migrar) ───────────
const SUPABASE_URL = 'https://cfwmeeksnwampfdkicye.supabase.co'
const ANON = 'eyJhbGciOiJIUzI1NiIsInR5cCI6IkpXVCJ9.eyJpc3MiOiJzdXBhYmFzZSIsInJlZiI6ImNmd21lZWtzbndhbXBmZGtpY3llIiwicm9sZSI6ImFub24iLCJpYXQiOjE3ODQ5MDIwMjksImV4cCI6MjEwMDQ3ODAyOX0.oFd0yNhE4I0uqrGzkmetVQllZs6loUrpsoXzvY9C2Tg'
const FN = SUPABASE_URL + '/functions/v1/painel'
const sb = createClient(SUPABASE_URL, ANON)
const RANK = { reseller: 1, master: 2, admin: 3 }
const PAPEL_PT = { admin: 'Admin', master: 'Master', reseller: 'Revendedor' }

// Plataforma do device (código gravado pelo app de TV E pelo app Flutter) →
// nome amigável + ícone. TVs vêm do tv-app; celular/tablet/desktop vêm do app
// Flutter (`Dispositivo.plataforma()`), que desde 2026-07-27 usa a MESMA
// Edge Function `ativacao` e a mesma tabela `dispositivos`.
// 'web' = provavelmente teste no navegador.
const MODELO_INFO = {
  // TV
  webos:        { nome: 'LG (webOS)',        icone: '📺' },
  tizen:        { nome: 'Samsung (Tizen)',   icone: '📺' },
  roku:         { nome: 'Roku',              icone: '🟣' },
  androidtv:    { nome: 'Android TV / Box',  icone: '🤖' },
  // Celular / tablet / desktop (app Flutter)
  android:      { nome: 'Android (celular)', icone: '📱' },
  androidtablet:{ nome: 'Android (tablet)',  icone: '💊' },
  ios:          { nome: 'iPhone',            icone: '📱' },
  ipados:       { nome: 'iPad',              icone: '💊' },
  windows:      { nome: 'Windows (PC)',      icone: '🖥️' },
  macos:        { nome: 'Mac',               icone: '🖥️' },
  linux:        { nome: 'Linux (PC)',        icone: '🖥️' },
  web:          { nome: 'Navegador (teste)', icone: '🌐' },
}
const modeloNome = (m) => (MODELO_INFO[m] && MODELO_INFO[m].nome) || (m || '—')
const modeloIcone = (m) => (MODELO_INFO[m] && MODELO_INFO[m].icone) || '❓'
const ATIVADO_POR_PT = { reseller: 'Revendedor', qr: 'QR (auto)', codigo: 'Código', admin: 'Admin', parceiro: 'Domínio parceiro' }

const app = document.getElementById('app')
let me = null // { id, nome, usuario, papel, saldo_creditos }
// ADMIN não tem saldo: ele é a FONTE do crédito, não um estoque. Toda a UI de
// crédito some pra ele (backend também não debita — ver rpc_* no schema).
const admInf = () => me && me.papel === 'admin'

const esc = (s) => String(s ?? '').replace(/[&<>"]/g, (c) => ({ '&': '&amp;', '<': '&lt;', '>': '&gt;', '"': '&quot;' }[c]))
const fmtData = (d) => d ? new Date(d).toLocaleDateString('pt-BR') : '—'
// Login por usuário → e-mail sintético (o Supabase Auth exige e-mail). MESMO
// derivador da Edge Function `painel` (USUARIO_DOMINIO). Nunca é enviado e-mail.
const USUARIO_DOMINIO = 'u.heroplaytv.com'
const usuarioParaEmail = (u) => String(u || '').trim().toLowerCase() + '@' + USUARIO_DOMINIO
// Data + hora (p/ "quando foi adicionado" com precisão no detalhe do device).
const fmtDataHora = (d) => d ? new Date(d).toLocaleString('pt-BR', { day: '2-digit', month: '2-digit', year: 'numeric', hour: '2-digit', minute: '2-digit' }) : '—'
function toast(msg, err) {
  const t = document.getElementById('toast')
  t.textContent = msg; t.className = 'on' + (err ? ' erro' : '')
  clearTimeout(t._t); t._t = setTimeout(() => { t.className = '' }, 3000)
}

async function api(acao, payload = {}) {
  const { data: { session } } = await sb.auth.getSession()
  const r = await fetch(FN, {
    method: 'POST',
    headers: { 'content-type': 'application/json', apikey: ANON, authorization: 'Bearer ' + (session?.access_token || ANON) },
    body: JSON.stringify({ acao, ...payload }),
  })
  const j = await r.json().catch(() => ({}))
  if (!r.ok || j.ok === false || j.erro) throw new Error(j.erro || ('erro ' + r.status))
  return j
}

// ── Cache por seção (não re-busca ao trocar de aba; invalida ao mutar) ────────
const cache = new Map()
async function pega(key, fetcher) {
  if (cache.has(key)) return cache.get(key)
  const v = await fetcher()
  cache.set(key, v)
  return v
}
const invalidar = (...keys) => keys.forEach((k) => cache.delete(k))

// ── Ícones (lucide) ──────────────────────────────────────────────────────────
const IC = {
  dashboard: '<path d="M4 4h6v8H4z"/><path d="M14 4h6v5h-6z"/><path d="M14 13h6v7h-6z"/><path d="M4 16h6v4H4z"/>',
  users: '<path d="M16 21v-2a4 4 0 0 0-4-4H6a4 4 0 0 0-4 4v2"/><circle cx="9" cy="7" r="4"/><path d="M22 21v-2a4 4 0 0 0-3-3.87"/><path d="M16 3.13a4 4 0 0 1 0 7.75"/>',
  shield: '<path d="M20 13c0 5-3.5 7.5-7.7 9-4.2-1.5-7.7-4-7.7-9V6l7.7-3 7.7 3z"/><path d="m9 12 2 2 4-4"/>',
  coins: '<circle cx="8" cy="8" r="6"/><path d="M18.09 10.37A6 6 0 1 1 10.34 18"/><path d="M7 6h1v4"/><path d="m16.71 13.88.7.71-2.82 2.82"/>',
  cart: '<circle cx="8" cy="21" r="1"/><circle cx="19" cy="21" r="1"/><path d="M2 2h2l2.6 12.4a2 2 0 0 0 2 1.6h9.8a2 2 0 0 0 2-1.6L23 6H5"/>',
  link: '<path d="M9 17H7A5 5 0 0 1 7 7h2"/><path d="M15 7h2a5 5 0 1 1 0 10h-2"/><line x1="8" x2="16" y1="12" y2="12"/>',
  globe: '<circle cx="12" cy="12" r="10"/><path d="M12 2a14.5 14.5 0 0 0 0 20 14.5 14.5 0 0 0 0-20"/><path d="M2 12h20"/>',
  monitor: '<rect width="20" height="14" x="2" y="3" rx="2"/><line x1="8" x2="16" y1="21" y2="21"/><line x1="12" x2="12" y1="17" y2="21"/>',
  logout: '<path d="M9 21H5a2 2 0 0 1-2-2V5a2 2 0 0 1 2-2h4"/><polyline points="16 17 21 12 16 7"/><line x1="21" x2="9" y1="12" y2="12"/>',
  plus: '<path d="M5 12h14"/><path d="M12 5v14"/>',
  send: '<path d="M14.5 9.5 21 3m0 0-6.5 18-3.5-8-8-3.5L21 3z"/>',
  userplus: '<path d="M16 21v-2a4 4 0 0 0-4-4H6a4 4 0 0 0-4 4v2"/><circle cx="9" cy="7" r="4"/><line x1="19" x2="19" y1="8" y2="14"/><line x1="22" x2="16" y1="11" y2="11"/>',
  zap: '<path d="M13 2 3 14h9l-1 8 10-12h-9l1-8z"/>',
  listv: '<path d="M12 12H3"/><path d="M16 6H3"/><path d="M12 18H3"/><path d="m16 12 5 3-5 3v-6Z"/>',
  ticket: '<path d="M2 9a3 3 0 0 0 0 6v2a2 2 0 0 0 2 2h16a2 2 0 0 0 2-2v-2a3 3 0 0 0 0-6V7a2 2 0 0 0-2-2H4a2 2 0 0 0-2 2z"/><path d="M13 5v2"/><path d="M13 11v2"/><path d="M13 17v2"/>',
  bell: '<path d="M6 8a6 6 0 0 1 12 0c0 7 3 9 3 9H3s3-2 3-9"/><path d="M10.3 21a1.94 1.94 0 0 0 3.4 0"/>',
  inbox: '<path d="M22 12h-6l-2 3h-4l-2-3H2"/><path d="M5.45 5.11 2 12v6a2 2 0 0 0 2 2h16a2 2 0 0 0 2-2v-6l-3.45-6.89A2 2 0 0 0 16.76 4H7.24a2 2 0 0 0-1.79 1.11z"/>',
  lifebuoy: '<circle cx="12" cy="12" r="10"/><circle cx="12" cy="12" r="4"/><line x1="4.93" y1="4.93" x2="9.17" y2="9.17"/><line x1="14.83" y1="14.83" x2="19.07" y2="19.07"/><line x1="14.83" y1="9.17" x2="19.07" y2="4.93"/><line x1="4.93" y1="19.07" x2="9.17" y2="14.83"/>',
  hash: '<line x1="4" x2="20" y1="9" y2="9"/><line x1="4" x2="20" y1="15" y2="15"/><line x1="10" x2="8" y1="3" y2="21"/><line x1="16" x2="14" y1="3" y2="21"/>',
  menu: '<line x1="3" x2="21" y1="6" y2="6"/><line x1="3" x2="21" y1="12" y2="12"/><line x1="3" x2="21" y1="18" y2="18"/>',
  server: '<rect width="20" height="8" x="2" y="2" rx="2"/><rect width="20" height="8" x="2" y="14" rx="2"/><line x1="6" x2="6.01" y1="6" y2="6"/><line x1="6" x2="6.01" y1="18" y2="18"/>',
  pencil: '<path d="M21.17 6.81a1 1 0 0 0-3.98-3.99L3.84 16.17a2 2 0 0 0-.5.83l-1.32 4.35a.5.5 0 0 0 .62.63l4.35-1.32a2 2 0 0 0 .83-.5z"/><path d="m15 5 4 4"/>',
  copy: '<rect width="13" height="13" x="9" y="9" rx="2"/><path d="M5 15H4a2 2 0 0 1-2-2V4a2 2 0 0 1 2-2h9a2 2 0 0 1 2 2v1"/>',
  search: '<circle cx="11" cy="11" r="8"/><path d="m21 21-4.3-4.3"/>',
  check: '<path d="m5 12.5 5 5 9-11"/>',
  refresh: '<path d="M3 12a9 9 0 0 1 9-9 9.75 9.75 0 0 1 6.74 2.74L21 8"/><path d="M21 3v5h-5"/><path d="M21 12a9 9 0 0 1-9 9 9.75 9.75 0 0 1-6.74-2.74L3 16"/><path d="M8 16H3v5"/>',
  trash: '<path d="M3 6h18"/><path d="M19 6v14a2 2 0 0 1-2 2H7a2 2 0 0 1-2-2V6"/><path d="M8 6V4a2 2 0 0 1 2-2h4a2 2 0 0 1 2 2v2"/><line x1="10" x2="10" y1="11" y2="17"/><line x1="14" x2="14" y1="11" y2="17"/>',
  eye: '<path d="M2 12s3.5-7 10-7 10 7 10 7-3.5 7-10 7-10-7-10-7z"/><circle cx="12" cy="12" r="3"/>',
  eyeoff: '<path d="M9.9 4.24A9.1 9.1 0 0 1 12 4c6.5 0 10 7 10 7a13.2 13.2 0 0 1-1.67 2.68"/><path d="M6.1 6.1A13.3 13.3 0 0 0 2 11s3.5 7 10 7a9.1 9.1 0 0 0 3.4-.66"/><path d="M14.12 14.12A3 3 0 1 1 9.88 9.88"/><line x1="2" x2="22" y1="2" y2="22"/>',
}
const svg = (name, extra = '') => `<svg viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="1.9" stroke-linecap="round" stroke-linejoin="round"${extra}>${IC[name]}</svg>`

// Campo de senha com botão de "olho" (mostrar/ocultar). `id` é o do <input>.
const campoSenha = (id, autocomplete) => `<div class="senha-wrap">
  <input id="${id}" type="password" placeholder="••••••••" autocomplete="${autocomplete}">
  <button type="button" class="olho" data-alvo="${id}" aria-label="Mostrar senha">${svg('eye')}</button>
</div>`
// Liga o toggle do olho de todos os campos-senha dentro de `raiz` (default: document).
function ligarOlhos(raiz) {
  (raiz || document).querySelectorAll('.olho').forEach((b) => {
    b.onclick = () => {
      const inp = document.getElementById(b.dataset.alvo)
      if (!inp) return
      const ver = inp.type === 'password'
      inp.type = ver ? 'text' : 'password'
      b.innerHTML = svg(ver ? 'eyeoff' : 'eye')
      b.setAttribute('aria-label', ver ? 'Ocultar senha' : 'Mostrar senha')
      inp.focus()
    }
  })
}

// ── Navegação ────────────────────────────────────────────────────────────────
// Mesmas seções do painel de referência, e elas MUDAM por papel: o revendedor
// tem um bloco só de "Negócios"; o admin separa Usuários (quem opera) de Sistema
// (o que é da plataforma). Grupo e item aceitam `papeis` — mas esconder no menu
// NÃO é segurança: cada ação de admin também confere `ehAdmin` no backend.
const NAV = [
  { grupo: '', itens: [
    { id: 'dashboard', rotulo: 'Dashboard', ic: 'dashboard' },
    { id: 'suporte', rotulo: 'Suporte', ic: 'lifebuoy' },
    { id: 'caixa', rotulo: 'Caixa de entrada', ic: 'inbox' },
  ] },
  { grupo: 'Conteúdo', itens: [
    // Clientes é NOSSO (o painel é client-centric; o de referência é device-centric).
    { id: 'clientes', rotulo: 'Clientes', ic: 'users' },
    { id: 'dispositivos', rotulo: 'Dispositivos', ic: 'monitor' },
    { id: 'playlists', rotulo: 'Playlists', ic: 'listv' },
  ] },
  { grupo: 'Negócios', papeis: ['master', 'reseller'], itens: [
    { id: 'comprar', rotulo: 'Comprar Créditos', ic: 'cart' },
    { id: 'creditos', rotulo: 'Créditos', ic: 'coins' },
    { id: 'indicacao', rotulo: 'Indicação', ic: 'link' },
    { id: 'revendedores', rotulo: 'Revendedores', ic: 'userplus' },
  ] },
  { grupo: 'Usuários', papeis: ['admin'], itens: [
    { id: 'revendedores', rotulo: 'Revendedores', ic: 'userplus' },
    { id: 'creditos', rotulo: 'Créditos', ic: 'coins' },
    { id: 'indicacao', rotulo: 'Indicação', ic: 'link' },
  ] },
  { grupo: 'Sistema', papeis: ['admin'], itens: [
    // Acordo comercial da plataforma — quem cadastra domínio parceiro é o admin.
    { id: 'parceiros', rotulo: 'Parceiros', ic: 'globe' },
    { id: 'servidores', rotulo: 'Servidores', ic: 'server' },
  ] },
]

function renderShell() {
  const nav = NAV.map((g) => {
    if (g.papeis && !g.papeis.includes(me.papel)) return ''
    const itens = g.itens.filter((i) => !i.papeis || i.papeis.includes(me.papel))
    if (!itens.length) return ''
    return `${g.grupo ? `<div class="nav-grp-label">${esc(g.grupo)}</div>` : ''}
      ${itens.map((i) => `<button class="nav-item" data-view="${i.id}">${svg(i.ic)}<span>${esc(i.rotulo)}</span></button>`).join('')}`
  }).join('')
  const inicial = (me.nome || me.usuario || '?').trim().charAt(0).toUpperCase()
  app.innerHTML = `<div class="shell">
    <header class="mtop">
      <button class="hamb" id="hamb" aria-label="Menu">${svg('menu')}</button>
      <img class="mtop-logo" src="heroplay-icon.svg" alt="Hero Play"><b class="mtop-nome">Hero Play</b>
      ${admInf() ? '' : `<div class="mtop-cr"><b>${me.saldo_creditos ?? 0}</b><span>cr</span></div>`}
    </header>
    <div class="side-bd" id="side-bd"></div>
    <aside class="side">
      <div class="side-top"><img class="side-logo" src="heroplay-icon.svg" alt="Hero Play"></div>
      <nav class="side-nav">${nav}</nav>
      <div class="side-user">
        <div class="user-card">
          <div class="user-av">${esc(inicial)}</div>
          <div class="user-meta"><div class="user-nome">${esc(me.nome || me.usuario)}</div><div class="user-papel">${esc(PAPEL_PT[me.papel] || me.papel)}</div></div>
          ${admInf() ? '' : `<div class="user-cr"><b id="u-saldo">${me.saldo_creditos ?? 0}</b><span>cr</span></div>`}
        </div>
        <button class="side-sair" id="sair">${svg('logout')}<span>Sair</span></button>
      </div>
    </aside>
    <main class="main"><div id="view"></div></main>
  </div>`
  const shell = app.querySelector('.shell')
  const fecharMenu = () => shell.classList.remove('nav-open')
  document.getElementById('hamb').onclick = () => shell.classList.toggle('nav-open')
  document.getElementById('side-bd').onclick = fecharMenu
  app.querySelectorAll('.nav-item').forEach((b) => { b.onclick = () => { fecharMenu(); irPara(b.dataset.view) } })
  document.getElementById('sair').onclick = sair
  irPara('dashboard')
}

function marcarNav(v) {
  const chave = v === 'cliente' ? 'clientes' : v
  app.querySelectorAll('.nav-item').forEach((b) => b.classList.toggle('on', b.dataset.view === chave))
}
const view = () => document.getElementById('view')

// Sequência de view: cada troca incrementa. As views assíncronas capturam o valor
// ao renderizar e ABANDONAM as escritas no DOM se a view mudou durante um await
// (senão dá "Cannot set innerHTML of null" ao escrever num #elemento já removido).
let _viewSeq = 0
const viewAtual = () => _viewSeq

function irPara(v, param) {
  _viewSeq++
  marcarNav(v)
  const fn = { dashboard: vDashboard, suporte: vSuporte, caixa: vCaixa, clientes: vClientes, cliente: vCliente, dispositivos: vDispositivos, playlists: vPlaylists, revendedores: vRevendedores, creditos: vCreditos, comprar: vComprar, indicacao: vIndicacao, parceiros: vParceiros, servidores: vServidores }[v]
  if (fn) fn(param)
}

// ── Login (split-screen: branding + formulário) ──────────────────────────────
function viewLogin(msg) {
  const ano = new Date().getFullYear()
  app.innerHTML = `<div class="login2">
    <div class="login2-brand">
      <div class="brand-inner">
        <img class="brand-logo" src="heroplay-icon.svg" alt="Hero Play">
        <div class="brand-label">Central de Revenda</div>
        <h1 class="brand-h1">Toda a sua <b>operação</b> num só painel.</h1>
        <p class="brand-sub">Dispositivos, playlists, clientes e créditos — organizados de ponta a ponta.</p>
      </div>
      <div class="brand-rodape">Hero Play © ${ano}</div>
    </div>
    <div class="login2-form">
      <div class="form-inner">
        <h2>Bem-vindo de volta</h2>
        <p class="form-sub">Entre no painel Hero Play</p>
        <label>Usuário</label>
        <input id="usuario" type="text" placeholder="seu_usuario" autocomplete="username" autocapitalize="none" spellcheck="false">
        <label>Senha</label>
        ${campoSenha('senha', 'current-password')}
        <button class="btn" id="entrar">Entrar</button>
        <div class="erro" id="erro">${msg ? esc(msg) : ''}</div>
      </div>
      <div class="form-rodape">Hero Play © ${ano}</div>
    </div>
  </div>`
  const entrar = async () => {
    document.getElementById('erro').textContent = ''
    const btn = document.getElementById('entrar'); btn.disabled = true
    // Login por USUÁRIO → e-mail sintético (o mesmo derivador da Edge Function).
    // Se digitar algo com "@" (ex.: admin com e-mail real de legado), usa literal.
    const entrada = document.getElementById('usuario').value.trim()
    const email = entrada.includes('@') ? entrada.toLowerCase() : usuarioParaEmail(entrada)
    const { error } = await sb.auth.signInWithPassword({ email, password: document.getElementById('senha').value })
    if (error) { document.getElementById('erro').textContent = 'Usuário ou senha inválidos.'; btn.disabled = false; return }
    iniciar()
  }
  document.getElementById('entrar').onclick = entrar
  document.getElementById('senha').onkeydown = (e) => { if (e.key === 'Enter') entrar() }
  ligarOlhos(app)
  document.getElementById('usuario').focus()
}
async function sair() { await sb.auth.signOut(); me = null; cache.clear(); viewLogin() }

// ── Modal genérico ───────────────────────────────────────────────────────────
// Atualiza o saldo em memória + em qualquer contador visível (topbar / créditos).
// `saldo` null = admin (crédito infinito) → não há número a atualizar.
function atualizarSaldo(saldo) {
  if (saldo === null || saldo === undefined) return
  if (saldo == null) return
  me.saldo_creditos = saldo
  const u = document.getElementById('u-saldo'); if (u) u.textContent = saldo
  const cr = document.getElementById('cr-saldo'); if (cr) cr.textContent = saldo
}

function abrirModal({ titulo, campos, okLabel = 'Salvar', onOk, aviso }) {
  const ov = document.createElement('div')
  ov.className = 'modal'
  ov.innerHTML = `<div class="modal-card"><h2>${esc(titulo)}</h2>
    ${aviso ? `<div class="modal-aviso">${aviso}</div>` : ''}
    ${campos.map((c) => `<label>${esc(c.label)}</label>${
      c.escolhas
        ? `<div class="opc" id="f-${c.id}" data-v="${esc(c.escolhas[0].v)}">${c.escolhas.map((o, i) => `
            <button type="button" class="opc-item${i === 0 ? ' on' : ''}" data-v="${esc(o.v)}">
              <span class="opc-ic">${svg(o.ic)}</span>
              <span class="opc-txt"><b>${esc(o.t)}</b>${o.d ? `<span>${esc(o.d)}</span>` : ''}</span>
              <span class="opc-check">${svg('check')}</span>
            </button>`).join('')}</div>`
        : c.options
        ? `<select id="f-${c.id}">${c.options.map((o) => `<option value="${esc(o.v)}">${esc(o.t)}</option>`).join('')}</select>`
        : c.type === 'textarea'
          ? `<textarea id="f-${c.id}" rows="4" placeholder="${esc(c.placeholder || '')}" autocomplete="off" spellcheck="false"></textarea>`
          : `<input id="f-${c.id}" type="${c.type || 'text'}" placeholder="${esc(c.placeholder || '')}" autocomplete="off" spellcheck="false" value="${esc(c.value || '')}"${c.format === 'mac' ? ' maxlength="17" class="modal-mac"' : ''}>`
    }`).join('')}
    <div class="modal-erro" id="m-erro"></div>
    <div class="modal-acoes"><button class="btn-sec" id="m-cancel">Cancelar</button><button class="btn" id="m-ok">${esc(okLabel)}</button></div>
  </div>`
  document.body.appendChild(ov)
  const err = (m) => { ov.querySelector('#m-erro').textContent = m || '' }
  const fechar = () => ov.remove()
  ov.querySelector('#m-cancel').onclick = fechar
  ov.onclick = (e) => { if (e.target === ov) fechar() }
  campos.forEach((c) => { if (c.format === 'mac') { const el = ov.querySelector('#f-' + c.id); el.addEventListener('input', () => { el.value = formatarMac(el.value) }) } })
  // Escolha em cartões: o valor vive no `data-v` do grupo (div não tem .value).
  ov.querySelectorAll('.opc').forEach((g) => {
    g.querySelectorAll('.opc-item').forEach((b) => {
      b.onclick = () => {
        g.dataset.v = b.dataset.v
        g.querySelectorAll('.opc-item').forEach((x) => x.classList.toggle('on', x === b))
      }
    })
  })
  const ok = async () => {
    const btn = ov.querySelector('#m-ok'); if (btn.disabled) return
    const vals = {}
    campos.forEach((c) => {
      const el = ov.querySelector('#f-' + c.id)
      vals[c.id] = el.value !== undefined ? el.value.trim() : (el.dataset.v || '')
    })
    const rot = btn.innerHTML
    btn.disabled = true; btn.classList.add('is-loading'); btn.innerHTML = '<span class="spin"></span> Processando…'
    const restaurar = () => { btn.disabled = false; btn.classList.remove('is-loading'); btn.innerHTML = rot }
    try { const e = await onOk(vals); if (e) { err(e); restaurar() } else fechar() } catch (ex) { err(ex.message); restaurar() }
  }
  ov.querySelector('#m-ok').onclick = ok
  // textarea entra na conta: no ticket o assunto já vem escolhido, então o
  // cursor tem que cair direto na descrição.
  const primeiro = ov.querySelector('input, select, textarea'); if (primeiro) primeiro.focus()
}
/**
 * PLANOS de ativação. `meses` só documenta aqui — quem calcula a data é o banco
 * (a RPC soma o intervalo), então o painel nunca inventa validade.
 *
 * `semestre` fica de fora da lista oferecida por decisão do usuário: hoje só
 * 1 ano e vitalícia. Está pronto no backend p/ quando for oferecido.
 */
const PLANOS = {
  ano: { rot: '1 ano', desc: 'Expira em 12 meses — precisa renovar', ic: 'coins' },
  vitalicia: { rot: 'Vitalícia', desc: 'Sem data de expiração', ic: 'shield' },
}
const planoRot = (p) => (PLANOS[p] || {}).rot || (p === 'semestre' ? '6 meses' : '—')
// Campo de escolha do plano, igual nos dois modais (vincular e renovar).
const campoPlano = () => ({
  id: 'plano', label: 'Plano da ativação',
  escolhas: Object.keys(PLANOS).map((k) => ({ v: k, t: PLANOS[k].rot, d: PLANOS[k].desc, ic: PLANOS[k].ic })),
})

function formatarMac(v) { const h = String(v).toUpperCase().replace(/[^0-9A-F]/g, '').slice(0, 12); return h.replace(/(.{2})(?=.)/g, '$1:') }

// Aviso do modal de ativação: o admin não gasta crédito, então pra ele o texto
// vira só o alerta de que a ação vale (não há custo nem saldo a mostrar).
const avisoAtivacao = () => admInf()
  ? 'Escolha o plano: <b>1 ano</b> expira e precisa de renovação; <b>vitalícia</b> não expira.'
  : `⚠️ Ativar este dispositivo <b>consome 1 crédito</b> e é <b>irreversível</b>. Seu saldo: <b>${me.saldo_creditos ?? 0}</b> crédito(s).`

// ── Modal do DISPOSITIVO (info + trocar playlist ativa + remover) ─────────────
function abrirModalDispositivo(d, playlists, vinculos, cliente_id, recarregar) {
  if (!d) return
  const vin = vinculos.find((x) => x.dispositivo_id === d.id && x.selecionada)
  const ativaId = vin ? vin.playlist_id : null
  const ov = document.createElement('div')
  ov.className = 'modal'
  ov.innerHTML = `<div class="modal-card modal-dev">
    <div class="mdev-head">
      <div class="mdev-id">
        <span class="mdev-icone" title="${esc(modeloNome(d.modelo))}">${modeloIcone(d.modelo)}</span>
        <div><div class="mdev-mac mono">${esc(d.mac)}</div><div class="mdev-key">Key ${esc(d.device_key)}</div></div>
      </div>
      <span class="badge badge-${esc(d.status)}">${esc(d.status)}</span>
    </div>
    <div class="mdev-info">
      <div><span>Aparelho</span><b>${esc(modeloNome(d.modelo))}</b></div>
      <div><span>Adicionado</span><b>${fmtDataHora(d.criado_em)}</b></div>
      <div><span>Ativado por</span><b>${esc(ATIVADO_POR_PT[d.ativado_por] || d.ativado_por || '—')}</b></div>
      <div><span>Última atividade</span><b>${d.atualizado_em ? fmtDataHora(d.atualizado_em) : '—'}</b></div>
      <div><span>Plano</span><b>${esc(planoRot(d.plano))}</b></div>
      <div><span>Expira</span><b>${d.expira_em ? fmtData(d.expira_em) : (d.plano === 'vitalicia' ? 'nunca' : '—')}</b></div>
      <div><span>Trial até</span><b>${d.trial_expira_em ? fmtData(d.trial_expira_em) : '—'}</b></div>
    </div>
    <div class="mdev-sec-t">Playlist ativa</div>
    ${playlists.length
      ? `<div class="mdev-pls">${playlists.map((p) => `<button class="mdev-pl${ativaId === p.id ? ' on' : ''}" data-pl="${esc(p.id)}">
          <span class="mdev-pl-nome">${esc(p.nome)}${p.tipo ? ` <i class="tipo">${esc(p.tipo)}</i>` : ''}</span>
          <span class="mdev-pl-tag">${ativaId === p.id ? 'ativa' : 'ativar'}</span></button>`).join('')}</div>`
      : `<div class="mdev-vazio">Este cliente não tem playlist. Adicione uma primeiro (bloco Playlists).</div>`}
    <div class="modal-erro" id="mdev-erro"></div>
    <div class="mdev-acoes">
      <button class="btn-danger" id="mdev-remover">Remover dispositivo</button>
      <button class="btn-sec" id="mdev-renovar">Renovar assinatura</button>
      <button class="btn-sec" id="mdev-fechar">Fechar</button>
    </div>
  </div>`
  document.body.appendChild(ov)
  const fechar = () => ov.remove()
  const err = (m) => { ov.querySelector('#mdev-erro').textContent = m || '' }
  ov.onclick = (e) => { if (e.target === ov) fechar() }
  ov.querySelector('#mdev-fechar').onclick = fechar
  ov.querySelectorAll('.mdev-pl').forEach((b) => { b.onclick = async () => {
    if (b.classList.contains('on')) return fechar()
    ov.querySelectorAll('.mdev-pl').forEach((x) => { x.disabled = true }); err('')
    try { await api('selecionar_playlist', { dispositivo_id: d.id, playlist_id: b.dataset.pl }); toast('Playlist ativada no dispositivo'); fechar(); recarregar() }
    catch (e) { err(e.message); ov.querySelectorAll('.mdev-pl').forEach((x) => { x.disabled = false }) }
  } })
  // Renovar SEMPRE cobra 1 crédito — é uma venda nova. Renovar antes de vencer
  // soma ao que resta (a conta é do banco), então ninguém perde dia pago.
  ov.querySelector('#mdev-renovar').onclick = () => {
    abrirModal({
      titulo: 'Renovar assinatura', okLabel: admInf() ? 'Renovar' : 'Renovar (1 crédito)',
      aviso: `Dispositivo <b>${esc(d.mac)}</b>. ${admInf() ? '' : 'Renovar <b>consome 1 crédito</b>. '}Se ainda não venceu, o novo prazo é somado ao que resta.`,
      campos: [campoPlano()],
      onOk: async (v) => {
        const r = await api('renovar_dispositivo', { dispositivo_id: d.id, plano: v.plano })
        atualizarSaldo(r.saldo)
        invalidar('dispositivos', 'cliente:' + cliente_id)
        toast(r.expira_em ? `Renovado até ${fmtData(r.expira_em)}` : 'Agora é vitalícia')
        fechar(); recarregar()
        return null
      },
    })
  }
  ov.querySelector('#mdev-remover').onclick = async () => {
    if (!confirm(`Remover o dispositivo ${d.mac}?\n\nEle sai deste cliente e volta a "sem lista". A ativação NÃO é reembolsada — re-ativar depois consome outro crédito.`)) return
    const rb = ov.querySelector('#mdev-remover'); rb.disabled = true; rb.textContent = 'Removendo…'; err('')
    try { await api('remover_dispositivo', { dispositivo_id: d.id }); toast('Dispositivo removido'); fechar(); recarregar() }
    catch (e) { err(e.message); rb.disabled = false; rb.textContent = 'Remover dispositivo' }
  }
}

// ── Dashboard ────────────────────────────────────────────────────────────────
const saudacao = () => { const h = new Date().getHours(); return h < 12 ? 'Bom dia' : h < 18 ? 'Boa tarde' : 'Boa noite' }
const dataHoje = () => new Date().toLocaleDateString('pt-BR', { weekday: 'long', day: 'numeric', month: 'long', year: 'numeric' })
  .replace(/(^|\s|-)([a-zà-ú])/g, (_m, p, c) => p + c.toUpperCase())

async function vDashboard() {
  view().innerHTML = `<div class="pg">
    <div class="dash-greet">${saudacao()}</div>
    <div class="pg-head"><div><h1>Dashboard</h1><p>${dataHoje()}</p></div><span class="badge badge-${esc(me.papel)}">${esc(PAPEL_PT[me.papel] || me.papel)}</span></div>
    <div class="stats" id="dash-stats"><div class="vazio">Carregando…</div></div>
    <div class="sec-label">Acesso rápido</div>
    <div class="quick">
      <button class="qbtn" data-go="clientes">${svg('zap')}<span>Ativar device</span></button>
      <button class="qbtn" data-go="clientes">${svg('listv')}<span>Adicionar playlist</span></button>
      <button class="qbtn" data-go="creditos">${svg('coins')}<span>Ver créditos</span></button>
      <button class="qbtn" data-go="indicacao">${svg('link')}<span>Indicação</span></button>
    </div>
  </div>`
  view().querySelectorAll('.qbtn').forEach((b) => { b.onclick = () => irPara(b.dataset.go) })
  const meu = viewAtual()
  try {
    const card = (ic, cor, val, lbl) => `<div class="stat"><div class="stat-ic" style="background:${cor}1f;color:${cor}">${svg(ic)}</div><div><b>${val}</b><span>${lbl}</span></div></div>`
    let html = admInf() ? '' : card('coins', '#E53935', me.saldo_creditos ?? 0, 'Créditos')
    const { clientes } = await pega('clientes', () => api('listar_clientes'))
    html += card('users', '#4f8ef7', clientes.length, 'Clientes')
    const { revendedores } = await pega('downline', () => api('listar_revendedores'))
    html += card('userplus', '#9b7bff', revendedores.length, 'Revendedores')
    if (me.papel === 'admin') {
      html += card('shield', '#7c5cff', revendedores.filter((r) => r.papel === 'master').length, 'Masters')
      // Parceiros é só do admin — e a conta não pode derrubar o resto do painel
      // se a tabela ainda não existir no banco.
      try {
        const { parceiros } = await pega('parceiros', () => api('listar_parceiros'))
        html += card('globe', '#34c759', parceiros.filter((p) => p.ativo).length, 'Parceiros')
      } catch (_) { /* sem parceiros: o dashboard segue */ }
    }
    if (meu !== viewAtual()) return
    document.getElementById('dash-stats').innerHTML = html
  } catch (e) {
    if (meu !== viewAtual()) return
    const el = document.getElementById('dash-stats'); if (el) el.innerHTML = `<div class="vazio">${esc(e.message)}</div>`
  }
}

// ── Clientes ─────────────────────────────────────────────────────────────────
async function vClientes() {
  view().innerHTML = `<div class="pg"><div class="pg-head"><div><h1>Clientes</h1><p id="cli-sub">Carregando…</p></div>
    <button class="btn" id="novo-cli">${svg('plus')} Novo cliente</button></div>
    <div class="lista" id="cli-lista"><div class="vazio">Carregando…</div></div></div>`
  document.getElementById('novo-cli').onclick = () => abrirModal({
    titulo: 'Novo cliente', okLabel: 'Criar', campos: [{ id: 'nome', label: 'Nome do cliente', placeholder: 'Ex.: Gabriel' }],
    onOk: async (v) => { if (!v.nome) return 'Informe o nome'; await api('criar_cliente', { nome: v.nome }); invalidar('clientes'); toast('Cliente criado'); vClientes(); return null },
  })
  const meu = viewAtual()
  try {
    const { clientes } = await pega('clientes', () => api('listar_clientes'))
    if (meu !== viewAtual()) return
    document.getElementById('cli-sub').textContent = `${clientes.length} cliente${clientes.length !== 1 ? 's' : ''}`
    const el = document.getElementById('cli-lista')
    if (!clientes.length) { el.innerHTML = '<div class="vazio">Nenhum cliente ainda. Crie o primeiro.</div>'; return }
    el.innerHTML = clientes.map((c) => `<button class="row" data-id="${esc(c.id)}"><div><div class="row-nome">${esc(c.nome)}</div><div class="row-sub">Criado ${fmtData(c.criado_em)}</div></div><span class="row-arrow">›</span></button>`).join('')
    el.querySelectorAll('.row').forEach((b) => { b.onclick = () => irPara('cliente', b.dataset.id) })
  } catch (e) { toast(e.message, true) }
}

async function vCliente(cliente_id) {
  const chaveCache = 'cliente:' + cliente_id
  view().innerHTML = `<div class="pg"><button class="btn-sec pg-back" id="voltar">← Clientes</button><div id="cli-det"><div class="vazio">Carregando…</div></div></div>`
  document.getElementById('voltar').onclick = () => irPara('clientes')
  const meu = viewAtual()
  let det
  try { det = await pega(chaveCache, () => api('cliente_detalhe', { cliente_id })) } catch (e) { toast(e.message, true); return }
  if (meu !== viewAtual()) return
  const { cliente, dispositivos, playlists, vinculos } = det
  const ativaDe = (did) => { const v = vinculos.find((x) => x.dispositivo_id === did && x.selecionada); return v ? v.playlist_id : null }
  const nomePl = (pid) => { const p = playlists.find((x) => x.id === pid); return p ? p.nome : null }
  document.getElementById('cli-det').innerHTML = `
    <div class="pg-head"><div><h1>${esc(cliente.nome)}</h1><p>${dispositivos.length} dispositivo(s) · ${playlists.length} playlist(s)</p></div></div>
    <div class="grid2">
      <section class="bloco">
        <div class="bloco-head"><h2>Dispositivos</h2><button class="btn" id="vincular">${svg('plus')} Vincular</button></div>
        ${dispositivos.length ? dispositivos.map((d) => `
          <button class="dev" data-id="${esc(d.id)}">
            <div class="dev-top"><span class="dev-icone">${modeloIcone(d.modelo)}</span><b class="mono">${esc(d.mac)}</b> <span class="badge badge-${esc(d.status)}">${esc(d.status)}</span></div>
            <div class="dev-sub">${esc(modeloNome(d.modelo))} · Key ${esc(d.device_key)} · <span title="${fmtDataHora(d.criado_em)}">adic. ${fmtData(d.criado_em)}</span></div>
            <div class="dev-sel">Ativa: ${ativaDe(d.id) ? esc(nomePl(ativaDe(d.id))) : '<i>nenhuma</i>'}<span class="dev-arrow">›</span></div>
          </button>`).join('') : '<div class="vazio">Nenhum dispositivo. Vincule pela Key mostrada na TV.</div>'}
      </section>
      <section class="bloco">
        <div class="bloco-head"><h2>Playlists</h2><button class="btn" id="add-pl">${svg('plus')} Adicionar</button></div>
        ${playlists.length ? playlists.map((p) => `<div class="pl"><div><b>${esc(p.nome)}</b><span class="tipo">${esc(p.tipo || '')}</span></div><button class="btn-del" data-pl="${esc(p.id)}">excluir</button></div>`).join('') : '<div class="vazio">Nenhuma playlist. Adicione e vai p/ todos os dispositivos.</div>'}
      </section>
    </div>`
  const recarregar = () => { invalidar(chaveCache); irPara('cliente', cliente_id) }
  document.getElementById('vincular').onclick = () => abrirModal({
    titulo: 'Vincular dispositivo', okLabel: admInf() ? 'Ativar' : 'Ativar (1 crédito)',
    aviso: avisoAtivacao(),
    campos: [
      { id: 'mac', label: 'MAC', placeholder: 'AA:BB:CC:DD:EE:FF', format: 'mac' },
      { id: 'key', label: 'Key', placeholder: '000000' },
      campoPlano(),
    ],
    onOk: async (v) => {
      if (v.mac.length !== 17) return 'MAC incompleto'
      if (!v.key) return 'Informe a Key'
      const r = await api('vincular_dispositivo', { cliente_id, mac: v.mac, key: v.key, plano: v.plano })
      atualizarSaldo(r.saldo)
      toast(r.cobrado ? `Ativado (${planoRot(r.plano)}) — −1 crédito` : 'Dispositivo vinculado')
      recarregar()
      return null
    },
  })
  document.getElementById('add-pl').onclick = () => abrirModal({
    titulo: 'Adicionar playlist', okLabel: 'Adicionar',
    campos: [{ id: 'nome', label: 'Nome', placeholder: 'Ex.: Gabriel' }, { id: 'url', label: 'URL da lista (M3U/Xtream)', placeholder: 'http://...' }, { id: 'epg', label: 'EPG (opcional)', placeholder: 'http://...' }],
    onOk: async (v) => { if (!/^https?:\/\//i.test(v.url)) return 'URL inválida (http/https)'; await api('add_playlist', { cliente_id, nome: v.nome || 'Playlist', lista_url: v.url, epg_url: v.epg }); toast('Playlist adicionada'); recarregar(); return null },
  })
  document.querySelectorAll('.dev').forEach((b) => { b.onclick = () => abrirModalDispositivo(dispositivos.find((x) => x.id === b.dataset.id), playlists, vinculos, cliente_id, recarregar) })
  document.querySelectorAll('.btn-del').forEach((b) => { b.onclick = async () => { if (!confirm('Excluir esta playlist?')) return; try { await api('excluir_playlist', { cliente_id, playlist_id: b.dataset.pl }); toast('Excluída'); recarregar() } catch (e) { toast(e.message, true) } } })
}

// ── Revendedores (downline DIRETO; admin promove/rebaixa o tier Master) ───────
async function vRevendedores() {
  const ehAdmin = me.papel === 'admin'
  view().innerHTML = `<div class="pg"><div class="pg-head"><div><h1>Revendedores</h1><p id="dl-sub">${ehAdmin ? 'Todos os revendedores da plataforma' : 'Sua rede direta'}</p></div>
    <button class="btn-sec" id="ir-indicacao">${svg('link')} Meu link de indicação</button></div>
    <div class="tbl-wrap" id="dl-tbl"><div class="vazio">Carregando…</div></div></div>`
  document.getElementById('ir-indicacao').onclick = () => irPara('indicacao')
  const meu = viewAtual()
  try {
    const { revendedores } = await pega('downline', () => api('listar_revendedores'))
    if (meu !== viewAtual()) return
    document.getElementById('dl-sub').textContent = ehAdmin
      ? `${revendedores.length} revendedor(es) na plataforma`
      : `${revendedores.length} revendedor(es) direto(s)`
    const el = document.getElementById('dl-tbl')
    if (!revendedores.length) { el.innerHTML = '<div class="vazio">Ninguém se cadastrou pelo seu link ainda. Compartilhe seu link em <b>Indicação</b>.</div>'; return }
    el.innerHTML = `<table><thead><tr><th>Nome</th>${ehAdmin ? '<th>Indicado por</th>' : ''}<th>Tier</th><th>Créditos</th><th>Status</th><th></th></tr></thead><tbody>
      ${revendedores.map((r) => `<tr>
        <td><b>${esc(r.nome || '—')}</b><div class="row-sub">@${esc(r.usuario || "—")}</div></td>
        ${ehAdmin ? `<td>${r.indicado_por
          ? `${esc(r.indicado_por)}<div class="row-sub mono">${esc(r.indicado_por_codigo || '—')}</div>`
          : '<span class="row-sub">— cadastro direto</span>'}</td>` : ''}
        <td><span class="badge badge-${r.papel === 'master' ? 'master' : 'reseller'}">${r.papel === 'master' ? 'Master' : 'Comum'}</span></td>
        <td class="tnum">${r.saldo_creditos ?? 0}</td>
        <td><span class="badge badge-${r.ativo ? 'ativo' : 'expirado'}">${r.ativo ? 'ativo' : 'inativo'}</span></td>
        <td class="acoes-dl">
          <button class="btn-sec" data-acao="transferir" data-id="${esc(r.id)}" data-nome="${esc(r.nome || r.usuario)}">${svg('send')} Transferir</button>
          ${ehAdmin ? `<button class="btn-sec" data-acao="tier" data-id="${esc(r.id)}" data-tier="${r.papel === 'master' ? 'reseller' : 'master'}">${r.papel === 'master' ? 'Rebaixar' : 'Promover a Master'}</button>` : ''}
        </td>
      </tr>`).join('')}</tbody></table>`
    el.querySelectorAll('[data-acao="transferir"]').forEach((b) => { b.onclick = () => abrirModal({
      titulo: 'Transferir créditos', okLabel: 'Transferir',
      campos: [{ id: 'qtd', label: admInf()
        ? `Quantidade → ${b.dataset.nome}`
        : `Quantidade (seu saldo: ${me.saldo_creditos ?? 0}) → ${b.dataset.nome}`, type: 'number', placeholder: '0' }],
      onOk: async (v) => {
        const q = parseInt(v.qtd, 10)
        if (!q || q <= 0) return 'Quantidade inválida'
        const r = await api('transferir_creditos', { revendedor_id: b.dataset.id, quantidade: q })
        atualizarSaldo(r.saldo)          // null p/ admin → não mexe em nada
        invalidar('downline', 'creditos')
        toast('Créditos transferidos')
        vRevendedores()
        return null
      },
    }) })
    el.querySelectorAll('[data-acao="tier"]').forEach((b) => { b.onclick = async () => { try { await api('promover', { revendedor_id: b.dataset.id, tier: b.dataset.tier }); invalidar('downline'); toast(b.dataset.tier === 'master' ? 'Promovido a Master' : 'Rebaixado a comum'); vRevendedores() } catch (e) { toast(e.message, true) } } })
  } catch (e) { toast(e.message, true) }
}

// ── Créditos (extrato) ───────────────────────────────────────────────────────
async function vCreditos() {
  view().innerHTML = `<div class="pg"><div class="pg-head"><div><h1>Créditos</h1><p>${
    admInf() ? 'Você distribui crédito para os revendedores — seu saldo é ilimitado' : 'Seu saldo e histórico de movimentos'}</p></div></div>
    <div class="stats"><div class="stat"><div class="stat-ic" style="background:#E539351f;color:#E53935">${svg('coins')}</div><div>${
    admInf() ? '<b class="cr-inf">∞</b><span>Crédito ilimitado</span>'
      : `<b id="cr-saldo">${me.saldo_creditos ?? 0}</b><span>Saldo atual</span>`}</div></div></div>
    <div class="tbl-wrap" id="cr-tbl"><div class="vazio">Carregando…</div></div></div>`
  const meu = viewAtual()
  try {
    const { saldo, transacoes } = await pega('creditos', () => api('listar_creditos'))
    if (meu !== viewAtual()) return
    atualizarSaldo(saldo)   // admin: saldo vem null e nada é exibido
    const cs = document.getElementById('cr-saldo'); if (cs && saldo !== null) cs.textContent = saldo
    const el = document.getElementById('cr-tbl')
    if (!transacoes.length) { el.innerHTML = '<div class="vazio">Nenhum movimento ainda.</div>'; return }
    const rotulo = { adicionado: 'Adicionado', consumido: 'Consumido', transferido_saida: 'Transferido', transferido_entrada: 'Recebido' }
    el.innerHTML = `<table><thead><tr><th>Tipo</th><th>Qtd</th><th>Saldo após</th><th>Nota</th><th>Data</th></tr></thead><tbody>
      ${transacoes.map((t) => `<tr>
        <td>${esc(rotulo[t.tipo] || t.tipo)}</td>
        <td class="${t.quantidade >= 0 ? 'pos' : 'neg'} tnum">${t.quantidade >= 0 ? '+' : ''}${t.quantidade}</td>
        <td class="tnum">${t.saldo_apos ?? '—'}</td>
        <td>${esc(t.nota || '—')}</td>
        <td class="tnum">${fmtData(t.criado_em)}</td>
      </tr>`).join('')}</tbody></table>`
  } catch (e) { toast(e.message, true) }
}

// ── Caixa de entrada ─────────────────────────────────────────────────────────
// Tudo o que chega para este usuário: ticket respondido, crédito recebido,
// revendedor novo na rede e aviso do admin. Para o admin, é aqui que caem os
// tickets abertos pelos revendedores (e, no futuro, os e-mails).
const NOTIF_IC = { ticket: 'lifebuoy', credito: 'coins', rede: 'userplus', aviso: 'bell' }
const NOTIF_COR = { ticket: '#4f8ef7', credito: '#E53935', rede: '#9b7bff', aviso: '#d9a23e' }

async function vCaixa() {
  const admin = me.papel === 'admin'
  view().innerHTML = `<div class="pg">
    <div class="pg-head"><div><h1>Caixa de entrada</h1><p id="cx-sub">Carregando…</p></div>
      <div class="pg-acoes">
        ${admin ? `<button class="btn-sec" id="cx-aviso">${svg('bell')} Enviar aviso</button>` : ''}
        <button class="btn-sec" id="cx-ler">Marcar tudo como lido</button>
      </div></div>
    <div class="lista" id="cx-lista"><div class="vazio">Carregando…</div></div>
  </div>`

  const meu = viewAtual()
  const carregar = async () => {
    try {
      const { notificacoes, nao_lidas } = await api('listar_notificacoes')
      if (meu !== viewAtual()) return
      atualizarBadgeCaixa(nao_lidas)
      const sub = document.getElementById('cx-sub')
      if (sub) sub.textContent = nao_lidas ? `${nao_lidas} não lida(s)` : 'Tudo lido'
      const l = document.getElementById('cx-lista'); if (!l) return
      if (!notificacoes.length) {
        l.innerHTML = '<div class="vazio">Nada por aqui ainda. Avisos de tickets, créditos e novos revendedores aparecem nesta caixa.</div>'
        return
      }
      l.innerHTML = notificacoes.map((n) => {
        const cor = NOTIF_COR[n.tipo] || '#8a8a8a'
        return `<button class="row cx-row${n.lida ? '' : ' cx-nova'}" data-id="${esc(n.id)}" data-tipo="${esc(n.tipo)}" data-ref="${esc(n.ref || '')}">
          <div class="cx-ic" style="background:${cor}1f;color:${cor}">${svg(NOTIF_IC[n.tipo] || 'bell')}</div>
          <div style="min-width:0;flex:1">
            <div class="row-nome">${n.lida ? '' : '<span class="cx-dot"></span>'}${esc(n.titulo)}</div>
            <div class="row-sub">${esc(n.corpo || '')}</div>
          </div>
          <div class="row-sub cx-quando">${fmtDataHora(n.criado_em)}</div>
        </button>`
      }).join('')
      l.querySelectorAll('.cx-row').forEach((b) => {
        b.onclick = async () => {
          try { await api('ler_notificacoes', { id: b.dataset.id }) } catch (_) { /* marcar lida nao e critico */ }
          // Aviso de ticket abre o próprio ticket — sem isso o usuário teria
          // que caçar o ticket na aba do lado.
          if (b.dataset.tipo === 'ticket' && b.dataset.ref) abrirTicket(b.dataset.ref, carregar)
          else carregar()
        }
      })
    } catch (e) {
      if (meu !== viewAtual()) return
      const l = document.getElementById('cx-lista'); if (l) l.innerHTML = `<div class="vazio">${esc(e.message)}</div>`
    }
  }

  document.getElementById('cx-ler').onclick = async () => {
    try { await api('ler_notificacoes'); toast('Tudo marcado como lido'); carregar() } catch (e) { toast(e.message, true) }
  }
  const bAviso = document.getElementById('cx-aviso')
  if (bAviso) bAviso.onclick = () => abrirModal({
    titulo: 'Enviar aviso', okLabel: 'Enviar',
    aviso: 'O aviso cai na caixa de entrada de <b>todos os revendedores ativos</b>.',
    campos: [
      { id: 'titulo', label: 'Título', placeholder: 'Ex.: Manutenção programada' },
      { id: 'corpo', label: 'Mensagem', type: 'textarea', placeholder: 'Detalhe o aviso…' },
    ],
    onOk: async (v) => {
      if (!v.titulo) return 'Informe o título'
      const r = await api('enviar_aviso', { titulo: v.titulo, corpo: v.corpo })
      toast(`Aviso enviado para ${r.enviados} revendedor(es)`); return null
    },
  })
  carregar()
}

/** Bolinha com o número de não lidas no item do menu. */
function atualizarBadgeCaixa(n) {
  const item = document.querySelector('.nav-item[data-view="caixa"]')
  if (!item) return
  let b = item.querySelector('.nav-badge')
  if (!n) { if (b) b.remove(); return }
  if (!b) { b = document.createElement('span'); b.className = 'nav-badge'; item.appendChild(b) }
  b.textContent = n > 99 ? '99+' : String(n)
}

/** Consulta o total de não lidas (sem abrir a caixa) para o menu já nascer certo. */
async function checarCaixa() {
  try { const { nao_lidas } = await api('listar_notificacoes'); atualizarBadgeCaixa(nao_lidas) } catch (_) { /* silencioso */ }
}

// ── Suporte (tickets) — real: revendedor abre; admin vê todos, responde e encerra
const TICKET_ST = { aberto: 'Aberto', respondido: 'Respondido', fechado: 'Fechado' }
async function vSuporte() {
  const admin = me.papel === 'admin'
  view().innerHTML = `<div class="pg">
    <div class="pg-head"><div><h1>Suporte</h1><p id="sup-sub">${admin ? 'Todos os tickets — responda e encerre' : 'Seus tickets de suporte'}</p></div>
      <button class="btn" id="novo-ticket">${svg('plus')} Novo ticket</button></div>
    <div class="filtros">
      <div class="pills" id="sup-fst">${pills('Status', [['', 'Todos'], ['aberto', 'Abertos'], ['respondido', 'Respondidos'], ['fechado', 'Fechados']])}</div>
      <div class="pills" id="sup-ftp">${pills('Assunto', [['', 'Todos'], ['financeiro', 'Financeiro'], ['tecnico', 'Técnico'], ['login', 'Login']])}</div>
    </div>
    <div class="lista" id="sup-lista"><div class="vazio">Carregando…</div></div>
  </div>`
  document.getElementById('novo-ticket').onclick = novoTicket
  const st = { status: '', topico: '' }
  const meu = viewAtual()
  const carregar = async () => {
    const el = document.getElementById('sup-lista'); if (el) el.innerHTML = '<div class="vazio">Carregando…</div>'
    try {
      let { tickets } = await api('listar_tickets', { status: st.status })
      // O filtro de assunto e local: a lista ja vem inteira e e curta.
      if (st.topico) tickets = tickets.filter((t) => (t.topico || '') === st.topico)
      if (meu !== viewAtual()) return
      const l = document.getElementById('sup-lista'); if (!l) return
      if (!tickets.length) { l.innerHTML = '<div class="vazio">Nenhum ticket aqui.</div>'; return }
      l.innerHTML = tickets.map((t) => `
        <button class="row sup-row" data-id="${esc(t.id)}">
          <div style="min-width:0">
            <div class="row-nome">${esc(t.assunto)}</div>
            <div class="row-sub">${admin ? 'de ' + esc(t.de) + ' · ' : ''}atualizado ${fmtDataHora(t.atualizado_em)}</div>
          </div>
          <span class="badge badge-tk-${esc(t.status)}">${esc(TICKET_ST[t.status] || t.status)}</span>
        </button>`).join('')
      l.querySelectorAll('.sup-row').forEach((b) => { b.onclick = () => abrirTicket(b.dataset.id, carregar) })
    } catch (e) { if (meu !== viewAtual()) return; const l = document.getElementById('sup-lista'); if (l) l.innerHTML = `<div class="vazio">${esc(e.message)}</div>` }
  }
  wirePills(document.getElementById('sup-fst'), (v) => { st.status = v; carregar() })
  wirePills(document.getElementById('sup-ftp'), (v) => { st.topico = v; carregar() })
  carregar()
}

// Assunto deixou de ser texto livre: o revendedor escolhe o TOPICO e so
// descreve o problema. Isso deixa o suporte triar por categoria e acaba com
// assunto vago do tipo "ajuda".
const TICKET_TOPICOS = [
  { v: 'financeiro', t: 'Financeiro', d: 'Créditos, cobrança, pagamento', ic: 'coins' },
  { v: 'tecnico', t: 'Técnico', d: 'App, dispositivo, playlist', ic: 'zap' },
  { v: 'login', t: 'Login', d: 'Acesso à conta do painel', ic: 'shield' },
]

function novoTicket() {
  abrirModal({
    titulo: 'Novo ticket', okLabel: 'Abrir ticket',
    campos: [
      // `escolhas` (não `options`): são três opções fixas e com descrição — cabem
      // na tela inteiras, sem obrigar a abrir uma lista pra ler cada uma.
      { id: 'topico', label: 'Assunto', escolhas: TICKET_TOPICOS },
      { id: 'msg', label: 'Descrição', type: 'textarea', placeholder: 'Conte o que está acontecendo…' },
    ],
    onOk: async (v) => {
      if (!v.msg) return 'Descreva o problema'
      await api('criar_ticket', { topico: v.topico, mensagem: v.msg })
      toast('Ticket aberto'); vSuporte(); return null
    },
  })
}

// Modal da thread do ticket: histórico + responder + encerrar/reabrir.
async function abrirTicket(id, recarregar) {
  let det
  try { det = await api('ticket_detalhe', { ticket_id: id }) } catch (e) { toast(e.message, true); return }
  const { ticket, mensagens, admin } = det
  const ov = document.createElement('div'); ov.className = 'modal'
  const bolhas = (msgs) => msgs.map((m) => `
    <div class="tk-msg ${m.do_admin ? 'tk-adm' : 'tk-cli'}">
      <div class="tk-msg-quem">${m.do_admin ? 'Suporte' : esc(ticket.de)} · ${fmtDataHora(m.criado_em)}</div>
      <div class="tk-msg-corpo">${esc(m.corpo).replace(/\n/g, '<br>')}</div>
    </div>`).join('')
  const fechado = ticket.status === 'fechado'
  ov.innerHTML = `<div class="modal-card modal-tk">
    <div class="tk-head">
      <div><div class="tk-assunto">${esc(ticket.assunto)}</div><div class="tk-de">${admin ? 'de ' + esc(ticket.de) + ' · ' : ''}<span class="badge badge-tk-${esc(ticket.status)}">${esc(TICKET_ST[ticket.status] || ticket.status)}</span></div></div>
    </div>
    <div class="tk-thread" id="tk-thread">${bolhas(mensagens)}</div>
    <div class="modal-erro" id="tk-erro"></div>
    <textarea id="tk-resp" class="tk-resp" placeholder="${fechado ? 'Ticket fechado — reabra para responder' : 'Escreva sua resposta…'}"${fechado ? ' disabled' : ''}></textarea>
    <div class="tk-acoes">
      <button class="btn-sec" id="tk-fechar-modal">Fechar janela</button>
      <div style="display:flex;gap:10px">
        ${fechado
          ? `<button class="btn-sec" id="tk-reabrir">Reabrir</button>`
          : `<button class="btn-sec" id="tk-encerrar">Encerrar ticket</button><button class="btn" id="tk-enviar">Responder</button>`}
      </div>
    </div>
  </div>`
  document.body.appendChild(ov)
  const fechar = () => { ov.remove(); if (recarregar) recarregar() }
  const err = (m) => { ov.querySelector('#tk-erro').textContent = m || '' }
  ov.onclick = (e) => { if (e.target === ov) fechar() }
  ov.querySelector('#tk-fechar-modal').onclick = fechar
  const thread = ov.querySelector('#tk-thread'); thread.scrollTop = thread.scrollHeight
  const enviar = ov.querySelector('#tk-enviar')
  if (enviar) enviar.onclick = async () => {
    const msg = ov.querySelector('#tk-resp').value.trim(); if (!msg) return err('Escreva uma resposta')
    enviar.disabled = true; err('')
    try {
      await api('responder_ticket', { ticket_id: id, mensagem: msg })
      const d = await api('ticket_detalhe', { ticket_id: id })
      thread.innerHTML = bolhas(d.mensagens); thread.scrollTop = thread.scrollHeight
      ov.querySelector('#tk-resp').value = ''; toast('Resposta enviada')
    } catch (e) { err(e.message) } finally { enviar.disabled = false }
  }
  const enc = ov.querySelector('#tk-encerrar')
  if (enc) enc.onclick = async () => { try { await api('fechar_ticket', { ticket_id: id }); toast('Ticket encerrado'); fechar() } catch (e) { err(e.message) } }
  const reab = ov.querySelector('#tk-reabrir')
  if (reab) reab.onclick = async () => { try { await api('fechar_ticket', { ticket_id: id, reabrir: true }); toast('Ticket reaberto'); fechar() } catch (e) { err(e.message) } }
}

// ── Helpers de filtro (pílulas) ──────────────────────────────────────────────
function pills(label, opts) {
  return `<span class="pill-lbl">${esc(label)}:</span>` + opts.map(([v, t], i) => `<button class="pill${i === 0 ? ' on' : ''}" data-v="${esc(v)}">${esc(t)}</button>`).join('')
}
function wirePills(container, onChange) {
  container.querySelectorAll('.pill').forEach((p) => { p.onclick = () => { container.querySelectorAll('.pill').forEach((x) => x.classList.remove('on')); p.classList.add('on'); onChange(p.dataset.v) } })
}
const statCard = (ic, cor, val, lbl) => `<div class="stat"><div class="stat-ic" style="background:${cor}1f;color:${cor}">${svg(ic)}</div><div><b>${val}</b><span>${lbl}</span></div></div>`

// ── Dispositivos (visão global do operador; busca + filtros) ──────────────────
async function vDispositivos() {
  view().innerHTML = `<div class="pg">
    <div class="pg-head"><div><h1>Dispositivos</h1><p id="dv-sub">Carregando…</p></div>
      <button class="btn" id="dv-vinc">${svg('link')} Vincular Device</button></div>
    <div class="stats" id="dv-stats"></div>
    <div class="filtros">
      <input class="busca" id="dv-q" placeholder="Buscar MAC, Key, modelo, cliente…">
      <div class="pills" id="dv-fst">${pills('Status', [['', 'Todos'], ['ativo', 'Ativo'], ['trial', 'Trial'], ['expirado', 'Expirado'], ['sem_lista', 'Sem lista'], ['banido', 'Banido']])}</div>
    </div>
    <div class="tbl-wrap" id="dv-tbl"><div class="vazio">Carregando…</div></div>
  </div>`
  document.getElementById('dv-vinc').onclick = modalVincularGlobal
  const meu = viewAtual()
  let dados = []
  const st = { q: '', status: '' }
  const render = () => {
    const f = dados.filter((d) => {
      if (st.status && (d.status || '') !== st.status) return false
      if (st.q && !`${d.mac} ${d.device_key} ${d.modelo || ''} ${modeloNome(d.modelo)} ${d.cliente || ''}`.toLowerCase().includes(st.q.toLowerCase())) return false
      return true
    })
    const el = document.getElementById('dv-tbl')
    if (!f.length) { el.innerHTML = '<div class="vazio">Nenhum dispositivo.</div>'; return }
    el.innerHTML = `<table><thead><tr><th>MAC</th><th>Key</th><th>Modelo</th><th>Cliente</th><th>Plano</th><th>Status</th><th>Expira</th><th>Trial</th><th>Criado</th></tr></thead><tbody>
      ${f.map((d) => `<tr>
        <td class="mono">${esc(d.mac)}</td><td class="mono">${esc(d.device_key)}</td>
        <td><span class="mdl-ico">${modeloIcone(d.modelo)}</span> ${esc(modeloNome(d.modelo))}</td><td>${esc(d.cliente || '—')}</td>
        <td>${esc(planoRot(d.plano))}</td>
        <td><span class="badge badge-${esc(d.status)}">${esc(d.status)}</span></td>
        <td class="tnum">${d.expira_em ? fmtData(d.expira_em) : (d.plano === 'vitalicia' ? 'nunca' : '—')}</td>
        <td class="tnum">${d.trial_expira_em ? fmtData(d.trial_expira_em) : '—'}</td>
        <td class="tnum">${fmtData(d.criado_em)}</td>
      </tr>`).join('')}</tbody></table>`
  }
  document.getElementById('dv-q').oninput = (e) => { st.q = e.target.value; render() }
  wirePills(document.getElementById('dv-fst'), (v) => { st.status = v; render() })
  try {
    const r = await pega('dispositivos', () => api('listar_dispositivos'))
    if (meu !== viewAtual()) return
    dados = r.dispositivos || []
    document.getElementById('dv-sub').textContent = `${dados.length} dispositivo(s)`
    const c = (s) => dados.filter((d) => d.status === s).length
    document.getElementById('dv-stats').innerHTML =
      statCard('monitor', '#4f8ef7', dados.length, 'Total') + statCard('shield', '#34c759', c('ativo'), 'Ativos') +
      statCard('coins', '#e8b23a', c('trial'), 'Trial') + statCard('globe', '#ff5b54', c('expirado'), 'Expirados')
    render()
  } catch (e) {
    if (meu !== viewAtual()) return
    const el = document.getElementById('dv-tbl'); if (el) el.innerHTML = `<div class="vazio">${esc(e.message)}</div>`
  }
}

async function modalVincularGlobal() {
  let clientes = []
  try { const r = await pega('clientes', () => api('listar_clientes')); clientes = r.clientes || [] } catch (_) {}
  if (!clientes.length) { toast('Crie um cliente primeiro', true); irPara('clientes'); return }
  abrirModal({
    titulo: 'Vincular dispositivo', okLabel: admInf() ? 'Ativar' : 'Ativar (1 crédito)',
    aviso: avisoAtivacao(),
    campos: [
      { id: 'cliente_id', label: 'Cliente', options: clientes.map((c) => ({ v: c.id, t: c.nome })) },
      { id: 'mac', label: 'MAC', placeholder: 'AA:BB:CC:DD:EE:FF', format: 'mac' },
      { id: 'key', label: 'Key', placeholder: '000000' },
      campoPlano(),
    ],
    onOk: async (v) => {
      if (v.mac.length !== 17) return 'MAC incompleto'
      if (!v.key) return 'Informe a Key'
      const r = await api('vincular_dispositivo', { cliente_id: v.cliente_id, mac: v.mac, key: v.key, plano: v.plano })
      atualizarSaldo(r.saldo)
      invalidar('dispositivos', 'cliente:' + v.cliente_id)
      toast(r.cobrado ? `Ativado (${planoRot(r.plano)}) — −1 crédito` : 'Dispositivo vinculado')
      vDispositivos()
      return null
    },
  })
}

// ── Playlists (visão global; busca + filtros + Migrar URL) ────────────────────
async function vPlaylists() {
  view().innerHTML = `<div class="pg">
    <div class="pg-head"><div><h1>Playlists</h1><p id="pl-sub">Carregando…</p></div>
      <button class="btn-sec" id="pl-migrar">${svg('send')} Migrar URL</button></div>
    <div class="stats" id="pl-stats"></div>
    <div class="filtros">
      <input class="busca" id="pl-q" placeholder="Buscar nome, cliente, URL…">
      <div class="pills" id="pl-fsel">${pills('Selecionada', [['', 'Todos'], ['sim', 'Sim'], ['nao', 'Não']])}</div>
      <div class="pills" id="pl-fpin">${pills('PIN', [['', 'Todos'], ['sim', 'Com PIN'], ['nao', 'Sem PIN']])}</div>
    </div>
    <div class="tbl-wrap" id="pl-tbl"><div class="vazio">Carregando…</div></div>
  </div>`
  document.getElementById('pl-migrar').onclick = modalMigrarUrl
  const meu = viewAtual()
  let dados = []
  const st = { q: '', sel: '', pin: '' }
  const ck = (b) => b ? '<span class="ck-s">✓</span>' : '<span class="ck-n">✗</span>'
  const render = () => {
    const f = dados.filter((p) => {
      if (st.sel === 'sim' && !p.selecionada) return false
      if (st.sel === 'nao' && p.selecionada) return false
      if (st.pin === 'sim' && !p.pin) return false
      if (st.pin === 'nao' && p.pin) return false
      if (st.q && !`${p.nome} ${p.cliente} ${p.url}`.toLowerCase().includes(st.q.toLowerCase())) return false
      return true
    })
    const el = document.getElementById('pl-tbl')
    if (!f.length) { el.innerHTML = '<div class="vazio">Nenhuma playlist.</div>'; return }
    el.innerHTML = `<table><thead><tr><th>Nome</th><th>Cliente</th><th>Tipo</th><th>URL</th><th>Free DNS</th><th>PIN</th><th>Selecionada</th><th>Criado</th><th></th></tr></thead><tbody>
      ${f.map((p) => `<tr>
        <td><b>${esc(p.nome)}</b></td><td>${esc(p.cliente || '—')}</td>
        <td><span class="tipo">${esc(p.tipo || '')}</span></td>
        <td class="url-cel mono" title="${esc(p.url)}">${esc(p.url || '—')}</td>
        <td>${ck(p.free_dns)}</td>
        <td>${p.pin ? '<span class="pin-on">🔒</span>' : '<span class="ck-n">—</span>'}</td>
        <td>${ck(p.selecionada)}</td>
        <td class="tnum">${fmtData(p.criado_em)}</td>
        <td><button class="btn-del" data-id="${esc(p.id)}" data-cli="${esc(p.cliente_id)}">excluir</button></td>
      </tr>`).join('')}</tbody></table>`
    el.querySelectorAll('.btn-del').forEach((b) => { b.onclick = async () => { if (!confirm('Excluir esta playlist?')) return; try { await api('excluir_playlist', { cliente_id: b.dataset.cli, playlist_id: b.dataset.id }); invalidar('playlists'); toast('Excluída'); vPlaylists() } catch (e) { toast(e.message, true) } } })
  }
  document.getElementById('pl-q').oninput = (e) => { st.q = e.target.value; render() }
  wirePills(document.getElementById('pl-fsel'), (v) => { st.sel = v; render() })
  wirePills(document.getElementById('pl-fpin'), (v) => { st.pin = v; render() })
  try {
    const r = await pega('playlists', () => api('listar_playlists'))
    if (meu !== viewAtual()) return                 // trocou de aba durante o fetch
    dados = r.playlists || []
    document.getElementById('pl-sub').textContent = `${dados.length} playlist(s)`
    const c = (t) => dados.filter((p) => p.tipo === t).length
    document.getElementById('pl-stats').innerHTML =
      statCard('listv', '#4f8ef7', dados.length, 'Total') + statCard('monitor', '#9b7bff', c('xtream'), 'Xtream') +
      statCard('coins', '#34c759', c('m3u'), 'M3U') + statCard('globe', '#8b8f98', dados.filter((p) => p.free_dns).length, 'Free DNS')
    render()
  } catch (e) {
    if (meu !== viewAtual()) return
    const el = document.getElementById('pl-tbl'); if (el) el.innerHTML = `<div class="vazio">${esc(e.message)}</div>`
  }
}

// Migrar URL em massa: pré-visualiza (dry-run) → confirma → aplica.
function modalMigrarUrl() {
  abrirModal({
    titulo: 'Migrar URL em massa', okLabel: 'Pré-visualizar',
    campos: [
      { id: 'origem', label: 'URL atual (origem) — protocolo + domínio + porta', placeholder: 'http://dominio1.com.br' },
      { id: 'destino', label: 'Nova URL (destino)', placeholder: 'http://dominio2.com.br:8080' },
    ],
    onOk: async (v) => {
      if (!v.origem || !v.destino) return 'Informe origem e destino'
      const r = await api('migrar_url', { origem: v.origem, destino: v.destino, preview: true })
      if (!r.afetadas.length) return 'Nenhuma playlist casa com essa URL de origem'
      const amostra = r.afetadas.slice(0, 8).map((a) => `• ${a.nome}\n   ${a.de}\n → ${a.para}`).join('\n\n')
      const extra = r.afetadas.length > 8 ? `\n\n… e mais ${r.afetadas.length - 8}` : ''
      if (!confirm(`${r.afetadas.length} playlist(s) serão migradas:\n\n${amostra}${extra}\n\nAplicar?`)) return null
      await api('migrar_url', { origem: v.origem, destino: v.destino })
      invalidar('playlists')
      toast(`${r.afetadas.length} playlist(s) migradas`)
      vPlaylists()
      return null
    },
  })
}

// ── Placeholders (nav completo, estilo GTV) ──────────────────────────────────
function placeholder(titulo, sub, ic) {
  view().innerHTML = `<div class="pg"><div class="pg-head"><div><h1>${esc(titulo)}</h1><p>${esc(sub)}</p></div></div>
    <div class="vazio" style="padding:70px 20px"><div style="opacity:.4;margin-bottom:12px">${svg(ic, ' width="30" height="30"')}</div>Em breve.</div></div>`
}
const vComprar = () => placeholder('Comprar Créditos', 'Adquira créditos para ativar dispositivos', 'cart')

// ── Parceiros (SÓ ADMIN) ─────────────────────────────────────────────────────
// Parceiro = servidor/domínio com acordo: todo dispositivo que recebe uma
// playlist apontando pra ele entra ATIVO na hora, sem teste e sem consumir
// crédito. O casamento é pelo HOST da URL da lista.
const COBRANCA = {
  gratuito: { rot: 'Gratuito', cor: 'info' },
  mensal: { rot: 'Mensalidade fixa', cor: 'ok' },
  por_device: { rot: 'Por device', cor: 'ok' },
}
function rotuloValor(p) {
  if (!p.valor || p.cobranca === 'gratuito') return ''
  const v = Number(p.valor).toLocaleString('pt-BR', { minimumFractionDigits: 2 })
  return `R$ ${v}${p.cobranca === 'mensal' ? '/mês' : '/device'}`
}

async function vParceiros() {
  if (me.papel !== 'admin') { placeholder('Parceiros', 'Área restrita ao administrador', 'globe'); return }
  view().innerHTML = `<div class="pg">
    <div class="pg-head">
      <div><h1>Parceiros</h1><p id="pc-sub">Carregando…</p></div>
      <button class="btn" id="pc-novo">${svg('plus')} Adicionar domínio</button>
    </div>
    <div class="tabs" id="pc-tabs">
      <button class="tab on" data-t="lista">Parceiros</button>
      <button class="tab" data-t="faturas">Faturas</button>
      <button class="tab" data-t="config">Configurações</button>
    </div>
    <div id="pc-aba-lista">
      <div class="stats" id="pc-stats"></div>
      <div class="lista" id="pc-lista"><div class="vazio">Carregando…</div></div>
    </div>
    <div id="pc-aba-faturas" class="oculto"></div>
    <div id="pc-aba-config" class="oculto"></div>
  </div>`
  document.getElementById('pc-novo').onclick = () => modalParceiro(carregar)
  // Abas: só a ativa fica visível (o botão "Adicionar domínio" é da lista).
  const abas = ['lista', 'faturas', 'config']
  const trocarAba = (t) => {
    abas.forEach((x) => document.getElementById('pc-aba-' + x).classList.toggle('oculto', x !== t))
    document.querySelectorAll('#pc-tabs .tab').forEach((b) => b.classList.toggle('on', b.dataset.t === t))
    document.getElementById('pc-novo').classList.toggle('oculto', t !== 'lista')
    if (t === 'faturas') abaFaturas(document.getElementById('pc-aba-faturas'))
    if (t === 'config') abaConfigParceiros(document.getElementById('pc-aba-config'))
  }
  document.querySelectorAll('#pc-tabs .tab').forEach((b) => { b.onclick = () => trocarAba(b.dataset.t) })
  const meu = viewAtual()

  async function carregar() {
    const el = document.getElementById('pc-lista'); if (el) el.innerHTML = '<div class="vazio">Carregando…</div>'
    try {
      const { parceiros } = await api('listar_parceiros')
      if (meu !== viewAtual()) return
      const l = document.getElementById('pc-lista'); if (!l) return
      const devices = parceiros.reduce((s, p) => s + (p.devices || 0), 0)
      document.getElementById('pc-sub').textContent =
        'Dispositivos com lista destes servidores são ativados sem consumir crédito'
      document.getElementById('pc-stats').innerHTML =
        statCard('globe', '#4f8ef7', parceiros.length, 'Domínios') +
        statCard('shield', '#34c759', parceiros.filter((p) => p.ativo).length, 'Ativos') +
        statCard('monitor', '#9b7bff', devices, 'Devices atendidos')
      if (!parceiros.length) { l.innerHTML = '<div class="vazio">Nenhum domínio parceiro cadastrado.</div>'; return }
      l.innerHTML = parceiros.map((p) => {
        const cb = COBRANCA[p.cobranca] || COBRANCA.gratuito
        const val = rotuloValor(p)
        return `<div class="pc-row">
          <div class="pc-ic ${p.ativo ? 'on' : ''}">${svg('globe')}</div>
          <div class="pc-meta">
            <div class="pc-top">
              <span class="pc-dom mono">${esc(p.dominio)}</span>
              <span class="badge badge-${p.ativo ? 'ok' : 'warn'}">${p.ativo ? 'Ativo' : 'Suspenso'}</span>
              <span class="badge badge-${cb.cor}">${esc(cb.rot)}</span>
            </div>
            <div class="pc-sub">
              ${p.nome ? `<span>${esc(p.nome)}</span>` : ''}
              <span>${svg('monitor')} ${p.devices} device(s)</span>
              ${val ? `<span>${svg('coins')} ${esc(val)}</span>` : ''}
            </div>
          </div>
          <div class="pc-acoes">
            <button class="btn-sec" data-acao="alternar" data-id="${esc(p.id)}" data-ativo="${p.ativo ? '1' : ''}">${p.ativo ? 'Suspender' : 'Reativar'}</button>
            <button class="pc-del" data-acao="excluir" data-id="${esc(p.id)}" data-dom="${esc(p.dominio)}" title="Excluir">${svg('trash')}</button>
          </div>
        </div>`
      }).join('')
      l.querySelectorAll('[data-acao="alternar"]').forEach((b) => {
        b.onclick = async () => {
          try { await api('parceiro_ativo', { id: b.dataset.id, ativo: !b.dataset.ativo }); invalidar('parceiros'); toast(b.dataset.ativo ? 'Domínio suspenso' : 'Domínio reativado'); carregar() }
          catch (e) { toast(e.message, true) }
        }
      })
      l.querySelectorAll('[data-acao="excluir"]').forEach((b) => {
        b.onclick = async () => {
          if (!confirm(`Excluir o parceiro ${b.dataset.dom}?\n\nOs dispositivos já ativados CONTINUAM ativos; listas novas desse domínio voltam a cair no teste de 3 dias.`)) return
          try { await api('excluir_parceiro', { id: b.dataset.id }); invalidar('parceiros'); toast('Parceiro excluído'); carregar() }
          catch (e) { toast(e.message, true) }
        }
      })
    } catch (e) {
      if (meu !== viewAtual()) return
      const l = document.getElementById('pc-lista'); if (l) l.innerHTML = `<div class="vazio">${esc(e.message)}</div>`
    }
  }
  carregar()
}

// ── Abas Faturas / Configurações (Parceiros) ─────────────────────────────────
const FAT_ST = {
  aguardando: { rot: 'Aguard. pagamento', cor: 'warn' },
  pago: { rot: 'Pago', cor: 'ok' },
  cancelado: { rot: 'Cancelado', cor: 'cinza' },
}
const fmtBRL = (v) => 'R$ ' + Number(v || 0).toLocaleString('pt-BR', { minimumFractionDigits: 2 })

// FATURAS: uma linha por parceiro por período. Sem gateway de pagamento ainda —
// "Marcar pago" é manual, e é assim que fica até a API existir.
async function abaFaturas(el) {
  el.innerHTML = `
    <div class="pg-acoes" style="justify-content:flex-end">
      <button class="btn-sec" id="ft-cobrar">${svg('refresh')} Executar cobrança</button>
    </div>
    <div class="tbl-wrap" id="ft-tbl"><div class="vazio">Carregando…</div></div>`
  const meu = viewAtual()

  document.getElementById('ft-cobrar').onclick = async () => {
    if (!confirm('Fechar o período atual e gerar as faturas dos parceiros pagantes?\n\nPode rodar mais de uma vez: fatura já existente no período não é duplicada.')) return
    try {
      const r = await api('gerar_faturas')
      toast(r.criadas ? `${r.criadas} fatura(s) gerada(s)` : 'Nenhuma fatura nova — o período já estava fechado')
      carregar()
    } catch (e) { toast(e.message, true) }
  }

  async function carregar() {
    const t = document.getElementById('ft-tbl'); if (!t) return
    t.innerHTML = '<div class="vazio">Carregando…</div>'
    try {
      const { faturas } = await api('listar_faturas')
      if (meu !== viewAtual()) return
      const alvo = document.getElementById('ft-tbl'); if (!alvo) return
      if (!faturas.length) { alvo.innerHTML = '<div class="vazio">Nenhuma fatura ainda. Use "Executar cobrança" para fechar o período.</div>'; return }
      alvo.innerHTML = `<table><thead><tr>
          <th>#</th><th>Parceiro</th><th>Tipo</th><th>Período</th><th>Devices</th>
          <th>Valor</th><th>Status</th><th>Vencimento / carência</th><th>Ações</th>
        </tr></thead><tbody>
        ${faturas.map((f, i) => {
          const st = FAT_ST[f.status] || FAT_ST.aguardando
          const acoes = f.status === 'aguardando' ? `
            <button class="ft-ac ft-pago" data-id="${esc(f.id)}" data-o="pago">Marcar pago</button>
            <button class="ft-ac ft-car" data-id="${esc(f.id)}" data-o="carencia">+ Carência</button>
            <button class="ft-ac ft-canc" data-id="${esc(f.id)}" data-o="cancelar">Cancelar</button>` : ''
          return `<tr>
            <td class="tnum">${i + 1}</td>
            <td class="mono">${esc(f.dominio)}</td>
            <td>${f.tipo === 'mensal' ? 'Mensal' : 'Por device'}</td>
            <td class="tnum" style="white-space:nowrap">${fmtData(f.periodo_ini)}<br>${fmtData(f.periodo_fim)}</td>
            <td class="tnum">${f.devices}</td>
            <td class="tnum"><b>${fmtBRL(f.valor)}</b></td>
            <td><span class="badge badge-${st.cor}">${st.rot}</span></td>
            <td class="tnum" style="white-space:nowrap">${fmtData(f.vencimento)}
              ${f.carencia_ate ? `<div class="ft-car-ate">carência até ${fmtData(f.carencia_ate)}${f.extensoes ? ` (${f.extensoes}x)` : ''}</div>` : ''}</td>
            <td><div class="ft-acoes">${acoes}</div></td>
          </tr>`
        }).join('')}</tbody></table>`
      alvo.querySelectorAll('.ft-ac').forEach((b) => {
        b.onclick = async () => {
          const o = b.dataset.o
          if (o === 'cancelar' && !confirm('Cancelar esta fatura?')) return
          try {
            const r = await api('fatura_acao', { id: b.dataset.id, oque: o })
            toast(o === 'pago' ? 'Fatura marcada como paga'
              : o === 'cancelar' ? 'Fatura cancelada'
              : `Carência estendida em ${r.dias} dia(s)`)
            carregar()
          } catch (e) { toast(e.message, true) }
        }
      })
    } catch (e) {
      if (meu !== viewAtual()) return
      const alvo = document.getElementById('ft-tbl'); if (alvo) alvo.innerHTML = `<div class="vazio">${esc(e.message)}</div>`
    }
  }
  carregar()
}

// Configuração do PROGRAMA de parceiros: modelos de cobrança, preços padrão,
// regras de carência e o convite que os revendedores veem.
async function abaConfigParceiros(el) {
  el.innerHTML = '<div class="vazio">Carregando…</div>'
  const meu = viewAtual()
  let cfg
  try { cfg = (await api('parceiros_config')).config } catch (e) { el.innerHTML = `<div class="vazio">${esc(e.message)}</div>`; return }
  if (meu !== viewAtual()) return

  const toggle = (id, on, titulo, desc) => `
    <div class="cfg-linha${on ? ' on' : ''}">
      <div><p class="cfg-t">${esc(titulo)}</p><p class="cfg-d">${esc(desc)}</p></div>
      <button type="button" class="sw${on ? ' on' : ''}" id="tg-${id}" aria-pressed="${on}"><span></span></button>
    </div>`
  const campo = (id, rot, valor, extra, hint) => `
    <div class="cfg-campo">
      <label for="cf-${id}">${esc(rot)}</label>
      <input id="cf-${id}" value="${esc(valor)}" ${extra || ''}>
      ${hint ? `<p class="cfg-hint">${esc(hint)}</p>` : ''}
    </div>`

  el.innerHTML = `<form class="cfg-form" id="pc-form">
    <p class="sec-label">Modelos de cobrança</p>
    ${toggle('mensal', cfg.modelo_mensal, 'Mensalidade fixa (pré-pago)', 'Parceiro paga um valor fixo por mês para ativação ilimitada de devices')}
    ${toggle('device', cfg.modelo_por_device, 'Pós-pago (por device)', 'Parceiro paga por device ativo ao final de cada período de faturamento')}

    <p class="sec-label">Preços padrão</p>
    <div class="cfg-grid2">
      ${campo('preco_mensal', 'Mensalidade fixa (R$)', cfg.preco_mensal, 'inputmode="decimal" placeholder="0,00"')}
      ${campo('preco_device', 'Pós-pago por device (R$)', cfg.preco_device, 'inputmode="decimal" placeholder="0,00"')}
    </div>
    ${campo('dia_cobranca', 'Dia do mês em que o período fecha', cfg.dia_cobranca, 'type="number" min="1" max="28"', 'De 1 a 28 — para existir em todo mês, inclusive fevereiro.')}

    <p class="sec-label">Regras de carência</p>
    <div class="cfg-aviso">
      <b>Como funciona</b>
      <p>Depois do vencimento o parceiro entra em carência. Se não pagar até o fim dela, é suspenso. O admin pode conceder dias extras, com limite.</p>
    </div>
    <div class="cfg-grid3">
      ${campo('carencia_dias', 'Dias de carência padrão', cfg.carencia_dias, 'type="number" min="0" max="30"', 'Automáticos após o vencimento')}
      ${campo('carencia_extra_max', 'Máximo de dias extras', cfg.carencia_extra_max, 'type="number" min="0" max="30"', 'Limite por concessão do admin')}
      ${campo('carencia_extensoes', 'Limite de extensões', cfg.carencia_extensoes, 'type="number" min="1" max="10"', 'Quantas vezes pode estender')}
    </div>

    <p class="sec-label">Programa de parceiros</p>
    ${toggle('programa', cfg.programa_ativo, 'Programa de parceiros ativo', 'Exibe o convite de parceria para os revendedores')}
    <div class="cfg-campo">
      <label for="cf-banner">Texto do convite (o revendedor vê)</label>
      <textarea id="cf-banner" rows="3" placeholder="Torne-se um parceiro…">${esc(cfg.banner_texto || '')}</textarea>
    </div>

    <div class="pg-acoes"><button class="btn" id="cf-salvar" type="submit">${svg('check')} Salvar configurações</button></div>
  </form>`

  el.querySelectorAll('.sw').forEach((b) => {
    b.onclick = () => {
      const on = !b.classList.contains('on')
      b.classList.toggle('on', on); b.setAttribute('aria-pressed', String(on))
      b.closest('.cfg-linha').classList.toggle('on', on)
    }
  })
  // Aceita "2.500,00" e "2500.00": tira o separador de milhar e usa ponto decimal.
  const num = (id) => Number(String(document.getElementById('cf-' + id).value).replace(/\./g, '').replace(',', '.')) || 0
  document.getElementById('pc-form').onsubmit = async (ev) => {
    ev.preventDefault()
    const btn = document.getElementById('cf-salvar')
    btn.disabled = true
    try {
      await api('salvar_parceiros_config', { config: {
        modelo_mensal: document.getElementById('tg-mensal').classList.contains('on'),
        modelo_por_device: document.getElementById('tg-device').classList.contains('on'),
        preco_mensal: num('preco_mensal'), preco_device: num('preco_device'),
        dia_cobranca: num('dia_cobranca'),
        carencia_dias: num('carencia_dias'), carencia_extra_max: num('carencia_extra_max'),
        carencia_extensoes: num('carencia_extensoes'),
        programa_ativo: document.getElementById('tg-programa').classList.contains('on'),
        banner_texto: document.getElementById('cf-banner').value,
      } })
      toast('Configurações salvas')
    } catch (e) { toast(e.message, true) } finally { btn.disabled = false }
  }
}

function modalParceiro(recarregar) {
  abrirModal({
    titulo: 'Adicionar domínio parceiro', okLabel: 'Adicionar',
    aviso: 'Todo dispositivo que receber uma lista deste servidor é ativado <b>na hora</b>, sem teste e <b>sem consumir crédito</b>.',
    campos: [
      { id: 'dominio', label: 'Domínio ou URL do servidor', placeholder: 'meuservidor.com  ou  http://1.2.3.4:25461/get.php?...' },
      { id: 'nome', label: 'Identificação (opcional)', placeholder: 'Nome do parceiro' },
      { id: 'cobranca', label: 'Cobrança', escolhas: [
        { v: 'gratuito', t: 'Gratuito', d: 'Sem cobrança pelo acordo', ic: 'globe' },
        { v: 'mensal', t: 'Mensalidade fixa', d: 'Valor fechado por mês', ic: 'coins' },
        { v: 'por_device', t: 'Por device', d: 'Valor por dispositivo ativado', ic: 'monitor' },
      ] },
      { id: 'valor', label: 'Valor (R$) — só para mensal/por device', type: 'number', placeholder: '0,00' },
    ],
    onOk: async (v) => {
      if (!v.dominio) return 'Informe o domínio do servidor'
      const r = await api('criar_parceiro', v)
      invalidar('parceiros', 'dispositivos')
      toast(r.ativados ? `Parceiro adicionado — ${r.ativados} device(s) ativados` : 'Parceiro adicionado')
      recarregar()
      return null
    },
  })
}

// ── SERVIDORES (admin) ───────────────────────────────────────────────────────
// Atalho de login Xtream: em vez de digitar "http://servidor.com:8080" no
// controle da TV, o cliente digita um CÓDIGO curto e o app resolve pro host.
// É só facilitador de digitação — não guarda usuário/senha de ninguém.
async function vServidores() {
  if (me.papel !== 'admin') { placeholder('Servidores', 'Área restrita ao administrador', 'server'); return }
  view().innerHTML = `<div class="pg">
    <div class="pg-head">
      <div><h1>Servidores</h1><p>Servidores IPTV disponíveis para os devices. O código é usado no app para login rápido.</p></div>
      <button class="btn" id="sv-novo">${svg('plus')} Novo servidor</button>
    </div>
    <div class="busca-wrap">
      ${svg('search')}
      <input id="sv-busca" placeholder="Buscar por nome, host ou código…" autocomplete="off">
      <span class="busca-cont" id="sv-cont"></span>
    </div>
    <div class="lista" id="sv-lista"><div class="vazio">Carregando…</div></div>
  </div>`
  document.getElementById('sv-novo').onclick = () => modalServidor(null, carregar)
  const meu = viewAtual()
  let todos = []

  const filtrar = () => {
    const q = (document.getElementById('sv-busca').value || '').trim().toLowerCase()
    const lista = !q ? todos : todos.filter((s) =>
      [s.codigo, s.host, s.nome].some((x) => String(x || '').toLowerCase().includes(q)))
    document.getElementById('sv-cont').textContent = `${lista.length}/${todos.length}`
    pintar(lista)
  }

  function pintar(lista) {
    const l = document.getElementById('sv-lista'); if (!l) return
    if (!lista.length) {
      l.innerHTML = `<div class="vazio">${todos.length ? 'Nenhum servidor com esse termo.' : 'Nenhum servidor cadastrado. Crie um para o cliente entrar por código.'}</div>`
      return
    }
    l.innerHTML = lista.map((s) => `<div class="sv-card${s.ativo ? '' : ' off'}">
      <div class="sv-body">
        <div class="sv-cod">
          <span class="sv-cod-label">Código</span>
          <b class="sv-cod-val mono">${esc(s.codigo)}</b>
          <button class="sv-copiar" data-copiar="${esc(s.codigo)}">Copiar</button>
        </div>
        <div class="sv-meta">
          <div class="sv-linha1">
            <b class="sv-nome">${esc(s.nome || s.host)}</b>
            <span class="badge badge-${s.ativo ? 'ok' : 'cinza'}">${s.ativo ? 'Ativo' : 'Inativo'}</span>
          </div>
          <p class="sv-host mono">${esc(s.host)}</p>
          <div class="sv-tags">
            <span>${svg('monitor')} ${s.devices} device(s)</span>
            <span>${svg('hash')} ID #${s.id_num ?? '—'}</span>
            <span>Criado em ${fmtData(s.criado_em)}</span>
          </div>
        </div>
        <div class="sv-acoes">
          <button class="btn-sec" data-a="editar" data-id="${esc(s.id)}">${svg('pencil')} Editar</button>
          <button class="btn-sec" data-a="codigo" data-id="${esc(s.id)}">${svg('refresh')} Novo código</button>
          <button class="sv-perigo" data-a="alternar" data-id="${esc(s.id)}" data-ativo="${s.ativo ? '1' : ''}">${s.ativo ? 'Desativar' : 'Ativar'}</button>
          <button class="sv-del" data-a="excluir" data-id="${esc(s.id)}" data-cod="${esc(s.codigo)}" title="Excluir">${svg('trash')}</button>
        </div>
      </div>
      <div class="sv-ajuda">
        <b>Como usar:</b> no app, vá em <span class="mono">Adicionar playlist → Por código</span>,
        digite <b class="mono">${esc(s.codigo)}</b> e confirme.
      </div>
    </div>`).join('')

    l.querySelectorAll('[data-copiar]').forEach((b) => {
      b.onclick = async () => {
        try { await navigator.clipboard.writeText(b.dataset.copiar) } catch (_) { /* sem permissão */ }
        toast('Código copiado')
      }
    })
    l.querySelectorAll('[data-a]').forEach((b) => {
      b.onclick = async () => {
        const s = todos.find((x) => x.id === b.dataset.id)
        const a = b.dataset.a
        if (a === 'editar') return modalServidor(s, carregar)
        try {
          if (a === 'codigo') {
            if (!confirm(`Gerar um código novo para ${s.host}?\n\nO código atual (${s.codigo}) para de funcionar — quem já usa a lista continua normal, só o atalho muda.`)) return
            const r = await api('servidor_codigo', { id: s.id })
            toast('Novo código: ' + r.codigo)
          } else if (a === 'alternar') {
            await api('servidor_ativo', { id: s.id, ativo: !b.dataset.ativo })
            toast(b.dataset.ativo ? 'Servidor desativado' : 'Servidor ativado')
          } else if (a === 'excluir') {
            if (!confirm(`Excluir o servidor de código ${b.dataset.cod}?\n\nAs playlists já criadas continuam funcionando — some só o atalho por código.`)) return
            await api('excluir_servidor', { id: s.id })
            toast('Servidor excluído')
          }
          carregar()
        } catch (e) { toast(e.message, true) }
      }
    })
  }

  async function carregar() {
    const l = document.getElementById('sv-lista'); if (l) l.innerHTML = '<div class="vazio">Carregando…</div>'
    try {
      const { servidores } = await api('listar_servidores')
      if (meu !== viewAtual()) return
      todos = servidores
      filtrar()
    } catch (e) {
      if (meu !== viewAtual()) return
      const el = document.getElementById('sv-lista'); if (el) el.innerHTML = `<div class="vazio">${esc(e.message)}</div>`
    }
  }
  document.getElementById('sv-busca').oninput = () => { if (todos.length) filtrar() }
  carregar()
}

// Mesmo modal para criar e editar (`s` null = criar).
function modalServidor(s, recarregar) {
  abrirModal({
    titulo: s ? 'Editar servidor' : 'Novo servidor',
    okLabel: s ? 'Salvar' : 'Criar servidor',
    aviso: 'O <b>código</b> é o que o cliente digita no app para não precisar escrever o endereço inteiro do servidor. Deixe em branco para gerar um de 4 dígitos.',
    campos: [
      { id: 'host', label: 'Host (URL base do servidor)', placeholder: 'http://servidor.com:8080', value: s ? s.host : '' },
      { id: 'nome', label: 'Nome do servidor (opcional)', placeholder: 'Api', value: s ? (s.nome || '') : '' },
      { id: 'codigo', label: 'Código de acesso', placeholder: 'Ex.: 1234, 726262, MEUCODIGO', value: s ? s.codigo : '' },
    ],
    onOk: async (v) => {
      if (!v.host) return 'Informe o host do servidor'
      const r = await api('salvar_servidor', { id: s ? s.id : '', ...v })
      toast(s ? 'Servidor atualizado' : 'Servidor criado — código ' + r.codigo)
      recarregar()
      return null
    },
  })
}

// ── Indicação (código + link; novos revendedores se cadastram por aqui) ──────
async function vIndicacao() {
  const codigo = me.codigo_indicacao || '—'
  // Link RELATIVO à página atual → funciona em qualquer caminho de deploy
  // (raiz, /painel/, /pasta-secreta/…) sem precisar saber o domínio/prefixo.
  const link = new URL('register.html?ref=' + encodeURIComponent(codigo), location.href).href
  view().innerHTML = `<div class="pg">
    <div class="pg-head"><div><h1>Indicação</h1><p>Seu link de indicação para novos revendedores</p></div></div>
    <div class="ind-cards">
      <div class="ind-card"><div class="ind-ic" style="background:#4f8ef71f;color:#4f8ef7">${svg('hash')}</div><div><div class="ind-label">Seu código</div><div class="ind-codigo mono">${esc(codigo)}</div></div></div>
      <div class="ind-card"><div class="ind-ic" style="background:#34c7591f;color:#34c759">${svg('users')}</div><div><div class="ind-label">Indicados</div><div class="ind-num tnum" id="ind-num">—</div></div></div>
    </div>
    <div class="ind-link-card">
      <div class="ind-label">Link de indicação</div>
      <div class="ind-link-row"><input class="ind-link mono" id="ind-link" readonly value="${esc(link)}"><button class="btn" id="ind-copy">Copiar</button></div>
    </div>
    <p class="ind-hint">Compartilhe seu link para que novos revendedores se cadastrem através de você — eles aparecem na aba <b>Revendedores</b>.</p>
  </div>`
  document.getElementById('ind-copy').onclick = async () => {
    const el = document.getElementById('ind-link')
    try { await navigator.clipboard.writeText(link) } catch (_) { el.select(); document.execCommand('copy') }
    toast('Link copiado')
  }
  try { const { revendedores } = await pega('downline', () => api('listar_revendedores')); const n = document.getElementById('ind-num'); if (n) n.textContent = revendedores.length } catch (_) {}
}

// ── Boot ─────────────────────────────────────────────────────────────────────
async function iniciar() {
  cache.clear()
  try { me = await api('me') } catch (e) { viewLogin('Não foi possível entrar: ' + (e && e.message ? e.message : e)); return }
  renderShell()
  // Badge de não lidas já no primeiro render, sem abrir a caixa.
  checarCaixa()
}
;(async () => {
  const { data: { session } } = await sb.auth.getSession()
  if (session) iniciar(); else viewLogin()
})()