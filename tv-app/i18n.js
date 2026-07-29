/* ============================================================================
   Hero Play TV — i18n (PT-BR base + EN + ES).
   A CHAVE é a própria string em português: t('Buscar') → 'Search'/'Buscar'.
   Strings não traduzidas caem no PT (fallback), sem quebrar nada.
   Placeholders: t('Restam {n} dia(s)').replace('{n}', 5).
   ============================================================================ */
const I18N = {
  en: {
    // Menu
    'Início': 'Home', 'TV ao vivo': 'Live TV', 'Filmes': 'Movies', 'Séries': 'Series',
    'Playlists': 'Playlists', 'Buscar': 'Search', 'Jogos do dia': "Today's games", 'Futebol': 'Football', 'Voltar': 'Back',
    'Configurações': 'Settings',
    // Perfis
    'Quem está assistindo?': "Who's watching?", 'Adicionar perfil': 'Add profile', 'Gerenciar perfis': 'Manage profiles',
    'Novo perfil': 'New profile', 'Editar perfil': 'Edit profile', 'Nome do perfil': 'Profile name', 'Criar': 'Create', 'Salvar': 'Save',
    'Continuar assistindo': 'Continue watching', 'Recomendações pra você': 'Recommended for you',
    'Perfis': 'Profiles', 'Perfil ativo e gerenciamento.': 'Active profile and management.', 'Trocar perfil': 'Switch profile',
    // Jogos
    'Ontem': 'Yesterday', 'Hoje': 'Today', 'Amanhã': 'Tomorrow', 'Onde assistir': 'Where to watch',
    'Rodada': 'Round', 'Carregando jogos…': 'Loading matches…', 'Nenhum jogo nesta data': 'No matches on this date',
    'Não disponível na sua lista': 'Not available in your list',
    '9+ canais': '9+ channels', '1 canal': '1 channel', '{n} canais': '{n} channels',
    // Hero / detalhe
    'Assistir': 'Watch', 'Minha Lista': 'My List', 'Episódios e mais': 'Episodes & more',
    'Continuar': 'Resume', 'Do início': 'From start', 'Continuar assistindo?': 'Resume watching?',
    'Parou em': 'Stopped at', 'Remover da Minha Lista': 'Remove from My List',
    'Adicionado à Minha Lista': 'Added to My List', 'Removido da Minha Lista': 'Removed from My List',
    'Elenco': 'Cast', 'Títulos semelhantes': 'Similar titles', 'Série': 'Series', 'Filme': 'Movie',
    'Temporada': 'Season',
    'Sem descrição disponível.': 'No description available.', 'Direção': 'Directed by',
    'Gêneros': 'Genres', 'Sinopse': 'Synopsis', 'Informações': 'Information',
    'Sem informações adicionais.': 'No additional information.', 'Minha Lista — em breve': 'My List — coming soon',
    // Placeholders / seções
    'Nada por aqui': 'Nothing here', 'Sua lista não tem itens nesta seção.': 'Your list has no items in this section.',
    'Agenda de jogos + onde assistir (próxima fase).': 'Match schedule + where to watch (next phase).',
    // TV ao vivo
    'Favoritos': 'Favorites', 'Favoritar': 'Favorite', 'Ao vivo': 'Live', 'Categorias': 'Categories', 'Canais ao vivo': 'Live channels',
    'Selecione uma categoria e um canal': 'Select a category and a channel', 'Programação': 'Schedule',
    'AGORA': 'NOW', 'Programa seguinte': 'Next program', 'Mais tarde': 'Later',
    'Abrir em tela cheia': 'Open fullscreen', 'Nenhum canal favoritado ainda': 'No favorite channels yet',
    'Adicionado aos favoritos': 'Added to favorites', 'Removido dos favoritos': 'Removed from favorites',
    'Qualidade': 'Quality', 'Fontes': 'Sources', 'Fonte': 'Source',
    'Carregando catálogo salvo…': 'Loading saved catalog…', 'Salvando catálogo para abrir rápido…': 'Saving catalog for fast startup…', 'Origem do catálogo': 'Catalog source', 'Cache — leitura': 'Cache — read', 'Cache — gravação': 'Cache — write', 'Cache — capas (TMDB)': 'Cache — artwork (TMDB)', 'Procurando legendas…': 'Looking for subtitles…', 'Procurando faixas de áudio…': 'Looking for audio tracks…', 'Sair do Hero Play?': 'Exit Hero Play?', 'Você voltará à tela inicial da TV.': "You'll return to the TV home screen.", 'Digite o PIN atual': 'Enter the current PIN', 'Carregando legenda…': 'Loading subtitle…', 'Legenda ativada': 'Subtitle on', 'Não foi possível carregar a legenda': "Couldn't load the subtitle",
    'Cache (rápido)': 'Cache (fast)', 'Parse da lista': 'Parsed from list',
    'Diagnóstico (memória)': 'Diagnostics (memory)', 'Heap em uso agora': 'Heap in use now',
    'Limite de heap (orçamento da TV)': 'Heap limit (TV budget)', 'Uso': 'Usage',
    'Heap antes do parse': 'Heap before parse', 'Heap logo após o parse': 'Heap right after parse',
    'Custo do parse': 'Parse cost', 'Tempo do parse': 'Parse time', 'Tamanho da lista (texto)': 'List size (text)',
    'Canais': 'Channels', 'Filmes': 'Movies', 'Séries': 'Series', 'Episódios': 'Episodes', 'Total de itens': 'Total items',
    'Se o "Uso" passa de ~70% do limite, a TV pode encerrar o app. Use estes números para decidir as otimizações.':
      'If "Usage" goes above ~70% of the limit, the TV may kill the app. Use these numbers to guide the optimizations.',
    'Legendas': 'Subtitles', 'Legenda': 'Subtitle', 'Áudio': 'Audio', 'Desativadas': 'Off',
    'Legendas desativadas': 'Subtitles off',
    'Este conteúdo não oferece legendas': 'This content has no subtitles',
    'Este conteúdo tem apenas uma faixa de áudio': 'This content has only one audio track',
    'Sem outras qualidades nesta fonte': 'No other qualities in this source', 'Sem outras fontes': 'No other sources',
    'Programação — em breve': 'Schedule — coming soon', 'Legendas — em breve': 'Subtitles — coming soon',
    'Faixas de áudio — em breve': 'Audio tracks — coming soon',
    'Não foi possível reproduzir. O formato pode exigir o player nativo da TV.': "Could not play. The format may require the TV's native player.",
    'Não foi possível reproduzir este conteúdo.': 'Could not play this content.',
    // Busca
    'Buscar…': 'Search…', 'Espaço': 'Space', 'Limpar': 'Clear',
    'Encontre seus filmes e séries': 'Find your movies and series',
    'Digite o nome no teclado ao lado para começar': 'Type the name on the keyboard to start',
    'Confira a digitação ou tente outro título': 'Check your spelling or try another title',
    'Sugestões': 'Suggestions', 'Resultados prováveis': 'Likely results',
    'Buscar em Séries': 'Search in Series', 'Buscar em Filmes': 'Search in Movies', 'Todos': 'All',
    'Nada encontrado para “{q}”': 'No results for “{q}”',
    // Teclado
    'Digite': 'Type', 'Digite…': 'Type…',
    // Onboarding / adicionar playlist
    'Adicionar Playlist': 'Add Playlist', 'Adicione e ative <b>tudo pelo site</b>': 'Add and activate <b>everything on the site</b>',
    '↻ Recarregar': '↻ Reload', 'ou': 'or',
    'Use as credenciais ou a URL da playlist no formulário ao lado': 'Use the credentials or the playlist URL in the form',
    'Use as credenciais ou a URL da playlist ao lado': 'Use the credentials or the playlist URL',
    'Entrar com credenciais': 'Sign in with credentials', 'Adicionar por credenciais ou Link': 'Add by credentials or Link',
    'Servidor (http://host:porta)': 'Server (http://host:port)', 'Usuário': 'Username', 'Senha': 'Password', 'Conectar': 'Connect',
    'Preencha servidor, usuário e senha.': 'Fill in server, username and password.',
    'Informe uma URL M3U válida (http/https).': 'Enter a valid M3U URL (http/https).',
    'Verificando…': 'Checking…', 'Nenhuma lista ainda. Adicione no celular e tente de novo.': 'No list yet. Add it on your phone and try again.',
    'Adicionando sua lista…': 'Adding your list…',
    'Aguardando a playlist…': 'Waiting for the playlist…',
    'Playlist encontrada! Carregando…': 'Playlist found! Loading…', 'Adicionando playlist…': 'Adding playlist…',
    'Carregando títulos…': 'Loading titles…', 'Organizando seus canais…': 'Organizing your channels…',
    'Baixando sua lista…': 'Downloading your list…', 'Preparando seus banners…': 'Preparing your banners…',
    'Não foi possível carregar sua lista. Verifique a URL/conexão.': 'Could not load your list. Check the URL/connection.',
    'Carregando…': 'Loading…',
    'Está demorando mais que o normal.': 'This is taking longer than usual.',
    'Tentar de novo': 'Try again', 'Continuar sem a lista': 'Continue without the list',
    'Sua lista não carregou. Tente Recarregar em Configurações.': 'Your list did not load. Try Reload in Settings.',
    // Aviso de teste
    'Período de teste': 'Trial period', '{n} dias grátis': '{n} free days',
    'Sua lista foi adicionada e o app está em teste. Para continuar depois do período, ative o app — você mesmo pode ativar escaneando o QR.': 'Your list was added and the app is in trial. To continue after the trial, activate the app — you can activate it yourself by scanning the QR.',
    'Ativar / gerenciar': 'Activate / manage', 'Continuar no teste': 'Continue trial',
    // Playlists
    'Minhas Playlists': 'My Playlists', 'Atualizar': 'Refresh', 'Carregando playlists…': 'Loading playlists…',
    'Nenhuma playlist': 'No playlists', 'Nenhuma playlist neste dispositivo': 'No playlists on this device',
    'Use "Adicionar Playlist" para começar': 'Use "Add Playlist" to start', 'Recarregar títulos': 'Reload titles',
    'Excluir': 'Delete', 'Excluindo…': 'Deleting…', 'Playlist excluída': 'Playlist deleted',
    'Recarregando títulos…': 'Reloading titles…', 'Selecionando…': 'Selecting…', 'Pronto': 'Done',
    'Atualizando…': 'Refreshing…', 'playlist': 'playlist', 'playlists': 'playlists',
    // Status
    'Em teste': 'In trial', 'Ativo': 'Active', 'Expirado': 'Expired', 'Sem lista': 'No list',
    // ── Configurações ──
    'Interface': 'Interface', 'Privacidade': 'Privacy', 'Dados': 'Data', 'Conta': 'Account',
    'Jogos': 'Games', 'Clima': 'Weather', 'Info': 'Info',
    'Idioma da interface': 'Interface language', 'Controle dos pais': 'Parental control',
    'Limpar cache': 'Clear cache', 'Limpar histórico': 'Clear history', 'Playlist ativa': 'Active playlist',
    'Minhas Informações': 'My Information', 'Gerenciar alertas': 'Manage alerts', 'Clima & Horário': 'Weather & Time',
    'Sobre / Versão': 'About / Version', 'Termos de uso': 'Terms of use', 'Testar velocidade de conexão': 'Test connection speed',
    'Idioma:': 'Language:',
    // Qualidade dos canais
    'Qualidade dos canais': 'Channel quality', 'Ajustes de reprodução dos canais ao vivo.': 'Live channel playback settings.',
    'Troca automática de qualidade': 'Automatic quality switching',
    'Se o canal ficar travando, baixa a qualidade automaticamente. Se o canal cair, troca para outra fonte.': 'If the channel keeps buffering, it lowers the quality automatically. If the channel drops, it switches to another source.',
    'Qualidade padrão': 'Default quality', 'Qualidade com prioridade ao abrir um canal.': 'Quality prioritized when opening a channel.',
    'Máxima': 'Maximum', 'Mínima': 'Minimum',
    'Troca automática ativada': 'Automatic switching on', 'Troca automática desativada': 'Automatic switching off',
    'Conexão instável — qualidade reduzida': 'Unstable connection — quality reduced',
    'Canal instável — trocando de fonte…': 'Channel unstable — switching source…', 'Principal': 'Main',
    // Parental
    'ATIVADO': 'ON', 'DESATIVADO': 'OFF', 'Definir PIN': 'Set PIN', 'Alterar PIN': 'Change PIN',
    'Bloqueios por categoria': 'Category blocks', 'Canais': 'Channels',
    'Nenhuma bloqueada': 'None blocked', '{n} bloqueadas': '{n} blocked', '{n} bloqueada': '{n} blocked',
    'Controle dos pais ativado': 'Parental control enabled', 'Controle dos pais desativado': 'Parental control disabled',
    '{rot} — Categorias bloqueadas': '{rot} — Blocked categories', '‹ Voltar': '‹ Back',
    'OK para bloquear / desbloquear': 'OK to block / unblock', 'bloqueada': 'blocked', 'livre': 'free',
    'Nenhuma categoria nesta lista': 'No categories in this list', 'Defina um PIN de 4 dígitos': 'Set a 4-digit PIN',
    'O PIN deve ter 4 dígitos': 'PIN must be 4 digits', 'PIN definido': 'PIN set',
    'Conteúdo bloqueado — digite o PIN': 'Blocked content — enter the PIN', 'PIN incorreto': 'Wrong PIN',
    // Dados
    'Limpa o cache de dados do app (início, canais, filmes, séries). O conteúdo será baixado novamente na próxima abertura.': 'Clears the app data cache (home, channels, movies, series). Content will be downloaded again on next launch.',
    'Limpar Cache': 'Clear Cache', 'Limpar cache?': 'Clear cache?', 'O conteúdo será baixado novamente.': 'Content will be downloaded again.',
    'Cache limpo — recarregando…': 'Cache cleared — reloading…',
    'Apaga o histórico de reprodução. Todo o progresso de episódios e filmes será perdido.': 'Erases the playback history. All episode and movie progress will be lost.',
    'Limpar Histórico': 'Clear History', 'Limpar histórico?': 'Clear history?', 'Todo o progresso será perdido.': 'All progress will be lost.',
    'Histórico limpo': 'History cleared', 'Cancelar': 'Cancel', 'Confirmar': 'Confirm',
    // Conta
    'Adicione, remova ou troque sua playlist ativa na aba de Playlists.': 'Add, remove or switch your active playlist in the Playlists tab.',
    'Gerenciar Playlists': 'Manage Playlists',
    'A licença do app (ativada pelo revendedor) e a conta da sua playlist (do provedor) são coisas diferentes — veja cada uma abaixo.': 'The app license (activated by the reseller) and your playlist account (from the provider) are different things — see each below.',
    'Licença do app (Hero Play)': 'App license (Hero Play)',
    'Ativação do dispositivo — feita pelo revendedor no painel (MAC + Key)': 'Device activation — done by the reseller in the panel (MAC + Key)',
    'Verificar status da Licença': 'Check License status', 'Playlist (conta do seu provedor)': 'Playlist (your provider account)',
    'Verificar status da playlist': 'Check playlist status', 'Carregando dados da playlist…': 'Loading playlist data…',
    'Sem conta de provedor para esta playlist (lista M3U sem login Xtream).': 'No provider account for this playlist (M3U list without Xtream login).',
    'Não foi possível carregar os dados da playlist (servidor fora do ar ou bloqueio do navegador).': 'Could not load playlist data (server down or browser block).',
    'Status': 'Status', 'Conex. máximas': 'Max connections', 'Conex. ativas': 'Active connections',
    'Conta trial': 'Trial account', 'Sim': 'Yes', 'Não': 'No', 'Criado em': 'Created on',
    'VENCIMENTO DA PLAYLIST': 'PLAYLIST EXPIRATION', 'Verificando licença…': 'Checking license…',
    'Licença atualizada': 'License updated', 'Verificando playlist…': 'Checking playlist…',
    'Playlist atualizada': 'Playlist updated', 'Não foi possível verificar': 'Could not verify',
    // Licença
    'Licença Ativa': 'License Active', 'Vitalícia': 'Lifetime', 'Restam {n} dia(s)': '{n} day(s) left',
    'Licença expirada': 'License expired', 'Renove pelo site': 'Renew on the website', 'Sem licença': 'No license',
    'Adicione uma playlist': 'Add a playlist', 'Licença do App': 'App License',
    // Alertas
    'Como funcionam os alertas:': 'How alerts work:',
    'você será notificado 30 min, 15 min, 5 min e na hora da partida. Adicione alertas na aba Futebol.': "you'll be notified 30 min, 15 min, 5 min and at match time. Add alerts in the Football tab.",
    'Nenhum alerta salvo': 'No alerts saved', 'Adicione alertas na aba Futebol.': "Add alerts in the Football tab.",
    'Testar Notificação': 'Test Notification', 'Notificação enviada ✔': 'Notification sent ✔',
    'Notificações bloqueadas neste dispositivo': 'Notifications blocked on this device', 'Notificação de teste ✔': 'Test notification ✔',
    // Clima
    'Carregando clima…': 'Loading weather…',
    'Ensolarado': 'Sunny', 'Predom. limpo': 'Mostly clear', 'Parcial. nublado': 'Partly cloudy', 'Nublado': 'Cloudy',
    'Nevoeiro': 'Fog', 'Garoa leve': 'Light drizzle', 'Garoa': 'Drizzle', 'Garoa forte': 'Heavy drizzle',
    'Chuva leve': 'Light rain', 'Chuva': 'Rain', 'Chuva forte': 'Heavy rain', 'Neve leve': 'Light snow',
    'Neve': 'Snow', 'Neve forte': 'Heavy snow', 'Pancadas': 'Showers', 'Pancadas fortes': 'Heavy showers', 'Tempestade': 'Storm',
    'Sensação térmica': 'Feels like', 'Humidade': 'Humidity', 'Vento': 'Wind', 'Índice UV': 'UV Index',
    'Visibilidade': 'Visibility', 'Pressão': 'Pressure', 'Precipitação': 'Precipitation',
    'Não foi possível obter o clima.': 'Could not get the weather.', 'Tentar de novo': 'Try again',
    'Localização desconhecida': 'Unknown location',
    // Sobre
    'Versão do App': 'App Version', 'Dispositivo': 'Device', 'Endereço MAC': 'MAC Address', 'Device Key': 'Device Key',
    'Web / Navegador': 'Web / Browser', 'Escaneie para acessar o site:': 'Scan to visit the website:',
    'Todos os direitos reservados.': 'All rights reserved.',
    // Termos
    'Leia os Termos de Uso e a Política de Privacidade do Hero Play.': "Read Hero Play's Terms of Use and Privacy Policy.",
    'Abrir Termos de Uso': 'Open Terms of Use', 'Termos de uso e Privacidade': 'Terms of Use and Privacy',
    'Escaneie o código para ler os Termos de Uso e a Política de Privacidade no site.': 'Scan the code to read the Terms of Use and Privacy Policy on the site.',
    'Fechar': 'Close',
    // Velocidade
    'Baixa ~5 MB de um servidor de teste e mede a velocidade de download da sua conexão.': "Downloads ~5 MB from a test server and measures your connection's download speed.",
    'Pressione OK para medir sua conexão': 'Press OK to measure your connection', 'Iniciar Teste de Velocidade': 'Start Speed Test',
    'Medindo sua conexão…': 'Measuring your connection…', 'Conexão Boa': 'Good Connection', 'Conexão Média': 'Average Connection',
    'Conexão Ruim': 'Poor Connection', 'Falha no teste. Verifique a conexão.': 'Test failed. Check your connection.',
    'Testar de novo': 'Test again', 'Testando…': 'Testing…',
  },
  es: {
    // Menu
    'Início': 'Inicio', 'TV ao vivo': 'TV en vivo', 'Filmes': 'Películas', 'Séries': 'Series',
    'Playlists': 'Listas', 'Buscar': 'Buscar', 'Jogos do dia': 'Partidos del día', 'Futebol': 'Fútbol', 'Voltar': 'Atrás', 'Configurações': 'Configuración',
    // Perfis
    'Quem está assistindo?': '¿Quién está viendo?', 'Adicionar perfil': 'Añadir perfil', 'Gerenciar perfis': 'Gestionar perfiles',
    'Novo perfil': 'Nuevo perfil', 'Editar perfil': 'Editar perfil', 'Nome do perfil': 'Nombre del perfil', 'Criar': 'Crear', 'Salvar': 'Guardar',
    'Continuar assistindo': 'Seguir viendo', 'Recomendações pra você': 'Recomendado para ti',
    'Perfis': 'Perfiles', 'Perfil ativo e gerenciamento.': 'Perfil activo y gestión.', 'Trocar perfil': 'Cambiar perfil',
    // Jogos
    'Ontem': 'Ayer', 'Hoje': 'Hoy', 'Amanhã': 'Mañana', 'Onde assistir': 'Dónde ver',
    'Rodada': 'Jornada', 'Carregando jogos…': 'Cargando partidos…', 'Nenhum jogo nesta data': 'Sin partidos en esta fecha',
    'Não disponível na sua lista': 'No disponible en tu lista',
    '9+ canais': '9+ canales', '1 canal': '1 canal', '{n} canais': '{n} canales',
    // Hero / detalhe
    'Assistir': 'Ver', 'Minha Lista': 'Mi Lista', 'Episódios e mais': 'Episodios y más',
    'Continuar': 'Continuar', 'Do início': 'Desde el inicio', 'Continuar assistindo?': '¿Continuar viendo?',
    'Parou em': 'Pausado en', 'Remover da Minha Lista': 'Quitar de Mi Lista',
    'Adicionado à Minha Lista': 'Añadido a Mi Lista', 'Removido da Minha Lista': 'Quitado de Mi Lista',
    'Elenco': 'Reparto', 'Títulos semelhantes': 'Títulos similares', 'Série': 'Serie', 'Filme': 'Película',
    'Temporada': 'Temporada',
    'Sem descrição disponível.': 'Sin descripción disponible.', 'Direção': 'Dirección',
    'Gêneros': 'Géneros', 'Sinopse': 'Sinopsis', 'Informações': 'Información',
    'Sem informações adicionais.': 'Sin información adicional.', 'Minha Lista — em breve': 'Mi Lista — próximamente',
    // Placeholders
    'Nada por aqui': 'Nada por aquí', 'Sua lista não tem itens nesta seção.': 'Tu lista no tiene elementos en esta sección.',
    'Agenda de jogos + onde assistir (próxima fase).': 'Agenda de partidos + dónde ver (próxima fase).',
    // TV ao vivo
    'Favoritos': 'Favoritos', 'Favoritar': 'Favorito', 'Ao vivo': 'En vivo', 'Categorias': 'Categorías', 'Canais ao vivo': 'Canales en vivo',
    'Selecione uma categoria e um canal': 'Selecciona una categoría y un canal', 'Programação': 'Programación',
    'AGORA': 'AHORA', 'Programa seguinte': 'Programa siguiente', 'Mais tarde': 'Más tarde',
    'Abrir em tela cheia': 'Abrir en pantalla completa', 'Nenhum canal favoritado ainda': 'Aún no hay canales favoritos',
    'Adicionado aos favoritos': 'Añadido a favoritos', 'Removido dos favoritos': 'Eliminado de favoritos',
    'Qualidade': 'Calidad', 'Fontes': 'Fuentes', 'Fonte': 'Fuente',
    'Carregando catálogo salvo…': 'Cargando catálogo guardado…', 'Salvando catálogo para abrir rápido…': 'Guardando catálogo para inicio rápido…', 'Origem do catálogo': 'Origen del catálogo', 'Cache — leitura': 'Caché — lectura', 'Cache — gravação': 'Caché — escritura', 'Cache — capas (TMDB)': 'Caché — carátulas (TMDB)', 'Procurando legendas…': 'Buscando subtítulos…', 'Procurando faixas de áudio…': 'Buscando pistas de audio…', 'Sair do Hero Play?': '¿Salir de Hero Play?', 'Você voltará à tela inicial da TV.': 'Volverás a la pantalla de inicio del televisor.', 'Digite o PIN atual': 'Introduce el PIN actual', 'Carregando legenda…': 'Cargando subtítulo…', 'Legenda ativada': 'Subtítulo activado', 'Não foi possível carregar a legenda': 'No se pudo cargar el subtítulo',
    'Cache (rápido)': 'Caché (rápido)', 'Parse da lista': 'Parseado de la lista',
    'Diagnóstico (memória)': 'Diagnóstico (memoria)', 'Heap em uso agora': 'Heap en uso ahora',
    'Limite de heap (orçamento da TV)': 'Límite de heap (presupuesto del TV)', 'Uso': 'Uso',
    'Heap antes do parse': 'Heap antes del parseo', 'Heap logo após o parse': 'Heap tras el parseo',
    'Custo do parse': 'Costo del parseo', 'Tempo do parse': 'Tiempo del parseo', 'Tamanho da lista (texto)': 'Tamaño de la lista (texto)',
    'Canais': 'Canales', 'Filmes': 'Películas', 'Séries': 'Series', 'Episódios': 'Episodios', 'Total de itens': 'Total de ítems',
    'Se o "Uso" passa de ~70% do limite, a TV pode encerrar o app. Use estes números para decidir as otimizações.':
      'Si el "Uso" supera ~70% del límite, el TV puede cerrar la app. Usa estos números para guiar las optimizaciones.',
    'Legendas': 'Subtítulos', 'Legenda': 'Subtítulo', 'Áudio': 'Audio', 'Desativadas': 'Desactivados',
    'Legendas desativadas': 'Subtítulos desactivados',
    'Este conteúdo não oferece legendas': 'Este contenido no ofrece subtítulos',
    'Este conteúdo tem apenas uma faixa de áudio': 'Este contenido tiene solo una pista de audio',
    'Sem outras qualidades nesta fonte': 'Sin otras calidades en esta fuente', 'Sem outras fontes': 'Sin otras fuentes',
    'Programação — em breve': 'Programación — próximamente', 'Legendas — em breve': 'Subtítulos — próximamente',
    'Faixas de áudio — em breve': 'Pistas de audio — próximamente',
    'Não foi possível reproduzir. O formato pode exigir o player nativo da TV.': 'No se pudo reproducir. El formato puede requerir el reproductor nativo del TV.',
    'Não foi possível reproduzir este conteúdo.': 'No se pudo reproducir este contenido.',
    // Busca
    'Buscar…': 'Buscar…', 'Espaço': 'Espacio', 'Limpar': 'Borrar',
    'Encontre seus filmes e séries': 'Encuentra tus películas y series',
    'Digite o nome no teclado ao lado para começar': 'Escribe el nombre en el teclado para empezar',
    'Confira a digitação ou tente outro título': 'Revisa la escritura o prueba otro título',
    'Sugestões': 'Sugerencias', 'Resultados prováveis': 'Resultados probables',
    'Buscar em Séries': 'Buscar en Series', 'Buscar em Filmes': 'Buscar en Películas', 'Todos': 'Todos',
    'Nada encontrado para “{q}”': 'Sin resultados para “{q}”',
    // Teclado
    'Digite': 'Escribe', 'Digite…': 'Escribe…',
    // Onboarding
    'Adicionar Playlist': 'Añadir Lista', 'Adicione e ative <b>tudo pelo site</b>': 'Añade y activa <b>todo en el sitio</b>',
    '↻ Recarregar': '↻ Recargar', 'ou': 'o',
    'Use as credenciais ou a URL da playlist no formulário ao lado': 'Usa las credenciales o la URL de la lista en el formulario',
    'Use as credenciais ou a URL da playlist ao lado': 'Usa las credenciales o la URL de la lista',
    'Entrar com credenciais': 'Entrar con credenciales', 'Adicionar por credenciais ou Link': 'Añadir por credenciales o enlace',
    'Servidor (http://host:porta)': 'Servidor (http://host:puerto)', 'Usuário': 'Usuario', 'Senha': 'Contraseña', 'Conectar': 'Conectar',
    'Preencha servidor, usuário e senha.': 'Completa servidor, usuario y contraseña.',
    'Informe uma URL M3U válida (http/https).': 'Ingresa una URL M3U válida (http/https).',
    'Verificando…': 'Verificando…', 'Nenhuma lista ainda. Adicione no celular e tente de novo.': 'Aún no hay lista. Añádela en el móvil e intenta de nuevo.',
    'Adicionando sua lista…': 'Añadiendo tu lista…',
    'Aguardando a playlist…': 'Esperando la lista…',
    'Playlist encontrada! Carregando…': '¡Lista encontrada! Cargando…', 'Adicionando playlist…': 'Añadiendo lista…',
    'Carregando títulos…': 'Cargando títulos…', 'Organizando seus canais…': 'Organizando tus canales…',
    'Baixando sua lista…': 'Descargando tu lista…', 'Preparando seus banners…': 'Preparando tus banners…',
    'Não foi possível carregar sua lista. Verifique a URL/conexão.': 'No se pudo cargar tu lista. Revisa la URL/conexión.',
    'Carregando…': 'Cargando…',
    'Está demorando mais que o normal.': 'Está tardando más de lo normal.',
    'Tentar de novo': 'Intentar de nuevo', 'Continuar sem a lista': 'Continuar sin la lista',
    'Sua lista não carregou. Tente Recarregar em Configurações.': 'Tu lista no cargó. Prueba Recargar en Ajustes.',
    // Aviso
    'Período de teste': 'Período de prueba', '{n} dias grátis': '{n} días gratis',
    'Sua lista foi adicionada e o app está em teste. Para continuar depois do período, ative o app — você mesmo pode ativar escaneando o QR.': 'Tu lista fue añadida y la app está en prueba. Para continuar después del período, activa la app — puedes activarla tú mismo escaneando el QR.',
    'Ativar / gerenciar': 'Activar / gestionar', 'Continuar no teste': 'Continuar en prueba',
    // Playlists
    'Minhas Playlists': 'Mis Listas', 'Atualizar': 'Actualizar', 'Carregando playlists…': 'Cargando listas…',
    'Nenhuma playlist': 'Sin listas', 'Nenhuma playlist neste dispositivo': 'Sin listas en este dispositivo',
    'Use "Adicionar Playlist" para começar': 'Usa "Añadir Lista" para empezar', 'Recarregar títulos': 'Recargar títulos',
    'Excluir': 'Eliminar', 'Excluindo…': 'Eliminando…', 'Playlist excluída': 'Lista eliminada',
    'Recarregando títulos…': 'Recargando títulos…', 'Selecionando…': 'Seleccionando…', 'Pronto': 'Listo',
    'Atualizando…': 'Actualizando…', 'playlist': 'lista', 'playlists': 'listas',
    // Status
    'Em teste': 'En prueba', 'Ativo': 'Activo', 'Expirado': 'Expirado', 'Sem lista': 'Sin lista',
    // Config
    'Interface': 'Interfaz', 'Privacidade': 'Privacidad', 'Dados': 'Datos', 'Conta': 'Cuenta',
    'Jogos': 'Juegos', 'Clima': 'Clima', 'Info': 'Info',
    'Idioma da interface': 'Idioma de la interfaz', 'Controle dos pais': 'Control parental',
    'Limpar cache': 'Borrar caché', 'Limpar histórico': 'Borrar historial', 'Playlist ativa': 'Lista activa',
    'Minhas Informações': 'Mi Información', 'Gerenciar alertas': 'Gestionar alertas', 'Clima & Horário': 'Clima y Hora',
    'Sobre / Versão': 'Acerca de / Versión', 'Termos de uso': 'Términos de uso', 'Testar velocidade de conexão': 'Probar velocidad de conexión',
    'Idioma:': 'Idioma:',
    // Qualidade dos canais
    'Qualidade dos canais': 'Calidad de canales', 'Ajustes de reprodução dos canais ao vivo.': 'Ajustes de reproducción de los canales en vivo.',
    'Troca automática de qualidade': 'Cambio automático de calidad',
    'Se o canal ficar travando, baixa a qualidade automaticamente. Se o canal cair, troca para outra fonte.': 'Si el canal se traba, baja la calidad automáticamente. Si el canal se cae, cambia a otra fuente.',
    'Qualidade padrão': 'Calidad predeterminada', 'Qualidade com prioridade ao abrir um canal.': 'Calidad con prioridad al abrir un canal.',
    'Máxima': 'Máxima', 'Mínima': 'Mínima',
    'Troca automática ativada': 'Cambio automático activado', 'Troca automática desativada': 'Cambio automático desactivado',
    'Conexão instável — qualidade reduzida': 'Conexión inestable — calidad reducida',
    'Canal instável — trocando de fonte…': 'Canal inestable — cambiando de fuente…', 'Principal': 'Principal',
    // Parental
    'ATIVADO': 'ACTIVADO', 'DESATIVADO': 'DESACTIVADO', 'Definir PIN': 'Definir PIN', 'Alterar PIN': 'Cambiar PIN',
    'Bloqueios por categoria': 'Bloqueos por categoría', 'Canais': 'Canales',
    'Nenhuma bloqueada': 'Ninguna bloqueada', '{n} bloqueadas': '{n} bloqueadas', '{n} bloqueada': '{n} bloqueada',
    'Controle dos pais ativado': 'Control parental activado', 'Controle dos pais desativado': 'Control parental desactivado',
    '{rot} — Categorias bloqueadas': '{rot} — Categorías bloqueadas', '‹ Voltar': '‹ Volver',
    'OK para bloquear / desbloquear': 'OK para bloquear / desbloquear', 'bloqueada': 'bloqueada', 'livre': 'libre',
    'Nenhuma categoria nesta lista': 'Sin categorías en esta lista', 'Defina um PIN de 4 dígitos': 'Define un PIN de 4 dígitos',
    'O PIN deve ter 4 dígitos': 'El PIN debe tener 4 dígitos', 'PIN definido': 'PIN definido',
    'Conteúdo bloqueado — digite o PIN': 'Contenido bloqueado — ingresa el PIN', 'PIN incorreto': 'PIN incorrecto',
    // Dados
    'Limpa o cache de dados do app (início, canais, filmes, séries). O conteúdo será baixado novamente na próxima abertura.': 'Borra la caché de datos de la app (inicio, canales, películas, series). El contenido se descargará de nuevo en el próximo inicio.',
    'Limpar Cache': 'Borrar Caché', 'Limpar cache?': '¿Borrar caché?', 'O conteúdo será baixado novamente.': 'El contenido se descargará de nuevo.',
    'Cache limpo — recarregando…': 'Caché borrado — recargando…',
    'Apaga o histórico de reprodução. Todo o progresso de episódios e filmes será perdido.': 'Borra el historial de reproducción. Se perderá todo el progreso de episodios y películas.',
    'Limpar Histórico': 'Borrar Historial', 'Limpar histórico?': '¿Borrar historial?', 'Todo o progresso será perdido.': 'Se perderá todo el progreso.',
    'Histórico limpo': 'Historial borrado', 'Cancelar': 'Cancelar', 'Confirmar': 'Confirmar',
    // Conta
    'Adicione, remova ou troque sua playlist ativa na aba de Playlists.': 'Añade, quita o cambia tu lista activa en la pestaña Listas.',
    'Gerenciar Playlists': 'Gestionar Listas',
    'A licença do app (ativada pelo revendedor) e a conta da sua playlist (do provedor) são coisas diferentes — veja cada uma abaixo.': 'La licencia de la app (activada por el revendedor) y la cuenta de tu lista (del proveedor) son cosas diferentes — mira cada una abajo.',
    'Licença do app (Hero Play)': 'Licencia de la app (Hero Play)',
    'Ativação do dispositivo — feita pelo revendedor no painel (MAC + Key)': 'Activación del dispositivo — hecha por el revendedor en el panel (MAC + Key)',
    'Verificar status da Licença': 'Verificar estado de la Licencia', 'Playlist (conta do seu provedor)': 'Lista (cuenta de tu proveedor)',
    'Verificar status da playlist': 'Verificar estado de la lista', 'Carregando dados da playlist…': 'Cargando datos de la lista…',
    'Sem conta de provedor para esta playlist (lista M3U sem login Xtream).': 'Sin cuenta de proveedor para esta lista (lista M3U sin login Xtream).',
    'Não foi possível carregar os dados da playlist (servidor fora do ar ou bloqueio do navegador).': 'No se pudieron cargar los datos de la lista (servidor caído o bloqueo del navegador).',
    'Status': 'Estado', 'Conex. máximas': 'Conex. máximas', 'Conex. ativas': 'Conex. activas',
    'Conta trial': 'Cuenta de prueba', 'Sim': 'Sí', 'Não': 'No', 'Criado em': 'Creado el',
    'VENCIMENTO DA PLAYLIST': 'VENCIMIENTO DE LA LISTA', 'Verificando licença…': 'Verificando licencia…',
    'Licença atualizada': 'Licencia actualizada', 'Verificando playlist…': 'Verificando lista…',
    'Playlist atualizada': 'Lista actualizada', 'Não foi possível verificar': 'No se pudo verificar',
    // Licença
    'Licença Ativa': 'Licencia Activa', 'Vitalícia': 'De por vida', 'Restam {n} dia(s)': 'Quedan {n} día(s)',
    'Licença expirada': 'Licencia expirada', 'Renove pelo site': 'Renueva en el sitio', 'Sem licença': 'Sin licencia',
    'Adicione uma playlist': 'Añade una lista', 'Licença do App': 'Licencia de la App',
    // Alertas
    'Como funcionam os alertas:': 'Cómo funcionan las alertas:',
    'você será notificado 30 min, 15 min, 5 min e na hora da partida. Adicione alertas na aba Futebol.': 'serás notificado 30 min, 15 min, 5 min y a la hora del partido. Añade alertas en la pestaña Fútbol.',
    'Nenhum alerta salvo': 'Sin alertas guardadas', 'Adicione alertas na aba Futebol.': 'Añade alertas en la pestaña Fútbol.',
    'Testar Notificação': 'Probar Notificación', 'Notificação enviada ✔': 'Notificación enviada ✔',
    'Notificações bloqueadas neste dispositivo': 'Notificaciones bloqueadas en este dispositivo', 'Notificação de teste ✔': 'Notificación de prueba ✔',
    // Clima
    'Carregando clima…': 'Cargando clima…',
    'Ensolarado': 'Soleado', 'Predom. limpo': 'Mayorm. despejado', 'Parcial. nublado': 'Parc. nublado', 'Nublado': 'Nublado',
    'Nevoeiro': 'Niebla', 'Garoa leve': 'Llovizna ligera', 'Garoa': 'Llovizna', 'Garoa forte': 'Llovizna fuerte',
    'Chuva leve': 'Lluvia ligera', 'Chuva': 'Lluvia', 'Chuva forte': 'Lluvia fuerte', 'Neve leve': 'Nieve ligera',
    'Neve': 'Nieve', 'Neve forte': 'Nieve fuerte', 'Pancadas': 'Chubascos', 'Pancadas fortes': 'Chubascos fuertes', 'Tempestade': 'Tormenta',
    'Sensação térmica': 'Sensación térmica', 'Humidade': 'Humedad', 'Vento': 'Viento', 'Índice UV': 'Índice UV',
    'Visibilidade': 'Visibilidad', 'Pressão': 'Presión', 'Precipitação': 'Precipitación',
    'Não foi possível obter o clima.': 'No se pudo obtener el clima.', 'Tentar de novo': 'Intentar de nuevo',
    'Localização desconhecida': 'Ubicación desconocida',
    // Sobre
    'Versão do App': 'Versión de la App', 'Dispositivo': 'Dispositivo', 'Endereço MAC': 'Dirección MAC', 'Device Key': 'Clave del dispositivo',
    'Web / Navegador': 'Web / Navegador', 'Escaneie para acessar o site:': 'Escanea para acceder al sitio:',
    'Todos os direitos reservados.': 'Todos los derechos reservados.',
    // Termos
    'Leia os Termos de Uso e a Política de Privacidade do Hero Play.': 'Lee los Términos de Uso y la Política de Privacidad de Hero Play.',
    'Abrir Termos de Uso': 'Abrir Términos de Uso', 'Termos de uso e Privacidade': 'Términos de Uso y Privacidad',
    'Escaneie o código para ler os Termos de Uso e a Política de Privacidade no site.': 'Escanea el código para leer los Términos de Uso y la Política de Privacidad en el sitio.',
    'Fechar': 'Cerrar',
    // Velocidade
    'Baixa ~5 MB de um servidor de teste e mede a velocidade de download da sua conexão.': 'Descarga ~5 MB de un servidor de prueba y mide la velocidad de descarga de tu conexión.',
    'Pressione OK para medir sua conexão': 'Pulsa OK para medir tu conexión', 'Iniciar Teste de Velocidade': 'Iniciar Prueba de Velocidad',
    'Medindo sua conexão…': 'Midiendo tu conexión…', 'Conexão Boa': 'Conexión Buena', 'Conexão Média': 'Conexión Media',
    'Conexão Ruim': 'Conexión Mala', 'Falha no teste. Verifique a conexão.': 'Prueba fallida. Revisa tu conexión.',
    'Testar de novo': 'Probar de nuevo', 'Testando…': 'Probando…',
  },
};

