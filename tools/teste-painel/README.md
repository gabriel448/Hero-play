# Teste do painel no navegador (Playwright)

Abre o `painel/` num Chromium de verdade, entra como **admin** e como
**revendedor**, e confere o que cada um vê. Nada toca o Supabase real: o login e
a Edge Function `painel` são **interceptados** e respondidos por um backend
falso (`fake_api.py`) com dados fictícios.

```bash
pip install playwright && python -m playwright install chromium
python tools/teste-painel/testa_painel.py            # headless
python tools/teste-painel/testa_painel.py --headed   # vendo o navegador
```

Sai `N passaram · N falharam` e grava telas em `tools/teste-painel/shots/`.
Falha também se aparecer erro de JS no console.

## O que ele cobre

- **Papéis:** seções do menu por papel; revendedor não vê Servidores/Parceiros.
- **Crédito infinito do admin:** sem contador na sidebar/topo, sem card no
  dashboard, ∞ na tela de Créditos, sem "(1 crédito)" nos botões — e ativar
  **não** debita.
- **Planos:** modal oferece 1 ano/Vitalícia (padrão 1 ano), grava data ou `null`,
  renovar cobra e **soma** ao prazo que resta.
- **Vencimento:** device com `expira_em` no passado aparece como *expirado*
  mesmo com `status='ativo'` no banco.
- **Servidores:** listar, buscar (com contador), criar, novo código, desativar.
- **Parceiros:** 3 abas, cobrança **idempotente**, limite de extensões da
  carência, salvar configuração.

## Limites (seja honesto ao ler o resultado)

O `fake_api.py` **imita** as regras do backend — ele não é o backend. Isto testa
o PAINEL (a tela e o que ela envia), não as RPCs do Postgres nem as Edge
Functions. Ao mudar uma regra no `schema-tv.sql` ou em
`supabase/functions/painel/`, atualize o fake junto, senão o teste passa a
validar uma regra que não existe mais.

⚠️ `inner_text()` do Playwright aplica o `text-transform` do CSS: cabeçalho de
tabela e badge voltam em CAIXA ALTA. Compare em minúsculas (já mordeu uma vez).
