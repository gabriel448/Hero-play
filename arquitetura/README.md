# Arquitetura — Hero Play

Documentação da arquitetura do **Hero Play**, um player IPTV multiplataforma
(Android, Windows, tablet) feito em Flutter que lê listas M3U.

Esta pasta descreve **como o app está organizado por dentro** — as camadas, o
fluxo de dados, as decisões de design e os pipelines de processamento. É o
material de onboarding para quem vai dar manutenção ou portar o app.

## Índice

| Documento | Conteúdo |
|---|---|
| [visao-geral.md](visao-geral.md) | Princípios, stack, fluxo de dados de alto nível, diagrama de camadas |
| [camadas.md](camadas.md) | As 4 camadas (models → services → state → UI) e regras de dependência |
| [modelos.md](modelos.md) | Modelos de dados: `Canal`, `Serie`, `ListaM3U`, `Programa`, etc. |
| [servicos.md](servicos.md) | Camada de serviços: parser, carregadores, players, EPG, TMDB |
| [estado.md](estado.md) | Providers (`IptvProvider`, `MiniPlayerProvider`, `PreferenciasProvider`) |
| [ui-e-navegacao.md](ui-e-navegacao.md) | Telas, layout responsivo, mini player, navegação |
| [pipeline-de-dados.md](pipeline-de-dados.md) | Importação → parse → agrupamento → qualidade → séries |
| [persistencia.md](persistencia.md) | Hive: boxes, chaves e formato de serialização |
| [build-e-deploy.md](build-e-deploy.md) | Build Android/Windows, assinatura, instalador, releases, API, site |

## Mapa rápido do código

```
lib/
├── main.dart          # Bootstrap: Hive, MediaKit, dotenv, providers → runApp
├── app.dart           # MaterialApp, tema, roteamento inicial (onboarding/home)
├── models/            # Estruturas de dados puras (sem lógica de UI)
├── services/          # I/O, parsing, players, integração externa
├── state/             # ChangeNotifier providers (estado + ações)
├── screens/           # Telas completas (rotas)
├── widgets/           # Componentes reutilizáveis (mini player, item canal…)
├── theme/             # Tokens de design e ThemeData
└── utils/             # Layout responsivo, qualidade, navegação

API/                   # Proxy serverless Node.js (TMDB) — deploy Vercel
website/               # Landing page estática — deploy Vercel
```

## Documentos complementares (na raiz)

- [`../DESIGN.md`](../DESIGN.md) — sistema de design (cores, spacing, tipografia)
- [`../PRODUCT.md`](../PRODUCT.md) — decisões de produto e público-alvo
- [`../README.md`](../README.md) — visão geral, downloads, setup