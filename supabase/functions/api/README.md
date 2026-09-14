# API do Hero Play

API para outros painéis lerem seus clientes e subirem listas.

**Endereço:** `https://<projeto>.supabase.co/functions/v1/api`

---

## Autenticação

Toda requisição leva a chave num cabeçalho. Qualquer um dos dois serve:

```
Authorization: Bearer hp_xxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxx
X-API-Key: hp_xxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxx
```

A chave é gerada no painel do Hero, em **Sistema → API**. Ela aparece **uma
única vez**, na criação — do banco só sai o hash. Perdeu, revoga e gera outra.

Sem chave, ou com chave revogada, a resposta é `401`.

---

## O que a chave faz

| Pode | Não pode |
|---|---|
| Listar clientes | Ativar ou renovar dispositivo |
| Ver detalhe de um cliente | Transferir crédito |
| Listar playlists | Criar ou promover revendedor |
| Criar playlist | Mexer em parceiro ou servidor |
| | Apagar qualquer coisa |

Ativação foi deixada de fora de propósito: ela **consome crédito**, então uma
chave vazada viraria prejuízo direto. A superfície é uma lista fechada, escrita
à mão — ação que não está documentada aqui não é alcançável por chave de API,
mesmo que exista no painel.

**Escopo:** a chave enxerga os clientes da conta dona dela — exatamente o que
essa conta vê no painel. Não alcança clientes de outros revendedores.

---

## Endpoints

### `GET /clientes`

```json
{ "ok": true, "clientes": [ { "id": "uuid", "nome": "João", "criado_em": "..." } ] }
```

### `GET /clientes/:id`

Cliente, seus aparelhos e suas listas.

```json
{
  "ok": true,
  "cliente": { "id": "uuid", "nome": "João", "criado_em": "..." },
  "dispositivos": [
    { "id": "uuid", "mac": "AA:BB:...", "device_key": "123456", "modelo": "android",
      "status": "ativo", "plano": "ano", "expira_em": "...", "ativado_por": "parceiro" }
  ],
  "playlists": [ { "id": "uuid", "nome": "Lista 1", "tipo": "xtream", "host": "servidor.com:8080", "free_dns": true } ]
}
```

O `status` já vem **calculado pela data**: um aparelho marcado como `ativo` no
banco, mas com `expira_em` no passado, aparece aqui como `expirado`. É a mesma
conta que o app faz — não precisa refazer do seu lado.

### `GET /playlists`

Todas as listas dos seus clientes, com a **URL decifrada** (até 1000).

```json
{
  "ok": true,
  "playlists": [
    { "id": "uuid", "cliente_id": "uuid", "nome": "Lista 1", "tipo": "xtream",
      "url": "http://servidor.com:8080/get.php?username=...&password=...",
      "host": "servidor.com:8080", "free_dns": true, "criado_em": "..." }
  ]
}
```

### `POST /playlists`

```json
{
  "cliente_id": "uuid",            // obrigatório
  "lista_url": "http://...",       // obrigatório, http ou https
  "nome": "Lista principal",       // opcional (padrão: "Playlist")
  "epg_url": "http://...",         // opcional
  "dispositivo_ids": ["uuid"]      // opcional; vazio = todos os aparelhos do cliente
}
```

Resposta `201`:

```json
{
  "ok": true,
  "playlist": { "id": "uuid", "nome": "Lista principal", "tipo": "xtream", "host": "servidor.com:8080", "free_dns": true },
  "vinculados": 2,
  "parceiro": true,
  "ativados": 2
}
```

Dois comportamentos que valem conhecer:

**A primeira lista de um aparelho vira a ativa.** Se o aparelho ainda não tem
nenhuma lista selecionada, a que você criar entra como selecionada. Se já tem,
a nova entra como alternativa e a seleção não muda.

**Domínio parceiro ativa o aparelho na hora.** Se o host da lista for de um
domínio com acordo, os aparelhos vinculados entram como `ativo` sem período de
teste e **sem consumir crédito** — `parceiro: true` e `ativados` dizem quando
isso aconteceu. Não é a API gastando crédito: é o acordo do domínio valendo,
igual a quando a lista entra pelo painel.

---

## Erros

Sempre no mesmo formato:

```json
{ "ok": false, "erro": "descrição do problema" }
```

| Código | Quando |
|---|---|
| `400` | Faltou campo, URL inválida, ou os `dispositivo_ids` não são desse cliente |
| `401` | Chave ausente, inválida ou revogada |
| `403` | A conta dona da chave está inativa, ou não é admin |
| `404` | Cliente não encontrado, ou rota que não existe |
| `500` | Falha ao gravar |

---

## Exemplos

```bash
CHAVE="hp_xxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxx"
BASE="https://<projeto>.supabase.co/functions/v1/api"

# Clientes
curl -s "$BASE/clientes" -H "Authorization: Bearer $CHAVE"

# Detalhe de um cliente
curl -s "$BASE/clientes/<uuid>" -H "Authorization: Bearer $CHAVE"

# Listas
curl -s "$BASE/playlists" -H "Authorization: Bearer $CHAVE"

# Subir uma lista para todos os aparelhos do cliente
curl -s -X POST "$BASE/playlists" \
  -H "Authorization: Bearer $CHAVE" \
  -H "Content-Type: application/json" \
  -d '{"cliente_id":"<uuid>","nome":"Lista principal","lista_url":"http://servidor.com:8080/get.php?username=u&password=p&type=m3u_plus"}'
```

---

## Notas para quem mantém

Esta função é **separada da `painel`** de propósito. A `painel` é o contrato
interno do nosso painel e muda quando precisamos; se um painel de terceiro
pendurasse nela, toda mudança nossa viraria quebra de contrato pra fora.

O hash da chave é calculado em **dois arquivos** (`api/index.ts` e
`painel/index.ts`) e as duas contas precisam ser idênticas — se divergirem,
nenhuma chave recém-criada abre a API, e o sintoma é "chave inválida" para uma
chave que acabou de sair do painel. Há teste travando isso em
`tools/teste-parceiros/api.test.mjs`.

O papel `admin` é conferido **a cada requisição**, não só ao criar a chave: se a
conta for rebaixada depois, a chave para de valer na hora, sem ninguém precisar
lembrar de revogar.

Para publicar:

```bash
supabase functions deploy api
```
