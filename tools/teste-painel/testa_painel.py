# -*- coding: utf-8 -*-
"""
Testa o PAINEL no navegador de verdade (Chromium via Playwright).

- Serve `painel/` num http local.
- Intercepta o Supabase: login falso + Edge Function `painel` respondida pelo
  FakeBackend (dados fictícios, mesmas regras do backend real).
- Roda como ADMIN e como REVENDEDOR e confere o que cada um vê.

Uso:  python testa_painel.py [--headed]
"""
import base64, json, os, subprocess, sys, threading, time, http.server, functools, socket
sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
from fake_api import FakeBackend
from playwright.sync_api import sync_playwright

# Caminhos relativos ao repo: o teste roda de qualquer máquina/pasta.
RAIZ = os.path.join(os.path.dirname(os.path.dirname(os.path.dirname(os.path.abspath(__file__)))), 'painel')
SHOTS = os.path.join(os.path.dirname(os.path.abspath(__file__)), 'shots')
os.makedirs(SHOTS, exist_ok=True)
falhas, passou = [], []


def ok(cond, msg):
    (passou if cond else falhas).append(msg)
    print(('  ok  ' if cond else '  XX  ') + msg)


def porta_livre():
    s = socket.socket(); s.bind(('127.0.0.1', 0)); p = s.getsockname()[1]; s.close(); return p


def servir(porta):
    h = functools.partial(http.server.SimpleHTTPRequestHandler, directory=RAIZ)
    srv = http.server.ThreadingHTTPServer(('127.0.0.1', porta), h)
    srv.log_message = lambda *a, **k: None
    threading.Thread(target=srv.serve_forever, daemon=True).start()
    return srv


def jwt_falso():
    """JWT sintaticamente válido (o supabase-js decodifica p/ achar o exp)."""
    b64 = lambda o: base64.urlsafe_b64encode(json.dumps(o).encode()).decode().rstrip('=')
    return b64({'alg': 'HS256', 'typ': 'JWT'}) + '.' + b64({
        'sub': 'admin-id', 'role': 'authenticated', 'exp': int(time.time()) + 3600}) + '.assinatura'


def preparar(page, be):
    """Intercepta tudo que sai para o Supabase."""
    def auth(route):
        u = jwt_falso()
        route.fulfill(status=200, content_type='application/json', body=json.dumps({
            'access_token': u, 'token_type': 'bearer', 'expires_in': 3600,
            'expires_at': int(time.time()) + 3600, 'refresh_token': 'refresh-falso',
            'user': {'id': 'admin-id', 'aud': 'authenticated', 'role': 'authenticated',
                     'email': 'admin@u.heroplaytv.com', 'app_metadata': {}, 'user_metadata': {},
                     'created_at': '2026-01-01T00:00:00Z'}}))

    def fn(route):
        body = json.loads(route.request.post_data or '{}')
        route.fulfill(status=200, content_type='application/json',
                      body=json.dumps(be.responder(body), default=str))

    page.route('**/auth/v1/**', auth)
    page.route('**/functions/v1/painel', fn)


def entrar(page, base, be):
    preparar(page, be)
    erros = []
    page.on('console', lambda m: erros.append(m.text) if m.type == 'error' else None)
    page.on('pageerror', lambda e: erros.append('pageerror: ' + str(e)))
    page.goto(base + '/index.html')
    page.wait_for_load_state('networkidle')
    page.fill('#usuario', 'admin' if be.eh_admin else 'alfa')
    page.fill('#senha', 'senha-ficticia')
    page.click('#entrar')
    page.wait_for_selector('.side-nav', timeout=15000)
    page.wait_for_timeout(600)
    return erros


def ir(page, view):
    page.click(f'.nav-item[data-view="{view}"]')
    page.wait_for_timeout(700)


