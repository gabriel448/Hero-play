# Hero Play

Player IPTV multiplataforma feito com Flutter. Importe qualquer lista M3U, navegue por canais ao vivo, filmes e séries — com interface adaptada para celular, tablet e desktop.

## Download

| Plataforma | Link |
|---|---|
| Android (APK) | [Hero_Play_v1.2.1.apk](https://github.com/gabriel448/IPTV/releases/download/v1.2.1/Hero_Play_v1.2.1.apk) |
| Windows (Instalador) | [Hero_Play_Setup_1.2.1.exe](https://github.com/gabriel448/IPTV/releases/download/v1.2.1/Hero_Play_Setup_1.2.1.exe) |

## Funcionalidades

- Importação de listas M3U por URL ou arquivo local
- Canais ao vivo, filmes e séries na mesma interface
- Player baseado em **libmpv** via `media_kit` — suporta HLS, MPEG-TS, RTSP e codecs exóticos
- Favoritos e histórico persistidos localmente (Hive)
- Categorias personalizadas
- Busca de metadados (sinopse, elenco, ano) via TMDB
- Mini player flutuante no desktop — redimensionável e arrastável
- Onboarding de idioma na primeira abertura
- Interface responsiva: layout diferente para celular, tablet e desktop

## Plataformas

| Plataforma | Status |
|---|---|
| Android | Disponível |
| Windows | Disponível |
| macOS | Em breve |
| Linux | Em breve |

## Tecnologias

| Pacote | Uso |
|---|---|
| `media_kit` + `media_kit_video` | Player de vídeo (libmpv) |
| `hive` + `hive_flutter` | Banco de dados local (favoritos, histórico, listas) |
| `provider` | Gerenciamento de estado |
| `http` | Download de listas M3U por URL |
| `google_fonts` | Fonte Manrope |
| `flutter_dotenv` | Variáveis de ambiente em runtime |
| `marquee` | Título rolante em VOD |
| `path_provider` | Caminhos do sistema de arquivos |

## Estrutura do projeto

```
lib/
├── main.dart                  # Inicialização (Hive, MediaKit, dotenv, providers)
├── app.dart                   # MaterialApp + roteamento inicial
├── models/                    # Canal, ListaM3U, Serie, Categoria, etc.
├── screens/                   # Telas (inicial, player, filmes, séries, detalhes…)
├── services/                  # Parser M3U, carregador, player ao vivo/VOD, TMDB, armazenamento
├── state/                     # IptvProvider, PreferenciasProvider, MiniPlayerProvider
├── theme/                     # AppTheme (tema escuro)
├── utils/                     # Layout responsivo, nav keys, qualidade
└── widgets/                   # ShellDesktop, MiniPlayerOverlay, ItemCanal, etc.

API/                           # Proxy serverless para o TMDB (Vercel)
website/                       # Site estático (Vercel)
assets/                        # Ícones do app
installer.iss                  # Script Inno Setup para o instalador Windows
build_installer.ps1            # Script que faz build Flutter + gera o instalador
```

## Configuração

### Variáveis de ambiente

Crie um arquivo `.env` na raiz do projeto:

```env
TMDB_PROXY_URL=https://sua-api.vercel.app/api/tmdb
```

O proxy TMDB é necessário para buscar metadados de filmes e séries. Sem ele, o app funciona normalmente — os metadados ficam em branco.

### Rodando em desenvolvimento

```bash
flutter pub get
flutter run
```

### Build Android (APK)

```bash
flutter build apk --release
# Saída: build/app/outputs/flutter-apk/app-release.apk
```

### Build Windows + Instalador

Requer [Inno Setup](https://jrsoftware.org/isinfo.php) instalado.

```powershell
.\build_installer.ps1
# Saída: installer_output/Hero_Play_Setup_<versão>.exe
```

O script lê a versão direto do `pubspec.yaml`, compila o Flutter em release e gera o instalador automaticamente.

## API Proxy (TMDB)

A pasta `API/` contém um proxy serverless em Node.js deployado no Vercel. Ele injeta a chave de API do TMDB server-side para que a chave não fique exposta no app.

Configure a variável `TMDB_API_KEY` nas Environment Variables do projeto Vercel da API.

## Site

O site está em `website/index.html` e é deployado no Vercel. Para apontar o Vercel para a subpasta correta, configure o **Root Directory** como `website` nas Settings do projeto no dashboard do Vercel.
