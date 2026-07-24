import { createClient } from 'https://esm.sh/@supabase/supabase-js@2'

// ── Config (projeto Supabase ATUAL — temporário; trocar ao migrar) ───────────
const SUPABASE_URL = 'https://cfwmeeksnwampfdkicye.supabase.co'
const ANON = 'eyJhbGciOiJIUzI1NiIsInR5cCI6IkpXVCJ9.eyJpc3MiOiJzdXBhYmFzZSIsInJlZiI6ImNmd21lZWtzbndhbXBmZGtpY3llIiwicm9sZSI6ImFub24iLCJpYXQiOjE3ODQ5MDIwMjksImV4cCI6MjEwMDQ3ODAyOX0.oFd0yNhE4I0uqrGzkmetVQllZs6loUrpsoXzvY9C2Tg'
const FN = SUPABASE_URL + '/functions/v1/painel'
const sb = createClient(SUPABASE_URL, ANON)
const RANK = { reseller: 1, master: 2, admin: 3 }
const PAPEL_PT = { admin: 'Admin', master: 'Master', reseller: 'Revendedor' }

// Plataforma do device (código gravado pelo tv-app) → nome amigável + ícone.
// 'web' = provavelmente teste no navegador. Futuro: androidtv/tvbox entram aqui.
const MODELO_INFO = {
  webos:    { nome: 'LG (webOS)',        icone: '📺' },
  tizen:    { nome: 'Samsung (Tizen)',   icone: '📺' },
  roku:     { nome: 'Roku',              icone: '🟣' },
  androidtv:{ nome: 'Android TV / Box',  icone: '🤖' },
  web:      { nome: 'Navegador (teste)', icone: '🌐' },
}
const modeloNome = (m) => (MODELO_INFO[m] && MODELO_INFO[m].nome) || (m || '—')
const modeloIcone = (m) => (MODELO_INFO[m] && MODELO_INFO[m].icone) || '❓'
const ATIVADO_POR_PT = { reseller: 'Revendedor', qr: 'QR (auto)', codigo: 'Código', admin: 'Admin' }

const app = document.getElementById('app')
let me = null // { id, nome, usuario, papel, saldo_creditos }

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
  lifebuoy: '<circle cx="12" cy="12" r="10"/><circle cx="12" cy="12" r="4"/><line x1="4.93" y1="4.93" x2="9.17" y2="9.17"/><line x1="14.83" y1="14.83" x2="19.07" y2="19.07"/><line x1="14.83" y1="9.17" x2="19.07" y2="4.93"/><line x1="4.93" y1="19.07" x2="9.17" y2="14.83"/>',
  hash: '<line x1="4" x2="20" y1="9" y2="9"/><line x1="4" x2="20" y1="15" y2="15"/><line x1="10" x2="8" y1="3" y2="21"/><line x1="16" x2="14" y1="3" y2="21"/>',
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

// ── Navegação (Conteúdo é por papel: admin=Masters+Revendedores+Clientes;
//    master=Revendedores; reseller=Clientes) ──────────────────────────────────
const NAV = [
  { grupo: '', itens: [
    { id: 'dashboard', rotulo: 'Dashboard', ic: 'dashboard' },
    { id: 'suporte', rotulo: 'Suporte', ic: 'lifebuoy' },
  ] },
  { grupo: 'Conteúdo', itens: [
    { id: 'clientes', rotulo: 'Clientes', ic: 'users' },
    { id: 'dispositivos', rotulo: 'Dispositivos', ic: 'monitor' },
    { id: 'playlists', rotulo: 'Playlists', ic: 'listv' },
  ] },
  { grupo: 'Negócios', itens: [
    { id: 'creditos', rotulo: 'Créditos', ic: 'coins' },
    { id: 'revendedores', rotulo: 'Revendedores', ic: 'userplus' },
    { id: 'comprar', rotulo: 'Comprar Créditos', ic: 'cart' },
    { id: 'indicacao', rotulo: 'Indicação', ic: 'link' },
    { id: 'parceiros', rotulo: 'Parceiros', ic: 'globe' },
  ] },
]