# ══════════════════════════════════════════════════════════════════════════════
def testar_admin(page, base):
    be = FakeBackend('admin')
    erros = entrar(page, base, be)
    print('\n── ADMIN ──────────────────────────────────────────────────────')

    # 1. Seções do menu no formato do GTV
    grupos = [t.strip() for t in page.locator('.nav-grp-label').all_text_contents()]
    ok(grupos == ['Conteúdo', 'Usuários', 'Sistema'],
       f'seções do admin = Conteúdo/Usuários/Sistema (veio {grupos})')
    itens = page.locator('.nav-item').all_text_contents()
    ok(any('Servidores' in i for i in itens), 'admin vê "Servidores"')
    ok(not any('Comprar' in i for i in itens), 'admin NÃO vê "Comprar Créditos"')

    # 2. Crédito não aparece em lugar nenhum
    ok(page.locator('.user-cr').count() == 0, 'sidebar do admin sem contador de crédito')
    ok(page.locator('.mtop-cr').count() == 0, 'topo mobile do admin sem contador de crédito')
    ir(page, 'dashboard')
    stats = page.locator('#dash-stats').inner_text()
    ok('Créditos' not in stats, f'dashboard do admin sem card "Créditos"')
    ir(page, 'creditos')
    ok(page.locator('.cr-inf').count() == 1 and page.locator('.cr-inf').inner_text() == '∞',
       'tela Créditos mostra ∞ para o admin')
    ok('ilimitado' in page.locator('.pg').inner_text(), 'texto de crédito ilimitado presente')
    page.screenshot(path=f'{SHOTS}/admin-creditos.png', full_page=True)

    # 3. Servidores: listar, criar, novo código, desativar, buscar
    ir(page, 'servidores')
    ok(page.locator('.sv-card').count() == 2, 'Servidores lista os 2 fictícios')
    ok('RAZORS' in page.locator('.sv-cod-val').first.inner_text(), 'código aparece em destaque')
    ok(page.locator('.sv-card.off').count() == 1, 'servidor inativo fica esmaecido')
    page.screenshot(path=f'{SHOTS}/admin-servidores.png', full_page=True)
    page.fill('#sv-busca', 'razors'); page.wait_for_timeout(400)
    ok(page.locator('.sv-card').count() == 1, 'busca de servidor filtra (case-insensitive)')
    ok(page.locator('#sv-cont').inner_text() == '1/2', 'contador da busca = 1/2')
    page.fill('#sv-busca', ''); page.wait_for_timeout(400)
    page.click('#sv-novo'); page.wait_for_selector('.modal')
    page.fill('#f-host', 'meuservidor-teste.com')
    page.fill('#f-nome', 'Teste')
    page.fill('#f-codigo', '9090')
    page.click('#m-ok'); page.wait_for_timeout(800)
    ok(page.locator('.sv-card').count() == 3, 'servidor novo entra na lista')
    ok('9090' in page.locator('#sv-lista').inner_text(), 'código digitado foi usado')
    ok('http://meuservidor-teste.com' in page.locator('#sv-lista').inner_text(),
       'host sem esquema recebeu http:// (normalização do backend)')
    page.once('dialog', lambda d: d.accept())
    page.locator('[data-a="alternar"]').first.click(); page.wait_for_timeout(700)
    ok(page.locator('.sv-card.off').count() == 2, 'desativar marca o cartão como inativo')

    # 4. Parceiros: 3 abas + faturas idempotentes + limite de carência
    ir(page, 'parceiros')
    abas = page.locator('#pc-tabs .tab').all_text_contents()
    ok(abas == ['Parceiros', 'Faturas', 'Configurações'], f'3 abas em Parceiros (veio {abas})')
    page.click('.tab[data-t="faturas"]'); page.wait_for_timeout(700)
    ok('Nenhuma fatura' in page.locator('#pc-aba-faturas').inner_text(), 'faturas começam vazias')
    page.once('dialog', lambda d: d.accept())
    page.click('#ft-cobrar'); page.wait_for_timeout(900)
    ok(page.locator('#ft-tbl tbody tr').count() == 1, 'Executar cobrança gera 1 fatura')
    page.once('dialog', lambda d: d.accept())
    page.click('#ft-cobrar'); page.wait_for_timeout(900)
    ok(page.locator('#ft-tbl tbody tr').count() == 1,
       'rodar a cobrança DE NOVO não duplica (idempotente)')
    page.screenshot(path=f'{SHOTS}/admin-faturas.png', full_page=True)
    for i in range(2):                                  # limite = 2 extensões
        page.locator('.ft-car').first.click(); page.wait_for_timeout(600)
    ok('2x' in page.locator('#ft-tbl').inner_text(), 'carência registra as 2 extensões')
    page.locator('.ft-car').first.click(); page.wait_for_timeout(600)
    ok('limite' in page.locator('#toast').inner_text().lower(),
       '3ª carência é barrada pelo limite configurado')
    page.click('.tab[data-t="config"]'); page.wait_for_timeout(700)
    ok(page.locator('#cf-preco_mensal').input_value() == '2500', 'config carrega o preço mensal')
    page.click('#tg-device'); page.click('#cf-salvar'); page.wait_for_timeout(700)
    ok(be.config['modelo_por_device'] is True, 'toggle salvo chega no backend')
    page.screenshot(path=f'{SHOTS}/admin-config-parceiros.png', full_page=True)

    # 5. Dispositivos: plano, status efetivo, ativar sem custo
    ir(page, 'dispositivos')
    cab = page.locator('#dv-tbl thead th').all_text_contents()
    ok('Plano' in cab, f'tabela de dispositivos tem coluna Plano (veio {cab})')
    txt = page.locator('#dv-tbl').inner_text()
    ok('Vitalícia' in txt and '1 ano' in txt, 'planos aparecem por extenso')
    # ⚠️ inner_text() aplica o text-transform do CSS → comparar em minúsculas.
    linha3 = page.locator('#dv-tbl tbody tr').nth(2).inner_text().lower()
    ok('expirado' in linha3, f'device com data vencida aparece como EXPIRADO (veio {linha3[:60]!r})')
    linha1 = page.locator('#dv-tbl tbody tr').nth(1).inner_text().lower()
    ok('ativo' in linha1 and 'expirado' not in linha1, 'device de 1 ano ainda vigente continua ativo')
    ok('nunca' in txt, 'vitalícia mostra "nunca" na coluna Expira')
    page.screenshot(path=f'{SHOTS}/admin-dispositivos.png', full_page=True)

    page.click('#dv-vinc'); page.wait_for_selector('.modal')
    aviso = page.locator('.modal-aviso').inner_text()
    ok('crédito' not in aviso.lower(), f'admin não vê aviso de custo ao ativar (veio: {aviso[:60]}…)')
    ok(page.locator('#m-ok').inner_text().strip() == 'Ativar',
       'botão do admin é "Ativar", sem "(1 crédito)"')
    ok(page.locator('#f-plano .opc-item').count() == 2, 'modal oferece 2 planos')
    rotulos = page.locator('#f-plano .opc-item b').all_text_contents()
    ok(rotulos == ['1 ano', 'Vitalícia'], f'planos = 1 ano e Vitalícia (veio {rotulos})')
    ok(page.locator('#f-plano').get_attribute('data-v') == 'ano', 'plano padrão é 1 ano')
    page.fill('#f-mac', 'AABBCCDDEE99')
    page.fill('#f-key', '199999')
    page.click('#m-ok'); page.wait_for_timeout(1000)
    d9 = next(d for d in be.dispositivos if d['id'] == 'd9')
    ok(d9['plano'] == 'ano' and d9['expira_em'], 'device ativado com plano de 1 ano e data')
    ok(be.saldo == 12, 'ADMIN ativou sem consumir crédito')
    envio = next(b for a, b in reversed(be.chamadas) if a == 'vincular_dispositivo')
    ok(envio.get('plano') == 'ano', f"o plano foi enviado ao backend (veio {envio.get('plano')!r})")
    return erros


