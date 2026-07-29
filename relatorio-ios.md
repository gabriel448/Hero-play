# Hero Play no iPhone — onde estamos

**29/07/2026**

## Resumo em uma linha

O app **já compila para iPhone** — isso foi validado hoje, com build de verdade.
Falta um iPhone na mão pra testar, e uma decisão sobre como mandar pra testador.

## O que foi feito

Portamos o app (Android/Windows) para iOS e rodamos a primeira build de verdade
num Mac alugado na nuvem — não precisou comprar Mac. Saiu um arquivo `.ipa` de
14 MB, que é o instalador do iPhone.

O maior risco técnico era o **player de vídeo**. O Hero Play não usa o player
comum do sistema: usa um motor próprio (libmpv/FFmpeg), que é o que segura canal
ao vivo e formatos que os players de prateleira engasgam. A dúvida era se esse
motor existia compilado pra iPhone. **Existe** — está dentro do `.ipa` que
geramos, junto com todos os outros componentes do app.

Também já ficaram resolvidos, no código:

- Liberação de listas `http://` (o iPhone bloqueia por padrão e o vídeo não abriria).
- Áudio continuando com a tela apagada.
- Identidade do aparelho guardada de forma que **reinstalar o app não perde a
  ativação** — o mesmo problema que corrigimos no TV Box.
- Aceleração de vídeo por hardware (4K sem fritar a bateria).

Custo de tudo isso até agora: **zero**.

## O que falta

### 1. Um iPhone (bloqueador)
Não temos nenhum aqui. Qualquer iPhone com iOS 13 ou mais novo serve. Sem
aparelho não há teste — compilar não é a mesma coisa que funcionar.

### 2. Decidir como instalar
| Caminho | Custo | Como é |
|---|---|---|
| **Teste interno** | grátis | Cabo USB + PC. O app vale **7 dias** e depois precisa religar no PC. Serve pra validar na mesa. |
| **TestFlight** | **US$ 99/ano** | Manda um link, a pessoa instala sozinha, app vale 1 ano. É o caminho pra testador de fora. |

A conta paga da Apple só é necessária pra **mandar pra outra pessoa**. Pra testar
aqui dentro, não.

### 3. Acabamento (meia hora de trabalho)
Ícone e tela de abertura ainda são os padrões do Flutter.

### 4. Testar na mão
Filme e canal ao vivo tocando, lista carregando, áudio com a tela apagada, e a
ativação não mudando ao reinstalar.

## O que muda no negócio (importante)

**No iPhone não existe o "baixe o APK no site".** No Android a gente distribui
direto pelo nosso site; na Apple isso é impossível — todo mundo instala pela App
Store, e ponto. Consequências:

1. A versão de iPhone tem que ser a **neutra**: abre vazia, sem venda nenhuma
   dentro do app, sem a palavra "IPTV". O app já foi construído assim de
   propósito, então não é retrabalho.
2. A Apple é a loja mais rígida com player de lista M3U. Os motivos comuns de
   recusa são "app genérico demais" e dúvida sobre direitos do conteúdo. Dá pra
   passar, mas costuma levar algumas idas e voltas de revisão — conta semanas,
   não dias.
3. Toda a parte de revenda continua no site/painel, como já é hoje.

## Resumo dos custos

| Item | Custo |
|---|---|
| Build (Mac na nuvem) | grátis |
| Teste interno com cabo | grátis |
| TestFlight / App Store | US$ 99/ano |
| Comprar um Mac | não é necessário |

## O que eu preciso de você

1. **Um iPhone emprestado** pra testar — é o que trava tudo.
2. Decidir se a gente paga os **US$ 99/ano** agora (pra mandar pra testador de
   fora) ou depois de validar internamente.
