# API do Hero Play

API para outros painéis lerem e administrarem a base do Hero Play:
clientes, aparelhos e listas de **todos os revendedores**.

**Endereço:** `https://cfwmeeksnwampfdkicye.supabase.co/functions/v1/api`

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
| Listar clientes (de todos os revendedores) | Ativar ou renovar dispositivo |
| Ver detalhe de um cliente | Transferir crédito |
| Listar aparelhos, com MAC e Key | Criar ou promover revendedor |
| Listar playlists | Mexer em parceiro ou servidor |
| Criar playlist | Apagar qualquer coisa |
| Trocar a lista de um cliente | |
| Trocar o domínio em massa | |

Ativação foi deixada de fora de propósito: ela **consome crédito**, então uma
chave vazada viraria prejuízo direto. A superfície é uma lista fechada, escrita
à mão — ação que não está documentada aqui não é alcançável por chave de API,
mesmo que exista no painel.

**Escopo:** a chave de admin enxerga a **plataforma inteira** — clientes,
aparelhos e listas de **todos os revendedores**, não só os do admin.

> O painel também mostra a plataforma inteira para o admin, mas em abas
> separadas e **somente leitura** — e **sem a URL das listas**, só o servidor
> (`host`). As abas "Meus ..." continuam sendo só do próprio operador, e são
> elas que têm as ações de escrita.
>
> A URL decifrada sai **só por aqui**. É de propósito: por chave o acesso é
> nominal e fica registrado em `ultimo_uso_em`; numa tela de consulta a
> credencial do servidor de outro revendedor ficaria à mostra de passagem.

---

## Endpoints

### `GET /clientes`

```json
{
  "ok": true,
  "clientes": [
    { "id": "uuid", "nome": "João", "criado_em": "...",
      "revendedor_id": "uuid", "revendedor": "Carlos" }
  ],
  "restam_mais": false,
  "proximo": null
}
```

### `GET /clientes/:id`

Cliente, seus aparelhos e suas listas.

```json
{
  "ok": true,
  "cliente": { "id": "uuid", "nome": "João", "criado_em": "...",
               "revendedor_id": "uuid", "revendedor": "Carlos" },
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

### `GET /dispositivos`

Todos os aparelhos da plataforma, com **MAC** e **Key**, e de quem é cada um.

```json
{
  "ok": true,
  "dispositivos": [
    { "id": "uuid", "mac": "AA:BB:CC:DD:EE:FF", "device_key": "123456",
      "modelo": "android", "status": "ativo", "plano": "ano",
      "expira_em": "...", "ativado_por": "parceiro",
      "cliente_id": "uuid", "cliente": "João", "revendedor": "Carlos" }
  ],
  "restam_mais": false,
  "proximo": null
}
```

### `GET /playlists`

Todas as listas da plataforma, com a **URL decifrada**, e de quem é cada uma.

```json
{
  "ok": true,
  "playlists": [
    { "id": "uuid", "cliente_id": "uuid", "cliente": "João", "revendedor": "Carlos",
      "nome": "Lista 1", "tipo": "xtream",
      "url": "http://servidor.com:8080/get.php?username=...&password=...",
      "host": "servidor.com:8080", "free_dns": true, "criado_em": "..." }
  ],
  "restam_mais": false,
  "proximo": null
}
```

> **Paginação.** As três listagens devolvem até 1000 por vez. Quando vier
> `"restam_mais": true`, repita a chamada com `?apos=<proximo>` até `restam_mais`
> virar `false`. Em `GET /playlists` dá para filtrar por servidor com
> `?host=servidor.com` (sem porta cobre qualquer porta).

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

### `PATCH /playlists/:id` — trocar a lista de um cliente

Mande só o que muda.

```json
{
  "lista_url": "http://servidor-novo.com:8080/get.php?username=u&password=p",
  "nome": "Lista nova",
  "epg_url": "http://servidor-novo.com:8080/xmltv.php?username=u&password=p"
}
```

```json
{
  "ok": true,
  "playlist": { "id": "uuid", "nome": "Lista nova", "tipo": "xtream", "host": "servidor-novo.com:8080", "free_dns": true },
  "parceiro": true,
  "ativados": 2
}
```

Se o domínio novo for de um parceiro, os aparelhos dessa lista são ativados na
hora — mesma regra da criação, e **sem consumir crédito**.

### `POST /playlists/migrar` — trocar o domínio em massa

Troca o servidor de **todas** as listas que estão num domínio. Por padrão é
**prévia**: nada é alterado até você mandar `"aplicar": true`.

```json
{ "de": "servidor-antigo.com:8080", "para": "servidor-novo.com:8080", "aplicar": false }
```

Prévia:

```json
{
  "ok": true, "aplicado": false, "encontradas": 42, "alteradas": 0,
  "amostra": [ { "id": "uuid", "nome": "Lista 1", "cliente_id": "uuid",
                 "de": "http://servidor-antigo.com:8080/get.php?...",
                 "para": "http://servidor-novo.com:8080/get.php?..." } ],
  "restam_mais": false, "proximo": null
}
```

Confira a prévia e repita com `"aplicar": true` para valer.

Três coisas que valem conhecer:

**Casa por host, não por texto.** `servidor-antigo.com` **não** pega
`servidor-antigo.company.com`. Só o host exato — ou o host em qualquer porta, se
você informar o domínio sem porta.

**Preserva o resto da URL.** Caminho, usuário, senha e parâmetros continuam
iguais; muda só o servidor. Se `para` vier sem porta e a lista tinha uma, a
porta é mantida.

**Vai em lotes de 300.** Quando vier `"restam_mais": true`, repita com
`"apos": "<proximo>"` até acabar.

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
BASE="https://cfwmeeksnwampfdkicye.supabase.co/functions/v1/api"

# Clientes
curl -s "$BASE/clientes" -H "Authorization: Bearer $CHAVE"

# Detalhe de um cliente
curl -s "$BASE/clientes/<uuid>" -H "Authorization: Bearer $CHAVE"

# Listas
curl -s "$BASE/playlists" -H "Authorization: Bearer $CHAVE"

# Aparelhos com MAC
curl -s "$BASE/dispositivos" -H "Authorization: Bearer $CHAVE"

# Trocar a lista de um cliente
curl -s -X PATCH "$BASE/playlists/<uuid>" \
  -H "Authorization: Bearer $CHAVE" -H "Content-Type: application/json" \
  -d '{"lista_url":"http://servidor-novo.com:8080/get.php?username=u&password=p"}'

# Troca em massa — PRÉVIA primeiro
curl -s -X POST "$BASE/playlists/migrar" \
  -H "Authorization: Bearer $CHAVE" -H "Content-Type: application/json" \
  -d '{"de":"servidor-antigo.com:8080","para":"servidor-novo.com:8080"}'

# …e só então aplicar
curl -s -X POST "$BASE/playlists/migrar" \
  -H "Authorization: Bearer $CHAVE" -H "Content-Type: application/json" \
  -d '{"de":"servidor-antigo.com:8080","para":"servidor-novo.com:8080","aplicar":true}'

# Subir uma lista para todos os aparelhos do cliente
curl -s -X POST "$BASE/playlists" \
  -H "Authorization: Bearer $CHAVE" \
  -H "Content-Type: application/json" \
  -d '{"cliente_id":"<uuid>","nome":"Lista principal","lista_url":"http://servidor.com:8080/get.php?username=u&password=p&type=m3u_plus"}'
```

---

---

*Documento gerado a partir do código da função em 14/09/2026. Endpoints e
formatos conferidos contra o ambiente publicado nessa data.*
