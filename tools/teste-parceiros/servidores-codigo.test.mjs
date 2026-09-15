// Testa o CÓDIGO de servidor no campo "Servidor" do app de TV e do site.
//
// Antes, o painel criava o código (tela Servidores) e nenhum app o consultava:
// o revendedor gerava um código que não fazia nada. Aqui se trava o caminho
// inteiro — a nuvem traduz, os DOIS formulários do app de TV e o do site usam a
// tradução, e endereço digitado continua funcionando como sempre.
//
// Rodar:  node tools/teste-parceiros/servidores-codigo.test.mjs
import { readFileSync } from 'node:fs'
import { test } from 'node:test'
import assert from 'node:assert/strict'

const ler = (p) => readFileSync(new URL(p, import.meta.url), 'utf8')
const ativacao = ler('../../supabase/functions/ativacao/index.ts')
const app = ler('../../tv-app/app.js')
const device = ler('../../tv-app/device.js')
const i18n = ler('../../tv-app/i18n.js')
const upload = ler('../../website/upload.html')
const site = ler('../../website/assets/site.js')
const painel = ler('../../painel/painel.js')

const trecho = (src, de, ate) => {
  const i = src.indexOf(de)
  const f = src.indexOf(ate, i + 1)
  // Delimitado dos DOIS lados: marcador que cai antes do início devolveria o
  // arquivo inteiro, e o teste passaria sem testar nada.
  assert.ok(i >= 0 && f > i, `não achei o trecho entre "${de}" e "${ate}"`)
  return src.slice(i, f)
}
const semComentarios = (s) => s.replace(/\/\*[\s\S]*?\*\//g, '').replace(/\/\/.*/g, '')

test('a nuvem só traduz o código para um aparelho que existe', () => {
  const s = trecho(ativacao, "acao === 'servidor'", "acao === 'selecionar'")
  assert.match(s, /if \(!mac \|\| !key\) return erro/)
  // Sem conferir a Key, bastaria varrer 1000-9999 para listar os servidores.
  assert.match(s, /d\.device_key !== key/)
  assert.match(s, /, 403\)/)
  assert.match(s, /\.eq\('ativo', true\)/)
  assert.match(s, /, 404\)/)
})

test('o código casa por igualdade, nunca por LIKE', () => {
  // O código aceita "_", que no LIKE é curinga: "A_1" casaria "AB1", o servidor
  // de outra pessoa.
  const s = semComentarios(trecho(ativacao, "acao === 'servidor'", "acao === 'selecionar'"))
  assert.ok(!/\.ilike\(|\.like\(/.test(s), 'a tradução do código voltou a usar LIKE')
  assert.match(s, /\.eq\('codigo', codigo\)/)
  // E é normalizado do mesmo jeito que o painel grava (maiúsculo).
  assert.match(s, /toUpperCase\(\)/)
})

test('o app de TV expõe a consulta', () => {
  assert.match(device, /async function resolverServidor\(codigo\)/)
  assert.match(device, /_post\(\{ acao: 'servidor', codigo \}\)/)
  assert.match(device, /return \{[^}]*resolverServidor[^}]*\}/)
})

// Executa a regra de verdade, com a nuvem simulada.
const fonteRegra = trecho(app, 'const _pareceCodigoServidor', '// Barra o "Conectar" repetido')
function montarRegra(resposta) {
  const chamadas = []
  const Dispositivo = { resolverServidor: async (c) => { chamadas.push(c); return resposta } }
  const t = (s) => s
  const hostDoCampo = new Function('Dispositivo', 't', fonteRegra + '\nreturn hostDoCampo')(Dispositivo, t)
  return { hostDoCampo, chamadas }
}

test('[executa] endereço digitado não consulta nada e segue igual', async () => {
  for (const v of ['http://srv.com:8080', 'srv.com:8080', 'https://srv.com']) {
    const { hostDoCampo, chamadas } = montarRegra({ host: 'NUNCA', motivo: null })
    assert.deepEqual(await hostDoCampo(v), { host: v })
    assert.equal(chamadas.length, 0, `"${v}" não deveria consultar a nuvem`)
  }
})

