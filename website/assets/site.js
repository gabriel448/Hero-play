/* ============================================================================
   Hero Play — chrome compartilhado (header + footer + nav) + i18n (PT/EN) +
   fundo animado. Injetado em todas as páginas públicas. Mantém DRY e torna a
   ÁREA BETA (contas mobile/desktop) DESCARTÁVEL: BETA_ATIVA = false remove o
   acesso (ou apague a pasta beta/ e este bloco).
   ============================================================================ */
(function () {
  const BETA_ATIVA = true;
  const BETA_URL = 'beta/index.html';

  const NAV = [
    { href: 'index.html',     k: 'nav.inicio' },
    { href: 'ativacao.html',  k: 'nav.ativacao' },
    { href: 'upload.html',    k: 'nav.upload' },
    { href: 'gerenciar.html', k: 'nav.gerenciar' },
    { href: 'contato.html',   k: 'nav.contato' },
  ];

  // ── Dicionário de tradução ──────────────────────────────────────────────
  const I18N = {
    pt: {
      'nav.inicio': 'Início', 'nav.ativacao': 'Ativação', 'nav.upload': 'Upload de Playlist',
      'nav.gerenciar': 'Gerenciar', 'nav.contato': 'Contato',
      'cta.ativar': 'Ativar', 'beta': 'Beta · App',
      'footer.blurb': 'O Hero Play é um reprodutor de mídia: ele toca as playlists M3U/M3U8 que você já possui. Não distribuímos nem vendemos canais, filmes ou séries — a licença cobre apenas o uso do aplicativo para organizar e reproduzir as suas listas.',
      'footer.nav': 'Navegação', 'footer.contato': 'Contato', 'footer.priv': 'Privacidade',
      'footer.termos': 'Termos', 'footer.rights': '© {ano} Hero Play — Todos os direitos reservados',
      // Home
      'hero.badge': 'Smart TV · Celular · Desktop',
      'hero.h1': 'Suas playlists,<br><span class="red">do jeito que a TV merece</span>',
      'hero.sub': 'O Hero Play transforma qualquer lista M3U ou Xtream numa central de mídia fluida — com guia de canais, busca e controle remoto. Você traz a lista; a gente cuida da experiência.',
      'hero.cta1': 'Ativar agora', 'hero.cta2': 'Área do cliente',
      'hero.trust1': 'Teste grátis', 'hero.trust2': 'Configura em 2 minutos',
      'compat.funciona': 'Funciona em', 'compat.tv': 'Smart TV', 'compat.celular': 'Celular',
      'compat.desktop': 'Desktop', 'compat.compativel': 'Compatível com',
      'feat.rotulo': 'O que ele faz', 'feat.h2': 'Um player completo, sem complicação',
      'feat.descr': 'Do canal ao vivo ao filme da noite: organização automática, qualidade que se adapta e a mesma cara em toda tela.',
      'feat.1t': 'Toque play na sua lista', 'feat.1d': 'Cole uma URL M3U ou suas credenciais Xtream e o app monta tudo: ao vivo, filmes e séries já separados.',
      'feat.2t': 'Ative em segundos', 'feat.2d': 'Sem cadastro nem dados pessoais. O app mostra um MAC e uma Key — você usa no site e libera o acesso.',
      'feat.3t': 'Adicione pelo navegador', 'feat.3d': 'Envie ou troque a lista pelo celular ou computador — o aparelho sincroniza sozinho na próxima abertura.',
      'feat.4t': 'Guia de programação', 'feat.4d': 'Quando a lista traz EPG, o Hero Play monta o guia com o que passa agora e o que vem depois.',
      'feat.5t': 'Você escolhe o plano', 'feat.5d': 'Mensal, anual ou vitalício — com período de teste pra você experimentar antes de decidir.',
      'feat.6t': 'Em todas as telas', 'feat.6d': 'Samsung, LG, Android TV e mais — com uma navegação desenhada para o controle remoto.',
      'how.rotulo': 'Comece rápido', 'how.h2': 'Três passos e pronto',
      'how.1t': 'Baixe e abra', 'how.1d': 'Instale o Hero Play na loja da sua TV ou aparelho e abra — ele inicia vazio, esperando a sua lista.',
      'how.2t': 'Libere o acesso', 'how.2d': 'O MAC e a Key aparecem na tela inicial. Informe-os no site para começar o teste ou ativar.',
      'how.3t': 'Dê play', 'how.3d': 'Adicione sua lista (URL ou Xtream) e pronto: canais, filmes e séries prontos pra assistir.',
      'faq.rotulo': 'Dúvidas', 'faq.h2': 'Perguntas frequentes',
      'faq.q1': 'O Hero Play vem com algum conteúdo?', 'faq.a1': 'Não. Ele é só o reprodutor: você fornece a sua playlist (M3U ou Xtream) e o app cuida de organizar e tocar.',
      'faq.q2': 'Preciso criar uma conta?', 'faq.a2': 'No app de TV, não. A identificação é por MAC + Key do aparelho — sem e-mail nem senha.',
      'faq.q3': 'Como ativo o aplicativo?', 'faq.a3': 'Pegue o MAC e a Key na tela inicial do app, abra a Ativação, informe-os e escolha um plano.',
      'faq.q4': 'Existe teste grátis?', 'faq.a4': 'Sim. Assim que você adiciona a primeira playlist, o aparelho ganha alguns dias de teste antes de ativar.',
      'cta.rotulo': 'Bora começar', 'cta.h2': 'Da instalação ao play<br><span style="color:var(--accent-bright)">em poucos minutos</span>',
      'cta.descr': 'Instale, libere com o MAC e adicione sua lista. Simples assim — e a sua biblioteca te espera em qualquer tela.',
      'cta.b1': 'Ativar agora', 'cta.b2': 'Falar com suporte',
      // Ativação
      'ativ.rotulo': 'Ative seu dispositivo', 'ativ.h2': 'Escolha sua licença',
      'ativ.descr': 'Escolha o plano que melhor se adapta a você. Ao selecionar, você informa o dispositivo e segue para o pagamento via PIX.',
      'ativ.popular': 'Mais popular', 'ativ.p6': '6 Meses', 'ativ.p1': '1 Ano', 'ativ.pv': 'Vitalício',
      'ativ.finst': 'Ativação instantânea', 'ativ.fseg': 'Seguro e criptografado', 'ativ.fsup': 'Suporte incluso', 'ativ.fsupp': 'Suporte prioritário', 'ativ.fnr': 'Sem renovação',
      'ativ.sel': 'Selecionar', 'ativ.avt': 'Sobre a licença',
      'ativ.avp': 'Você está contratando o uso do aplicativo Hero Play para organizar e reproduzir as suas próprias playlists M3U/M3U8. O app não inclui, distribui nem vende canais, filmes ou séries.',
      'ativ.mac': 'MAC do dispositivo', 'ativ.ir': 'Ir para o pagamento', 'ativ.cancelar': 'Cancelar',
      'ativ.pix': 'Pagamento via PIX', 'ativ.soon': 'Em breve', 'ativ.fechar': 'Fechar', 'ativ.errmac': 'Informe o MAC do dispositivo.',
      // Upload
      'up.rotulo': 'Upload de Playlist', 'up.h2': 'Adicione sua lista',
      'up.descr': 'Configure a playlist do seu dispositivo Hero Play. Suporta Xtream ou URL M3U.',
      'up.mac': 'MAC do dispositivo', 'up.key': 'Key', 'up.server': 'Servidor', 'up.user': 'Usuário', 'up.pass': 'Senha', 'up.m3u': 'URL da lista (M3U)',
      'up.dvlista': 'Lista (M3U)', 'up.dvepg': 'EPG (XMLTV)', 'up.add': 'Adicionar lista', 'up.adding': 'Adicionando…',
      'up.errdev': 'Informe o MAC e a Key do dispositivo.', 'up.errx': 'Preencha servidor, usuário e senha.', 'up.errm': 'Informe uma URL M3U válida (http/https).',
      'up.rtrial': 'Período de teste', 'up.rdias': '{n} dias grátis',
      'up.rok': 'Sua lista foi adicionada com sucesso. Volte à TV e toque em <b style="color:var(--text)">Recarregar</b> para começar.',
      'up.rafter': 'Para continuar após o teste, faça a <a href="ativacao.html" style="color:var(--accent-bright)">ativação</a>.',
      'up.demo': 'Modo demonstração — backend ainda não conectado.', 'up.epgsem': '— (sem EPG para esta lista)',
      // Gerenciar
      'ger.rotulo': 'Área do cliente', 'ger.h2': 'Gerenciar dispositivo',
      'ger.descr': 'Informe o MAC e a Key do seu dispositivo para ver e gerenciar suas playlists.',
      'ger.mac': 'Endereço MAC', 'ger.key': 'Device Key', 'ger.entrar': 'Entrar',
      'ger.help': 'Não sabe onde encontrar? O MAC e a Key ficam no canto inferior esquerdo da tela inicial do app.',
      'ger.loading': 'Entrando…', 'ger.err': 'Informe o MAC e a Key.', 'ger.errdev': 'Dispositivo não encontrado ou Key incorreta.',
      'ger.nolist': 'Nenhuma playlist configurada neste dispositivo.', 'ger.trocar': 'Trocar playlist', 'ger.adicionar': 'Adicionar playlist', 'ger.ativar': 'Ativar / renovar',
      'ger.status': 'Status', 'ger.dvlista': 'Lista (M3U)', 'ger.dvepg': 'EPG', 'ger.demo': 'Modo demonstração — backend ainda não conectado.',
      'st.trial': 'Em teste', 'st.ativo': 'Ativo', 'st.expirado': 'Expirado', 'st.sem_lista': 'Sem lista', 'st.banido': 'Banido',
      // Contato
      'ct.rotulo': 'Fale conosco', 'ct.h2': 'Entre em contato', 'ct.descr': 'Dúvidas ou problemas? Nossa equipe está pronta para ajudar.',
      'ct.nome': 'Nome completo', 'ct.email': 'E-mail', 'ct.assunto': 'Assunto', 'ct.msg': 'Mensagem',
      'ct.opt1': 'Ativação / pagamento', 'ct.opt2': 'Adicionar / gerenciar playlist', 'ct.opt3': 'Problema técnico', 'ct.opt4': 'Outro',
      'ct.enviar': 'Enviar mensagem', 'ct.ok': 'Mensagem pronta para envio. Abrindo seu app de email…',
    },
    en: {
      'nav.inicio': 'Home', 'nav.ativacao': 'Activation', 'nav.upload': 'Upload Playlist',
      'nav.gerenciar': 'Manage', 'nav.contato': 'Contact',
      'cta.ativar': 'Activate', 'beta': 'Beta · App',
      'footer.blurb': 'Hero Play is a media player: it plays the M3U/M3U8 playlists you already own. We do not distribute or sell channels, movies or series — the license only covers the use of the app to organize and play your own lists.',
      'footer.nav': 'Navigation', 'footer.contato': 'Contact', 'footer.priv': 'Privacy',
      'footer.termos': 'Terms', 'footer.rights': '© {ano} Hero Play — All rights reserved',
      'hero.badge': 'Smart TV · Mobile · Desktop',
      'hero.h1': 'Your playlists,<br><span class="red">the way TV deserves</span>',
      'hero.sub': 'Hero Play turns any M3U or Xtream list into a smooth media hub — with channel guide, search and remote control. You bring the list; we handle the experience.',
      'hero.cta1': 'Activate now', 'hero.cta2': 'Customer area',
      'hero.trust1': 'Free trial', 'hero.trust2': 'Set up in 2 minutes',
      'compat.funciona': 'Works on', 'compat.tv': 'Smart TV', 'compat.celular': 'Mobile',
      'compat.desktop': 'Desktop', 'compat.compativel': 'Compatible with',
      'feat.rotulo': 'What it does', 'feat.h2': 'A complete player, no hassle',
      'feat.descr': 'From the live channel to tonight’s movie: automatic organization, adaptive quality and the same look on every screen.',
      'feat.1t': 'Hit play on your list', 'feat.1d': 'Paste an M3U URL or your Xtream credentials and the app sets everything up: live, movies and series already sorted.',
      'feat.2t': 'Activate in seconds', 'feat.2d': 'No sign-up, no personal data. The app shows a MAC and a Key — use them on the site to unlock access.',
      'feat.3t': 'Add from your browser', 'feat.3d': 'Upload or swap the list from your phone or computer — the device syncs by itself on the next launch.',
      'feat.4t': 'Program guide', 'feat.4d': 'When the list includes EPG, Hero Play builds the guide with what’s on now and what’s next.',
      'feat.5t': 'You pick the plan', 'feat.5d': 'Monthly, yearly or lifetime — with a trial period so you can try before deciding.',
      'feat.6t': 'On every screen', 'feat.6d': 'Samsung, LG, Android TV and more — with navigation designed for the remote.',
      'how.rotulo': 'Get started fast', 'how.h2': 'Three steps and done',
      'how.1t': 'Download and open', 'how.1d': 'Install Hero Play from your TV or device store and open it — it starts empty, waiting for your list.',
      'how.2t': 'Unlock access', 'how.2d': 'The MAC and Key show on the home screen. Enter them on the site to start the trial or activate.',
      'how.3t': 'Hit play', 'how.3d': 'Add your list (URL or Xtream) and you’re set: channels, movies and series ready to watch.',
      'faq.rotulo': 'FAQ', 'faq.h2': 'Frequently asked questions',
      'faq.q1': 'Does Hero Play come with any content?', 'faq.a1': 'No. It’s only the player: you provide your playlist (M3U or Xtream) and the app organizes and plays it.',
      'faq.q2': 'Do I need an account?', 'faq.a2': 'On the TV app, no. Identification is by the device’s MAC + Key — no email or password.',
      'faq.q3': 'How do I activate the app?', 'faq.a3': 'Get the MAC and Key on the app’s home screen, open Activation, enter them and choose a plan.',
      'faq.q4': 'Is there a free trial?', 'faq.a4': 'Yes. As soon as you add the first playlist, the device gets a few trial days before activating.',
      'cta.rotulo': 'Let’s go', 'cta.h2': 'From install to play<br><span style="color:var(--accent-bright)">in a few minutes</span>',
      'cta.descr': 'Install, unlock with the MAC and add your list. That simple — and your library waits for you on any screen.',
      'cta.b1': 'Activate now', 'cta.b2': 'Talk to support',
      // Activation
      'ativ.rotulo': 'Activate your device', 'ativ.h2': 'Choose your license',
      'ativ.descr': 'Choose the plan that fits you best. On selecting, you enter your device and proceed to payment via PIX.',
      'ativ.popular': 'Most popular', 'ativ.p6': '6 Months', 'ativ.p1': '1 Year', 'ativ.pv': 'Lifetime',
      'ativ.finst': 'Instant activation', 'ativ.fseg': 'Secure & encrypted', 'ativ.fsup': 'Support included', 'ativ.fsupp': 'Priority support', 'ativ.fnr': 'No renewal',
      'ativ.sel': 'Select', 'ativ.avt': 'About the license',
      'ativ.avp': 'You are purchasing the use of the Hero Play app to organize and play your own M3U/M3U8 playlists. The app does not include, distribute or sell channels, movies or series.',
      'ativ.mac': 'Device MAC', 'ativ.ir': 'Go to payment', 'ativ.cancelar': 'Cancel',
      'ativ.pix': 'Payment via PIX', 'ativ.soon': 'Coming soon', 'ativ.fechar': 'Close', 'ativ.errmac': 'Enter the device MAC.',
      // Upload
      'up.rotulo': 'Upload Playlist', 'up.h2': 'Add your list',
      'up.descr': 'Set up the playlist for your Hero Play device. Supports Xtream or M3U URL.',
      'up.mac': 'Device MAC', 'up.key': 'Key', 'up.server': 'Server', 'up.user': 'Username', 'up.pass': 'Password', 'up.m3u': 'List URL (M3U)',
      'up.dvlista': 'Playlist (M3U)', 'up.dvepg': 'EPG (XMLTV)', 'up.add': 'Add list', 'up.adding': 'Adding…',
      'up.errdev': 'Enter the device MAC and Key.', 'up.errx': 'Fill in server, username and password.', 'up.errm': 'Enter a valid M3U URL (http/https).',
      'up.rtrial': 'Trial period', 'up.rdias': '{n} free days',
      'up.rok': 'Your list was added successfully. Go back to the TV and tap <b style="color:var(--text)">Reload</b> to start.',
      'up.rafter': 'To keep using after the trial, complete <a href="ativacao.html" style="color:var(--accent-bright)">activation</a>.',
      'up.demo': 'Demo mode — backend not connected yet.', 'up.epgsem': '— (no EPG for this list)',
      // Manage
      'ger.rotulo': 'Customer area', 'ger.h2': 'Manage device',
      'ger.descr': 'Enter your device MAC and Key to view and manage your playlists.',
      'ger.mac': 'MAC address', 'ger.key': 'Device Key', 'ger.entrar': 'Sign in',
      'ger.help': 'Not sure where to find it? The MAC and Key are in the bottom-left of the app’s home screen.',
      'ger.loading': 'Signing in…', 'ger.err': 'Enter the MAC and Key.', 'ger.errdev': 'Device not found or wrong Key.',
      'ger.nolist': 'No playlist configured on this device.', 'ger.trocar': 'Change playlist', 'ger.adicionar': 'Add playlist', 'ger.ativar': 'Activate / renew',
      'ger.status': 'Status', 'ger.dvlista': 'Playlist (M3U)', 'ger.dvepg': 'EPG', 'ger.demo': 'Demo mode — backend not connected yet.',
      'st.trial': 'Trial', 'st.ativo': 'Active', 'st.expirado': 'Expired', 'st.sem_lista': 'No list', 'st.banido': 'Banned',
      // Contact
      'ct.rotulo': 'Contact us', 'ct.h2': 'Get in touch', 'ct.descr': 'Questions or issues? Our team is ready to help.',
      'ct.nome': 'Full name', 'ct.email': 'Email', 'ct.assunto': 'Subject', 'ct.msg': 'Message',
      'ct.opt1': 'Activation / payment', 'ct.opt2': 'Add / manage playlist', 'ct.opt3': 'Technical issue', 'ct.opt4': 'Other',
      'ct.enviar': 'Send message', 'ct.ok': 'Message ready to send. Opening your email app…',
    },
  };

  const getLang = () => (localStorage.getItem('hp_lang') === 'en' ? 'en' : 'pt');
  function aplicar(l) {
    const ano = new Date().getFullYear();
    const dict = I18N[l] || I18N.pt;
    const sub = (s) => (s == null ? s : String(s).replace('{ano}', ano));
    document.querySelectorAll('[data-i18n]').forEach((el) => { const v = sub(dict[el.dataset.i18n]); if (v != null) el.textContent = v; });
    document.querySelectorAll('[data-i18n-html]').forEach((el) => { const v = sub(dict[el.dataset.i18nHtml]); if (v != null) el.innerHTML = v; });
    document.querySelectorAll('[data-i18n-ph]').forEach((el) => { const v = sub(dict[el.dataset.i18nPh]); if (v != null) el.placeholder = v; });
  }
  function setLang(l) {
    localStorage.setItem('hp_lang', l);
    document.documentElement.lang = l === 'en' ? 'en' : 'pt-BR';
    document.querySelectorAll('.lang-switch button').forEach((b) => b.classList.toggle('ativo', b.dataset.l === l));
    aplicar(l);
  }
  window.HP_setLang = setLang;
  // Helper p/ textos gerados via JS nas páginas (usa o idioma atual).
  window.HP_lang = getLang;
  window.HP_t = (k) => { const l = getLang(); return (I18N[l] && I18N[l][k] != null) ? I18N[l][k] : (I18N.pt[k] != null ? I18N.pt[k] : k); };

  const arquivo = (location.pathname.split('/').pop() || 'index.html').toLowerCase();
  const ativo = (h) => (h === arquivo ? ' ativo' : '');
  const LOGO = `
    <a class="brand" href="index.html">
      <img src="assets/heroplay-icon-192.png" alt="Hero Play">
      <span class="brand-text"><b>Hero</b> Play</span>
    </a>`;
  const ICO_SETA = '<svg width="12" height="12" viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="2" stroke-linecap="round" stroke-linejoin="round"><path d="M7 7h10v10"/><path d="M7 17 17 7"/></svg>';
  const btnBeta = BETA_ATIVA
    ? `<a class="btn-beta" href="${BETA_URL}"><span class="dot"></span><span data-i18n="beta">Beta · App</span></a>` : '';

  // ── Header ──────────────────────────────────────────────────────────────
  const header = document.getElementById('site-header');
  if (header) {
    header.className = 'site-header';
    header.innerHTML = `
      <div class="header-inner">
        ${LOGO}
        <nav class="nav">
          ${NAV.map((n) => `<a href="${n.href}" class="${ativo(n.href).trim()}" data-i18n="${n.k}">${n.k}</a>`).join('')}
        </nav>
        <div class="header-acoes">
          ${btnBeta}
          <a class="btn btn-primary" href="ativacao.html" style="padding:9px 18px;font-size:12px"><span data-i18n="cta.ativar">Ativar</span> ${ICO_SETA}</a>
          <button class="menu-btn" id="menu-abrir" aria-label="Menu">
            <svg width="24" height="24" viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="2" stroke-linecap="round"><line x1="4" x2="20" y1="7" y2="7"/><line x1="4" x2="20" y1="12" y2="12"/><line x1="4" x2="20" y1="17" y2="17"/></svg>
          </button>
        </div>
      </div>`;
    const onScroll = () => header.classList.toggle('scrolled', window.scrollY > 8);
    onScroll(); window.addEventListener('scroll', onScroll, { passive: true });
  }

  // ── Menu mobile ──────────────────────────────────────────────────────────
  const menu = document.createElement('div');
  menu.className = 'menu-mob';
  menu.innerHTML = `
    <button class="fechar" id="menu-fechar" aria-label="Fechar"><svg width="28" height="28" viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="2" stroke-linecap="round"><path d="M18 6 6 18M6 6l12 12"/></svg></button>
    ${NAV.map((n) => `<a href="${n.href}" class="${ativo(n.href).trim()}" data-i18n="${n.k}">${n.k}</a>`).join('')}
    ${BETA_ATIVA ? `<a href="${BETA_URL}" data-i18n="beta">Beta · App</a>` : ''}`;
  document.body.appendChild(menu);
  const ab = document.getElementById('menu-abrir'); if (ab) ab.addEventListener('click', () => menu.classList.add('show'));
  const fe = document.getElementById('menu-fechar'); if (fe) fe.addEventListener('click', () => menu.classList.remove('show'));

  // ── Footer ────────────────────────────────────────────────────────────────
  const footer = document.getElementById('site-footer');
  if (footer) {
    footer.className = 'site-footer';
    footer.innerHTML = `
      <div class="footer-inner">
        <div>${LOGO}<p class="blurb" data-i18n="footer.blurb"></p></div>
        <div class="footer-col">
          <div class="tit" data-i18n="footer.nav">Navegação</div>
          ${NAV.map((n) => `<a href="${n.href}" data-i18n="${n.k}">${n.k}</a>`).join('')}
        </div>
        <div class="footer-col">
          <div class="tit" data-i18n="footer.contato">Contato</div>
          <a href="mailto:contato@heroplaytv.com">contato@heroplaytv.com</a>
          <a href="privacidade.html" data-i18n="footer.priv">Privacidade</a>
          <a href="termos.html" data-i18n="footer.termos">Termos</a>
        </div>
      </div>
      <div class="footer-bottom"><p data-i18n="footer.rights"></p></div>`;
  }

  // ── Fundo minimalista + marca animada da Hero Play ──────────────────────────
  const bg = document.createElement('div');
  bg.className = 'bg-min';
  bg.innerHTML = `
    <div class="grade"></div><div class="glow"></div>
    <div class="marca"><svg viewBox="0 0 100 100" fill="none" stroke="currentColor" stroke-width="2.5" stroke-linejoin="round"><path d="M34 20 L82 50 L34 80 Z"/></svg></div>`;
  document.body.insertBefore(bg, document.body.firstChild);

  // ── Seletor de idioma (canto inferior esquerdo) ────────────────────────────
  const ls = document.createElement('div');
  ls.className = 'lang-switch';
  ls.innerHTML = `<button data-l="pt">PT</button><button data-l="en">EN</button>`;
  document.body.appendChild(ls);
  ls.querySelectorAll('button').forEach((b) => b.addEventListener('click', () => setLang(b.dataset.l)));

  setLang(getLang()); // aplica idioma salvo
})();