// Idioma É por perfil (Perfis.chave); cai no global/pt antes de ter perfil.
function _chaveIdioma() { return (typeof Perfis !== 'undefined') ? Perfis.chave('tv_idioma') : 'tv_idioma'; }
function idiomaAtual() { return localStorage.getItem(_chaveIdioma()) || localStorage.getItem('tv_idioma') || 'pt'; }
// Traduz `pt` para o idioma atual (fallback = o próprio pt).
function t(pt) {
  const l = idiomaAtual();
  if (l === 'pt' || !I18N[l]) return pt;
  const v = I18N[l][pt];
  return v != null ? v : pt;
}
// Define o idioma, persiste e re-renderiza a interface (sidebar + seção atual).
function definirIdioma(l) {
  localStorage.setItem(_chaveIdioma(), l);
  try { document.documentElement.lang = l === 'pt' ? 'pt-BR' : l; } catch (_) {}
  aplicarIdioma();
}
function aplicarIdioma() {
  // Lê a seção ATUAL antes de remontar a sidebar (montarSidebar limpa a .ativo).
  const ativo = document.querySelector('.nav-item.ativo');
  const secao = ativo ? ativo.dataset.secao : 'inicio';
  if (typeof montarSidebar === 'function') montarSidebar();
  if (typeof navegar === 'function') navegar(secao);   // mantém na mesma seção
}