test('[executa] código conhecido vira o host cadastrado', async () => {
  const { hostDoCampo, chamadas } = montarRegra({ host: 'http://real.com:80', motivo: null })
  assert.deepEqual(await hostDoCampo('1234'), { host: 'http://real.com:80' })
  assert.deepEqual(chamadas, ['1234'])
})

test('[executa] domínio sem porta continua funcionando como host', async () => {
  // "servidor.com" tem cara de código (sem ":"), a nuvem não conhece — e ele
  // tem que continuar sendo aceito como endereço, como antes da mudança.
  const { hostDoCampo } = montarRegra({ host: null, motivo: 'nao_encontrado' })
  assert.deepEqual(await hostDoCampo('servidor.com'), { host: 'servidor.com' })
})

test('[executa] código errado diz que está errado; sem rede diz que é a rede', async () => {
  const errado = montarRegra({ host: null, motivo: 'nao_encontrado' })
  assert.deepEqual(await errado.hostDoCampo('9999'), { erro: 'Código de servidor não encontrado.' })
  // Sem rede, "código não encontrado" mandaria conferir um código que está certo.
  const offline = montarRegra({ host: null, motivo: 'offline' })
  assert.deepEqual(await offline.hostDoCampo('9999'), { erro: 'Sem conexão para conferir o código do servidor.' })
})

test('os DOIS formulários do app de TV passam pela regra', () => {
  // Onboarding e tela Playlists têm cada um o seu campo Servidor. Consertar só
  // um deixaria o código funcionando pela metade.
  const ob = trecho(app, 'async function onboardingAdicionar', 'async function recarregarOnboarding')
  const pl = trecho(app, 'async function addPlaylistSubmit', '// ── Boot')
  for (const [nome, f] of [['onboardingAdicionar', ob], ['addPlaylistSubmit', pl]]) {
    assert.match(f, /await hostDoCampo\(campo\)/, `${nome} não resolve o código`)
    assert.match(f, /montarXtream\(r\.host,/, `${nome} monta a URL com o campo cru`)
    assert.match(f, /if \(_conferindoServidor\) return;/, `${nome} aceita "Conectar" repetido`)
  }
})

test('o placeholder novo existe e está traduzido', () => {
  assert.ok(!app.includes("t('Servidor (http://host:porta)')"), 'sobrou o placeholder antigo')
  assert.equal((app.match(/t\('Servidor ou código'\)/g) || []).length, 2)
  for (const chave of ['Servidor ou código', 'Conferindo o servidor…', 'Código de servidor não encontrado.', 'Sem conexão para conferir o código do servidor.']) {
    // EN e ES — o PT é a própria chave.
    assert.equal(i18n.split(`'${chave}':`).length - 1, 2, `"${chave}" sem tradução EN/ES`)
  }
})

test('o site resolve o código antes de adicionar', () => {
  const f = trecho(upload, 'async function adicionar(e)', 'function mostrarResultado')
  const i = f.indexOf('resolverServidor(d, h)')
  const j = f.indexOf("acao: 'adicionar'")
  assert.ok(i > 0 && j > i, 'o site adiciona a lista antes de resolver o código')
  // O EPG digitado à mão continua mandando.
  assert.match(f, /if \(!epgInformado\(\)\) lista\.epg_url = x\.epg_url/)
  assert.match(upload, /acao: 'servidor', mac: dev\.mac, key: dev\.key, codigo/)
  assert.match(upload, /id="x-host" placeholder="[^"]*" data-i18n-ph="up\.serverph"/)
})

test('a prévia do site não promete uma URL feita de código', () => {
  const f = trecho(upload, 'function atualizarDerivado', 'function trocarAba')
  assert.match(f, /codigo \? t\('up\.codres'\) : d\.lista_url/)
})

test('os textos novos do site existem em PT e EN', () => {
  for (const k of ['up.errcod', 'up.codres', 'up.serverph']) {
    assert.equal(site.split(`'${k}':`).length - 1, 2, `${k} não está nos dois idiomas`)
  }
})

test('a ajuda da tela Servidores descreve o fluxo que existe', () => {
  // Mandava ir em "Adicionar playlist → Por código", uma tela que nunca existiu.
  assert.ok(!painel.includes('Por código'), 'a ajuda ainda cita a tela inexistente')
  assert.match(painel, /no campo <b>Servidor<\/b>/)
})