function renderShell() {
  const nav = NAV.map((g) => {
    const itens = g.itens.filter((i) => !i.papeis || i.papeis.includes(me.papel))
    if (!itens.length) return ''
    return `${g.grupo ? `<div class="nav-grp-label">${esc(g.grupo)}</div>` : ''}
      ${itens.map((i) => `<button class="nav-item" data-view="${i.id}">${svg(i.ic)}<span>${esc(i.rotulo)}</span></button>`).join('')}`
  }).join('')
  const inicial = (me.nome || me.usuario || '?').trim().charAt(0).toUpperCase()
  app.innerHTML = `<div class="shell">
    <aside class="side">
      <div class="side-top"><img class="side-logo" src="heroplay-icon.svg" alt="Hero Play"></div>
      <nav class="side-nav">${nav}</nav>
      <div class="side-user">
        <div class="user-card">
          <div class="user-av">${esc(inicial)}</div>
          <div class="user-meta"><div class="user-nome">${esc(me.nome || me.usuario)}</div><div class="user-papel">${esc(PAPEL_PT[me.papel] || me.papel)}</div></div>
          <div class="user-cr"><b id="u-saldo">${me.saldo_creditos ?? 0}</b><span>cr</span></div>
        </div>
        <button class="side-sair" id="sair">${svg('logout')}<span>Sair</span></button>
      </div>
    </aside>
    <main class="main"><div id="view"></div></main>
  </div>`
  app.querySelectorAll('.nav-item').forEach((b) => { b.onclick = () => irPara(b.dataset.view) })
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
  const fn = { dashboard: vDashboard, suporte: vSuporte, clientes: vClientes, cliente: vCliente, dispositivos: vDispositivos, playlists: vPlaylists, revendedores: vRevendedores, creditos: vCreditos, comprar: vComprar, indicacao: vIndicacao, parceiros: vParceiros }[v]
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
function atualizarSaldo(saldo) {
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
      c.options
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
  const ok = async () => {
    const btn = ov.querySelector('#m-ok'); if (btn.disabled) return
    const vals = {}; campos.forEach((c) => { vals[c.id] = ov.querySelector('#f-' + c.id).value.trim() })
    const rot = btn.innerHTML
    btn.disabled = true; btn.classList.add('is-loading'); btn.innerHTML = '<span class="spin"></span> Processando…'
    const restaurar = () => { btn.disabled = false; btn.classList.remove('is-loading'); btn.innerHTML = rot }
    try { const e = await onOk(vals); if (e) { err(e); restaurar() } else fechar() } catch (ex) { err(ex.message); restaurar() }
  }
  ov.querySelector('#m-ok').onclick = ok
  const primeiro = ov.querySelector('input, select'); if (primeiro) primeiro.focus()
}
function formatarMac(v) { const h = String(v).toUpperCase().replace(/[^0-9A-F]/g, '').slice(0, 12); return h.replace(/(.{2})(?=.)/g, '$1:') }

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
      <div><span>Expira</span><b>${d.expira_em ? fmtData(d.expira_em) : '—'}</b></div>
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
    let html = card('coins', '#E53935', me.saldo_creditos ?? 0, 'Créditos')
    const { clientes } = await pega('clientes', () => api('listar_clientes'))
    html += card('users', '#4f8ef7', clientes.length, 'Clientes')
    const { revendedores } = await pega('downline', () => api('listar_revendedores'))
    html += card('userplus', '#9b7bff', revendedores.length, 'Revendedores')
    if (me.papel === 'admin') html += card('shield', '#7c5cff', revendedores.filter((r) => r.papel === 'master').length, 'Masters')
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
    titulo: 'Vincular dispositivo', okLabel: 'Ativar (1 crédito)',
    aviso: `⚠️ Ativar este dispositivo <b>consome 1 crédito</b> e é <b>irreversível</b>. Seu saldo: <b>${me.saldo_creditos ?? 0}</b> crédito(s).`,
    campos: [{ id: 'mac', label: 'MAC', placeholder: 'AA:BB:CC:DD:EE:FF', format: 'mac' }, { id: 'key', label: 'Key', placeholder: '000000' }],
    onOk: async (v) => { if (v.mac.length !== 17) return 'MAC incompleto'; if (!v.key) return 'Informe a Key'; const r = await api('vincular_dispositivo', { cliente_id, mac: v.mac, key: v.key }); atualizarSaldo(r.saldo); toast(r.cobrado ? 'Dispositivo ativado (−1 crédito)' : 'Dispositivo vinculado'); recarregar(); return null },
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
  view().innerHTML = `<div class="pg"><div class="pg-head"><div><h1>Revendedores</h1><p id="dl-sub">Sua rede direta</p></div>
    <button class="btn-sec" id="ir-indicacao">${svg('link')} Meu link de indicação</button></div>
    <div class="tbl-wrap" id="dl-tbl"><div class="vazio">Carregando…</div></div></div>`
  document.getElementById('ir-indicacao').onclick = () => irPara('indicacao')
  const meu = viewAtual()
  try {
    const { revendedores } = await pega('downline', () => api('listar_revendedores'))
    if (meu !== viewAtual()) return
    document.getElementById('dl-sub').textContent = `${revendedores.length} revendedor(es) direto(s)`
    const el = document.getElementById('dl-tbl')
    if (!revendedores.length) { el.innerHTML = '<div class="vazio">Ninguém se cadastrou pelo seu link ainda. Compartilhe seu link em <b>Indicação</b>.</div>'; return }
    el.innerHTML = `<table><thead><tr><th>Nome</th><th>Tier</th><th>Créditos</th><th>Status</th><th></th></tr></thead><tbody>
      ${revendedores.map((r) => `<tr>
        <td><b>${esc(r.nome || '—')}</b><div class="row-sub">@${esc(r.usuario || "—")}</div></td>
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
      campos: [{ id: 'qtd', label: `Quantidade (seu saldo: ${me.saldo_creditos ?? 0}) → ${b.dataset.nome}`, type: 'number', placeholder: '0' }],
      onOk: async (v) => { const q = parseInt(v.qtd, 10); if (!q || q <= 0) return 'Quantidade inválida'; const r = await api('transferir_creditos', { revendedor_id: b.dataset.id, quantidade: q }); me.saldo_creditos = r.saldo; document.getElementById('u-saldo').textContent = r.saldo; invalidar('downline', 'creditos'); toast('Créditos transferidos'); vRevendedores(); return null },
    }) })
    el.querySelectorAll('[data-acao="tier"]').forEach((b) => { b.onclick = async () => { try { await api('promover', { revendedor_id: b.dataset.id, tier: b.dataset.tier }); invalidar('downline'); toast(b.dataset.tier === 'master' ? 'Promovido a Master' : 'Rebaixado a comum'); vRevendedores() } catch (e) { toast(e.message, true) } } })
  } catch (e) { toast(e.message, true) }
}

