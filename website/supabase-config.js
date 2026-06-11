// Configuracao publica do Supabase usada pelas paginas login.html e painel.html.
//
// Preencha com os dados do SEU projeto (Dashboard > Project Settings > API).
// A anon key e PUBLICA por design — pode ficar aqui e no Git. O que protege os
// dados e o RLS no banco (ver supabase/schema.sql), nao o segredo da chave.
// NUNCA coloque aqui a chave `service_role`.

window.SUPABASE_URL = 'https://mlafyphpntjssmxagyhc.supabase.co';
window.SUPABASE_ANON_KEY = 'sb_publishable_MlxtdbBT4UJWhBVJ5Krtww_AvZHXa3I';

// Cria o cliente Supabase com "Lembrar deste dispositivo":
//  - lembrar (padrao): sessao no localStorage  -> continua logado apos fechar o navegador.
//  - nao lembrar:       sessao no sessionStorage -> some ao fechar o navegador.
// A pagina de login grava a preferencia em localStorage['hp_lembrar'] ('1'/'0')
// ANTES de autenticar; o adapter abaixo decide onde gravar a sessao. Todas as
// paginas usam este mesmo cliente, entao leem a sessao de onde quer que esteja.
window.criarClienteSupabase = function () {
  const PREF = 'hp_lembrar';
  const armazenamento = {
    getItem(k) {
      try { return localStorage.getItem(k) ?? sessionStorage.getItem(k); }
      catch (_) { return null; }
    },
    setItem(k, v) {
      const lembrar = localStorage.getItem(PREF) !== '0'; // padrao = lembrar
      try {
        (lembrar ? localStorage : sessionStorage).setItem(k, v);
        (lembrar ? sessionStorage : localStorage).removeItem(k); // evita sessao duplicada/obsoleta
      } catch (_) {}
    },
    removeItem(k) {
      try { localStorage.removeItem(k); sessionStorage.removeItem(k); } catch (_) {}
    },
  };
  return supabase.createClient(window.SUPABASE_URL, window.SUPABASE_ANON_KEY, {
    auth: {
      persistSession: true,
      autoRefreshToken: true,
      detectSessionInUrl: true,
      storage: armazenamento,
    },
  });
};