def testar_reseller(page, base):
    be = FakeBackend('reseller')
    erros = entrar(page, base, be)
    print('\n── REVENDEDOR ─────────────────────────────────────────────────')

    grupos = [t.strip() for t in page.locator('.nav-grp-label').all_text_contents()]
    ok(grupos == ['Conteúdo', 'Negócios'], f'seções do revendedor = Conteúdo/Negócios (veio {grupos})')
    itens = page.locator('.nav-item').all_text_contents()
    ok(not any('Servidores' in i for i in itens), 'revendedor NÃO vê Servidores')
    ok(not any('Parceiros' in i for i in itens), 'revendedor NÃO vê Parceiros (tela de admin)')
    ok(any('Comprar' in i for i in itens), 'revendedor vê Comprar Créditos')
    ok(page.locator('.user-cr').inner_text().startswith('12'), 'saldo aparece na sidebar')
    ir(page, 'dashboard')
    dash = page.locator('#dash-stats').inner_text().lower()
    ok('créditos' in dash and '12' in dash, f'dashboard mostra card de Créditos com o saldo (veio {dash[:40]!r})')
    page.screenshot(path=f'{SHOTS}/reseller-dashboard.png', full_page=True)

    ir(page, 'dispositivos')
    page.click('#dv-vinc'); page.wait_for_selector('.modal')
    aviso = page.locator('.modal-aviso').inner_text()
    ok('consome 1 crédito' in aviso, 'revendedor VÊ o aviso de custo')
    ok('12' in aviso, 'aviso mostra o saldo dele')
    ok(page.locator('#m-ok').inner_text().strip() == 'Ativar (1 crédito)', 'botão com o custo')
    page.screenshot(path=f'{SHOTS}/reseller-ativar.png', full_page=True)
    page.select_option('#f-cliente_id', label='João da Silva')
    page.fill('#f-mac', 'AABBCCDDEE99'); page.fill('#f-key', '199999')
    page.locator('#f-plano .opc-item[data-v="vitalicia"]').click()
    page.click('#m-ok'); page.wait_for_timeout(1000)
    d9 = next(d for d in be.dispositivos if d['id'] == 'd9')
    ok(d9['plano'] == 'vitalicia' and d9['expira_em'] is None, 'vitalícia grava sem data')
    ok(be.saldo == 11, f'revendedor consumiu 1 crédito (saldo {be.saldo})')
    ok(page.locator('.user-cr').inner_text().startswith('11'), 'saldo da sidebar caiu na hora')

    # Renovar, pelo modal do device dentro do cliente
    ir(page, 'clientes')
    page.locator('#cli-lista .row').first.click()
    page.wait_for_selector('.dev', timeout=10000); page.wait_for_timeout(500)
    # d2 = plano de 1 ano com ~200 dias restantes → renovar tem que SOMAR.
    antes = next(d for d in be.dispositivos if d['id'] == 'd2')['expira_em']
    page.locator('.dev[data-id="d2"]').click()
    page.wait_for_selector('.modal-dev')
    info = page.locator('.mdev-info').inner_text().lower()
    ok('plano' in info and '1 ano' in info, f'modal do device mostra o plano (veio {info[:80]!r})')
    page.screenshot(path=f'{SHOTS}/reseller-device.png')
    ok(page.locator('#mdev-renovar').count() == 1, 'modal do device tem "Renovar assinatura"')
    page.click('#mdev-renovar'); page.wait_for_selector('#f-plano')
    page.click('#m-ok'); page.wait_for_timeout(1200)
    ok(be.saldo == 10, f'renovar consumiu mais 1 crédito (saldo {be.saldo})')
    ok(any(a == 'renovar_dispositivo' for a, _ in be.chamadas), 'chamou renovar_dispositivo')
    depois = next(d for d in be.dispositivos if d['id'] == 'd2')['expira_em']
    ok(depois > antes, f'renovar SOMOU ao prazo que restava ({antes[:10]} → {depois[:10]})')
    return erros


def main():
    porta = porta_livre()
    servir(porta)
    base = f'http://127.0.0.1:{porta}'
    headed = '--headed' in sys.argv
    with sync_playwright() as p:
        b = p.chromium.launch(headless=not headed)
        ctx = b.new_context(viewport={'width': 1500, 'height': 950})
        page = ctx.new_page()
        e1 = testar_admin(page, base)
        ctx2 = b.new_context(viewport={'width': 1500, 'height': 950})
        page2 = ctx2.new_page()
        e2 = testar_reseller(page2, base)
        b.close()

    reais = [x for x in (e1 + e2) if 'favicon' not in x.lower() and 'esm.sh' not in x]
    print('\n── CONSOLE ────────────────────────────────────────────────────')
    print('  sem erros de JS' if not reais else '\n'.join('  ! ' + x for x in reais[:12]))
    print(f'\n{len(passou)} passaram · {len(falhas)} falharam')
    for f in falhas: print('  FALHOU: ' + f)
    sys.exit(1 if (falhas or reais) else 0)


if __name__ == '__main__':
    main()
