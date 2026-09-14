// Testa a API PÚBLICA do Hero (Edge Function `api`) e as chaves que a abrem.
//
// O que dá para testar sem Deno nem Supabase é justamente onde mora o risco:
// o hash da chave (calculado em DOIS arquivos, que precisam concordar) e o
// tamanho da superfície exposta.
//
// Rodar:  node tools/teste-parceiros/api.test.mjs
import { readFileSync } from 'node:fs'
import { test } from 'node:test'
import assert from 'node:assert/strict'

const ler = (p) => readFileSync(new URL(p, import.meta.url), 'utf8')
const api = ler('../../supabase/functions/api/index.ts')
const painel = ler('../../supabase/functions/painel/index.ts')

/** Extrai uma função do fonte e tira as anotações de tipo. */
function extrair(src, marcador, fim) {
  const i = src.indexOf(marcador)
  assert.ok(i >= 0, `não achei "${marcador}"`)
  const j = src.indexOf(fim, i)
  assert.ok(j > i, `não achei o fim de "${marcador}"`)
  return src.slice(i, j + fim.length)
    .replace(/export /g, '')
    .replace(/:\s*Promise<string>/g, '')
    .replace(/:\s*string/g, '')
}

test('[executa] o hash da chave é IGUAL nos dois arquivos', async () => {
  // Se divergirem, nenhuma chave criada pelo painel abre a API — e o sintoma é
  // "chave inválida" para uma chave que acabou de ser gerada.
  const daApi = extrair(api, 'export async function hashDaChave(', '\n}')
  const doPainel = extrair(painel, 'async function hashDaChave(', '\n}')
  assert.equal(
    daApi.replace(/\s+/g, ' ').trim(),
    doPainel.replace(/\s+/g, ' ').trim(),
    'as duas implementações de hashDaChave precisam ser idênticas',
  )

  // E roda de verdade, contra um vetor conhecido de SHA-256.
  const fn = new Function(`${daApi}; return hashDaChave`)()
  assert.equal(
    await fn('abc'),
    'ba7816bf8f01cfea414140de5dae2223b00361a396177a9cb410ff61f20015ad',
  )
  assert.equal((await fn('hp_teste')).length, 64)
})

test('[executa] a chave gerada tem o formato esperado e não se repete', () => {
  const gerar = new Function(`${extrair(painel, 'function gerarChaveApi(', '\n}')}; return gerarChaveApi`)()
  const uma = gerar()
  assert.match(uma, /^hp_[0-9a-f]{40}$/)
  // 20 bytes aleatórios: colisão em 100 mil é praticamente impossível, e um
  // gerador quebrado (constante) cai aqui na hora.
  const muitas = new Set(Array.from({ length: 100_000 }, gerar))
  assert.equal(muitas.size, 100_000)
})

test('a chave nunca é gravada em texto', () => {
  const criar = painel.slice(painel.indexOf("acao === 'criar_api_chave'"), painel.indexOf("acao === 'revogar_api_chave'"))
  assert.match(criar, /hash: await hashDaChave\(chave\)/)
  // O insert não pode ter um campo com a chave crua.
  assert.doesNotMatch(criar, /\bchave,\s*$/m)
  assert.doesNotMatch(criar, /valor: chave|chave_texto|segredo: chave/)
  // O prefixo visível é só o começo — nunca a chave inteira.
  assert.match(criar, /prefixo: chave\.slice\(0, 11\)/)
  // Listar não devolve o hash.
  const listar = painel.slice(painel.indexOf("acao === 'listar_api_chaves'"), painel.indexOf("acao === 'criar_api_chave'"))
  assert.doesNotMatch(listar, /select\([^)]*hash/)
})

test('a API só aceita chave — sem porta dos fundos por JWT', () => {
  const autenticar = api.slice(api.indexOf('async function autenticar('), api.indexOf('/** Ids dos clientes'))
  assert.match(autenticar, /x-api-key/)
  assert.match(autenticar, /hash', await hashDaChave\(chave\)/)
  // Nada de sessão de usuário nesta função.
  assert.doesNotMatch(api, /auth\.getUser\(\)/)
  assert.doesNotMatch(api, /grant_type=password/)
  // Chave revogada não passa.
  assert.match(autenticar, /!registro\.ativo/)
  // O papel é conferido A CADA requisição, não só ao criar a chave: conta
  // rebaixada perde acesso na hora, sem depender de alguém lembrar de revogar.
  assert.match(autenticar, /rev\.papel !== 'admin'/)
})

test('a superfície é FECHADA: nada que gaste crédito ou mexa em conta', () => {
  // Uma chave vazada não pode ativar dispositivo (consome crédito), nem criar
  // revendedor, nem transferir crédito, nem apagar nada.
  for (const proibido of [
    'rpc_ativar_dispositivo', 'vincular_dispositivo', 'renovar_dispositivo',
    'transferir_creditos', 'criar_revendedor', 'promover',
    'criar_parceiro', 'excluir_parceiro', 'parceiro_ativo',
    'salvar_servidor', 'excluir_servidor', 'migrar_url',
  ]) {
    assert.ok(!api.includes(proibido), `a API pública não pode alcançar \`${proibido}\``)
  }
  // E nenhum delete, em hipótese alguma.
  assert.doesNotMatch(api, /\.delete\(\)/)
})

test('as rotas são as quatro combinadas, e só elas', () => {
  const rotas = [...api.matchAll(/req\.method === '(GET|POST)' && rota\[0\] === '([a-z]+)'/g)]
    .map((m) => `${m[1]} /${m[2]}`)
  assert.deepEqual(rotas, ['GET /clientes', 'GET /clientes', 'GET /playlists', 'POST /playlists'])
})

test('escopo: só enxerga e escreve nos clientes do próprio operador', () => {
  // Todo caminho passa por `revendedor_id = rev.id`. Sem isso a chave do admin
  // veria cliente de revendedor que não é dele.
  const listar = api.slice(api.indexOf("rota[0] === 'clientes' && !rota[1]"), api.indexOf("rota[0] === 'clientes' && rota[1]"))
  assert.match(listar, /eq\('revendedor_id', rev\.id\)/)
  const detalhe = api.slice(api.indexOf("rota[0] === 'clientes' && rota[1]"), api.indexOf("rota[0] === 'playlists' && !rota[1]"))
  assert.match(detalhe, /eq\('revendedor_id', rev\.id\)/)
  assert.match(api, /async function clientesDoOperador/)
  // No POST o cliente é conferido antes de gravar qualquer coisa.
  const post = api.slice(api.indexOf("req.method === 'POST' && rota[0] === 'playlists'"))
  assert.match(post, /eq\('id', cliente_id\)\.eq\('revendedor_id', rev\.id\)/)
  // E os dispositivos informados também são conferidos contra o cliente.
  assert.match(post, /eq\('cliente_id', cliente_id\)\.in\('id', alvos\)/)
})

test('a URL da playlist entra CIFRADA, como no painel', () => {
  const post = api.slice(api.indexOf("req.method === 'POST' && rota[0] === 'playlists'"))
  assert.match(post, /url_cifrada: await cifrar\(lista_url\)/)
  assert.doesNotMatch(post, /url: lista_url/)
  // E o host em texto claro acompanha — é por ele que se casa parceiro e se
  // conta device por domínio.
  assert.match(post, /host, free_dns: !!parceiro/)
})