// ── Créditos (extrato) ───────────────────────────────────────────────────────
async function vCreditos() {
  view().innerHTML = `<div class="pg"><div class="pg-head"><div><h1>Créditos</h1><p>Seu saldo e histórico de movimentos</p></div></div>
    <div class="stats"><div class="stat"><div class="stat-ic" style="background:#E539351f;color:#E53935">${svg('coins')}</div><div><b id="cr-saldo">${me.saldo_creditos ?? 0}</b><span>Saldo atual</span></div></div></div>
    <div class="tbl-wrap" id="cr-tbl"><div class="vazio">Carregando…</div></div></div>`
  const meu = viewAtual()
  try {
    const { saldo, transacoes } = await pega('creditos', () => api('listar_creditos'))
    if (meu !== viewAtual()) return
    me.saldo_creditos = saldo; document.getElementById('cr-saldo').textContent = saldo
    const su = document.getElementById('u-saldo'); if (su) su.textContent = saldo
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

// ── Suporte (tickets) — só a tela; o envio ainda não vai a lugar nenhum ──────
function vSuporte() {
  view().innerHTML = `<div class="pg">
    <div class="pg-head"><div><h1>Suporte</h1><p>Seus tickets de suporte</p></div></div>
    <div class="sup-bar">
      <div class="sup-filtros"><span class="sup-fl">Status:</span>
        <button class="pill on">Todos</button><button class="pill">Abertos</button><button class="pill">Respondidos</button><button class="pill">Fechados</button></div>
      <div class="sup-dir"><input class="sup-busca" placeholder="Buscar…"><button class="btn" id="novo-ticket">${svg('plus')} Novo ticket</button></div>
    </div>
    <div class="sup-vazio">
      <div class="sup-ic">${svg('ticket', ' width="30" height="30"')}</div>
      <div class="sup-t">Nenhum ticket</div>
      <div class="sup-s">Você ainda não abriu nenhum ticket.</div>
    </div>
  </div>`
  view().querySelectorAll('.pill').forEach((p) => { p.onclick = () => { view().querySelectorAll('.pill').forEach((x) => x.classList.remove('on')); p.classList.add('on') } })
  document.getElementById('novo-ticket').onclick = () => abrirModal({
    titulo: 'Novo ticket', okLabel: 'Abrir ticket',
    campos: [{ id: 'assunto', label: 'Assunto', placeholder: 'Resumo do problema' }, { id: 'msg', label: 'Mensagem', type: 'textarea', placeholder: 'Descreva sua dúvida ou problema…' }],
    onOk: async (v) => { if (!v.assunto) return 'Informe o assunto'; toast('Ticket registrado — suporte em breve'); return null },
  })
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
    el.innerHTML = `<table><thead><tr><th>MAC</th><th>Key</th><th>Modelo</th><th>Cliente</th><th>Status</th><th>Expira</th><th>Trial</th><th>Criado</th></tr></thead><tbody>
      ${f.map((d) => `<tr>
        <td class="mono">${esc(d.mac)}</td><td class="mono">${esc(d.device_key)}</td>
        <td><span class="mdl-ico">${modeloIcone(d.modelo)}</span> ${esc(modeloNome(d.modelo))}</td><td>${esc(d.cliente || '—')}</td>
        <td><span class="badge badge-${esc(d.status)}">${esc(d.status)}</span></td>
        <td class="tnum">${d.expira_em ? fmtData(d.expira_em) : '—'}</td>
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
    titulo: 'Vincular dispositivo', okLabel: 'Ativar (1 crédito)',
    aviso: `⚠️ Ativar este dispositivo <b>consome 1 crédito</b> e é <b>irreversível</b>. Seu saldo: <b>${me.saldo_creditos ?? 0}</b> crédito(s).`,
    campos: [
      { id: 'cliente_id', label: 'Cliente', options: clientes.map((c) => ({ v: c.id, t: c.nome })) },
      { id: 'mac', label: 'MAC', placeholder: 'AA:BB:CC:DD:EE:FF', format: 'mac' },
      { id: 'key', label: 'Key', placeholder: '000000' },
    ],
    onOk: async (v) => { if (v.mac.length !== 17) return 'MAC incompleto'; if (!v.key) return 'Informe a Key'; const r = await api('vincular_dispositivo', { cliente_id: v.cliente_id, mac: v.mac, key: v.key }); atualizarSaldo(r.saldo); invalidar('dispositivos', 'cliente:' + v.cliente_id); toast(r.cobrado ? 'Dispositivo ativado (−1 crédito)' : 'Dispositivo vinculado'); vDispositivos(); return null },
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
const vParceiros = () => placeholder('Parceiros', 'Domínios parceiros (Free DNS) — ativação sem consumir crédito', 'globe')

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
}
;(async () => {
  const { data: { session } } = await sb.auth.getSession()
  if (session) iniciar(); else viewLogin()
})()