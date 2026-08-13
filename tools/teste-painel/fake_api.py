# -*- coding: utf-8 -*-
"""
Backend FALSO da Edge Function `painel`, para testar o painel no navegador.

Reproduz as REGRAS que implementamos (papel, plano, validade, crédito do admin
infinito) em cima de dados fictícios em memória. Nada toca o Supabase real.
"""
import json
from datetime import datetime, timedelta, timezone

AGORA = datetime.now(timezone.utc)
def iso(d): return d.isoformat()
def mais_meses(base, meses):
    # aproximação boa o bastante p/ teste de UI (o cálculo real é do Postgres)
    return base + timedelta(days=int(round(meses * 30.44)))

PLANOS = {'semestre': 6, 'ano': 12, 'vitalicia': None}


class FakeBackend:
    def __init__(self, papel='admin'):
        self.papel = papel
        self.saldo = 12                       # só vale p/ não-admin
        self.chamadas = []                    # log p/ as asserções
        self.clientes = [
            {'id': 'c1', 'nome': 'João da Silva', 'criado_em': iso(AGORA - timedelta(days=40))},
            {'id': 'c2', 'nome': 'Maria Souza', 'criado_em': iso(AGORA - timedelta(days=8))},
        ]
        self.dispositivos = [
            {'id': 'd1', 'mac': 'AA:BB:CC:DD:EE:01', 'device_key': '100001', 'modelo': 'androidtv',
             'cliente_id': 'c1', 'status': 'ativo', 'plano': 'vitalicia', 'trial_expira_em': None,
             'expira_em': None, 'ativado_por': 'reseller',
             'criado_em': iso(AGORA - timedelta(days=40)), 'atualizado_em': iso(AGORA)},
            {'id': 'd2', 'mac': 'AA:BB:CC:DD:EE:02', 'device_key': '100002', 'modelo': 'webos',
             'cliente_id': 'c1', 'status': 'ativo', 'plano': 'ano', 'trial_expira_em': None,
             'expira_em': iso(AGORA + timedelta(days=200)), 'ativado_por': 'reseller',
             'criado_em': iso(AGORA - timedelta(days=165)), 'atualizado_em': iso(AGORA)},
            # VENCIDO: status 'ativo' no banco, mas a data passou → tem que
            # aparecer como "expirado" (é a regra do statusEfetivo).
            {'id': 'd3', 'mac': 'AA:BB:CC:DD:EE:03', 'device_key': '100003', 'modelo': 'tizen',
             'cliente_id': 'c2', 'status': 'ativo', 'plano': 'ano', 'trial_expira_em': None,
             'expira_em': iso(AGORA - timedelta(days=3)), 'ativado_por': 'reseller',
             'criado_em': iso(AGORA - timedelta(days=368)), 'atualizado_em': iso(AGORA)},
            {'id': 'd4', 'mac': 'AA:BB:CC:DD:EE:04', 'device_key': '100004', 'modelo': 'android',
             'cliente_id': 'c2', 'status': 'trial', 'plano': None,
             'trial_expira_em': iso(AGORA + timedelta(days=4)), 'expira_em': None,
             'ativado_por': 'qr', 'criado_em': iso(AGORA - timedelta(days=3)), 'atualizado_em': iso(AGORA)},
            # device NOVO, ainda sem dono — é o que o teste vai ativar
            {'id': 'd9', 'mac': 'AA:BB:CC:DD:EE:99', 'device_key': '199999', 'modelo': 'androidtv',
             'cliente_id': None, 'status': 'sem_lista', 'plano': None, 'trial_expira_em': None,
             'expira_em': None, 'ativado_por': None,
             'criado_em': iso(AGORA - timedelta(hours=2)), 'atualizado_em': iso(AGORA)},
        ]
        self.playlists = [
            {'id': 'p1', 'cliente_id': 'c1', 'nome': 'Lista Principal', 'tipo': 'xtream',
             'url': 'http://servidor-ficticio.com:8080/get.php?username=u&password=p',
             'pin': None, 'free_dns': True, 'selecionada': True, 'devices': 2,
             'criado_em': iso(AGORA - timedelta(days=40)), 'atualizado_em': iso(AGORA)},
            {'id': 'p2', 'cliente_id': 'c2', 'nome': 'Lista Teste', 'tipo': 'm3u',
             'url': 'http://outro-ficticio.net/lista.m3u', 'pin': '1234', 'free_dns': False,
             'selecionada': True, 'devices': 2,
             'criado_em': iso(AGORA - timedelta(days=8)), 'atualizado_em': iso(AGORA)},
        ]
        self.revendedores = [
            {'id': 'r1', 'nome': 'Revenda Alfa', 'usuario': 'alfa', 'papel': 'reseller', 'ativo': True,
             'saldo_creditos': 30, 'criado_em': iso(AGORA - timedelta(days=90)), 'criado_por': 'admin-id',
             'indicado_por': 'Admin', 'indicado_por_codigo': 'ADMIN001'},
            {'id': 'r2', 'nome': 'Revenda Beta', 'usuario': 'beta', 'papel': 'master', 'ativo': True,
             'saldo_creditos': 120, 'criado_em': iso(AGORA - timedelta(days=30)), 'criado_por': 'admin-id',
             'indicado_por': 'Admin', 'indicado_por_codigo': 'ADMIN001'},
        ]
        self.servidores = [
            {'id': 's1', 'id_num': 141, 'codigo': 'RAZORS', 'host': 'http://servidor-ficticio.com:8080',
             'nome': 'Api', 'ativo': True, 'devices': 7, 'criado_em': iso(AGORA - timedelta(days=44))},
            {'id': 's2', 'id_num': 214, 'codigo': '6240', 'host': 'http://outro-ficticio.net',
             'nome': None, 'ativo': False, 'devices': 0, 'criado_em': iso(AGORA - timedelta(days=18))},
        ]
        self.parceiros = [
            {'id': 'pa1', 'dominio': 'servidor-ficticio.com', 'nome': 'Parceiro Fictício',
             'ativo': True, 'cobranca': 'mensal', 'valor': 2500, 'devices': 56,
             'criado_em': iso(AGORA - timedelta(days=60))},
        ]
        self.faturas = []
        self.config = {
            'modelo_mensal': True, 'modelo_por_device': False, 'preco_mensal': 2500,
            'preco_device': 2.5, 'dia_cobranca': 5, 'carencia_dias': 3,
            'carencia_extra_max': 7, 'carencia_extensoes': 2, 'programa_ativo': True,
            'banner_texto': 'Torne-se um parceiro e ative de graça.',
        }
        self.transacoes = [
            {'id': 't1', 'tipo': 'transferido_entrada', 'quantidade': 50, 'saldo_apos': 50,
             'nota': 'De Admin', 'criado_em': iso(AGORA - timedelta(days=20))},
        ]

    # ── regras que espelham o backend real ──────────────────────────────────
    @property
    def eh_admin(self): return self.papel == 'admin'

    def status_efetivo(self, d):
        if d['status'] == 'banido': return 'banido'
        if d['status'] == 'ativo':
            return 'expirado' if d['expira_em'] and datetime.fromisoformat(d['expira_em']) < AGORA else 'ativo'
        if d['status'] == 'trial':
            return 'expirado' if d['trial_expira_em'] and datetime.fromisoformat(d['trial_expira_em']) < AGORA else 'trial'
        return d['status']

    def ativar(self, dev, plano, renovar):
        vigente = dev['status'] == 'ativo' and (
            not dev['expira_em'] or datetime.fromisoformat(dev['expira_em']) > AGORA)
        cobra = (renovar or not vigente) and not self.eh_admin
        if cobra:
            if self.saldo < 1: raise ValueError('SALDO_INSUFICIENTE')
            self.saldo -= 1
            self.transacoes.insert(0, {
                'id': 'tx%d' % len(self.transacoes), 'tipo': 'consumido', 'quantidade': -1,
                'saldo_apos': self.saldo,
                'nota': ('Renovação' if renovar else 'Ativação') + ' do dispositivo %s (%s)' % (dev['mac'], plano),
                'criado_em': iso(AGORA)})
        meses = PLANOS[plano]
        if meses is None:
            nova = None
        else:
            base = datetime.fromisoformat(dev['expira_em']) if (
                dev['expira_em'] and datetime.fromisoformat(dev['expira_em']) > AGORA) else AGORA
            nova = iso(mais_meses(base, meses))
        dev.update(status='ativo', plano=plano, expira_em=nova, ativado_por='reseller')
        return {'cobrado': cobra, 'saldo': None if self.eh_admin else self.saldo, 'expira_em': nova}

    # ── roteador ────────────────────────────────────────────────────────────
    def responder(self, body):
        a = body.get('acao')
        self.chamadas.append((a, body))
        f = getattr(self, 'ac_' + a, None)
        if not f: return {'ok': False, 'erro': 'acao desconhecida no fake: ' + str(a)}
        try:
            return f(body)
        except ValueError as e:
            return {'ok': False, 'erro': str(e)}

    def ac_me(self, b):
        return {'id': 'admin-id', 'nome': 'Admin' if self.eh_admin else 'Revenda Alfa',
                'usuario': 'admin' if self.eh_admin else 'alfa', 'papel': self.papel,
                'saldo_creditos': None if self.eh_admin else self.saldo,
                'codigo_indicacao': 'ADMIN001'}

    def ac_listar_clientes(self, b): return {'clientes': self.clientes}
    def ac_listar_revendedores(self, b): return {'revendedores': self.revendedores, 'admin': self.eh_admin}
    def ac_listar_notificacoes(self, b): return {'notificacoes': [], 'nao_lidas': 0}
    def ac_listar_tickets(self, b): return {'tickets': [], 'admin': self.eh_admin}
    def ac_listar_creditos(self, b):
        return {'saldo': None if self.eh_admin else self.saldo, 'transacoes': self.transacoes}

    def ac_listar_dispositivos(self, b):
        nomes = {c['id']: c['nome'] for c in self.clientes}
        return {'dispositivos': [dict(d, cliente=nomes.get(d['cliente_id'], ''),
                                      status=self.status_efetivo(d)) for d in self.dispositivos]}

    def ac_listar_playlists(self, b):
        nomes = {c['id']: c['nome'] for c in self.clientes}
        return {'playlists': [dict(p, cliente=nomes.get(p['cliente_id'], '')) for p in self.playlists]}

    def ac_cliente_detalhe(self, b):
        cid = b['cliente_id']
        cli = next(c for c in self.clientes if c['id'] == cid)
        disp = [dict(d, status=self.status_efetivo(d)) for d in self.dispositivos if d['cliente_id'] == cid]
        pls = [p for p in self.playlists if p['cliente_id'] == cid]
        return {'cliente': cli, 'dispositivos': disp, 'playlists': pls,
                'vinculos': [{'dispositivo_id': d['id'], 'playlist_id': pls[0]['id'], 'selecionada': True}
                             for d in disp] if pls else []}

    def ac_vincular_dispositivo(self, b):
        if b.get('plano') not in PLANOS: raise ValueError('escolha o plano da ativação')
        dev = next((d for d in self.dispositivos if d['mac'] == b['mac']), None)
        if not dev or dev['device_key'] != b['key']:
            raise ValueError('dispositivo nao encontrado (confira MAC e Key)')
        dev['cliente_id'] = b['cliente_id']
        r = self.ativar(dev, b['plano'], False)
        return dict(ok=True, dispositivo={'id': dev['id'], 'mac': dev['mac']}, plano=b['plano'], **r)

    def ac_renovar_dispositivo(self, b):
        if b.get('plano') not in PLANOS: raise ValueError('escolha o plano da renovação')
        dev = next(d for d in self.dispositivos if d['id'] == b['dispositivo_id'])
        r = self.ativar(dev, b['plano'], True)
        return dict(ok=True, plano=b['plano'], **r)

    def ac_transferir_creditos(self, b):
        q = int(b['quantidade'])
        if not self.eh_admin:
            if q > self.saldo: raise ValueError('saldo insuficiente')
            self.saldo -= q
        alvo = next(r for r in self.revendedores if r['id'] == b['revendedor_id'])
        alvo['saldo_creditos'] += q
        return {'ok': True, 'saldo': None if self.eh_admin else self.saldo}

    # ── admin-only ──────────────────────────────────────────────────────────
    def _so_admin(self):
        if not self.eh_admin: raise ValueError('apenas admin')

    def ac_listar_servidores(self, b): self._so_admin(); return {'servidores': self.servidores}
    def ac_salvar_servidor(self, b):
        self._so_admin()
        cod = (b.get('codigo') or '').strip().upper() or '4242'
        # mesma normalizacao do backend real: host sem esquema ganha http://
        if b.get('host') and '://' not in b['host']: b['host'] = 'http://' + b['host']
        if b.get('id'):
            s = next(x for x in self.servidores if x['id'] == b['id'])
            s.update(host=b['host'], codigo=cod, nome=b.get('nome') or None)
            return {'ok': True, 'id': s['id'], 'codigo': cod}
        novo = {'id': 's%d' % (len(self.servidores) + 1), 'id_num': 300 + len(self.servidores),
                'codigo': cod, 'host': b['host'], 'nome': b.get('nome') or None,
                'ativo': True, 'devices': 0, 'criado_em': iso(AGORA)}
        self.servidores.append(novo)
        return {'ok': True, 'id': novo['id'], 'codigo': cod}
    def ac_servidor_codigo(self, b):
        self._so_admin()
        s = next(x for x in self.servidores if x['id'] == b['id']); s['codigo'] = '7777'
        return {'ok': True, 'codigo': '7777'}
    def ac_servidor_ativo(self, b):
        self._so_admin()
        next(x for x in self.servidores if x['id'] == b['id'])['ativo'] = bool(b['ativo'])
        return {'ok': True}
    def ac_excluir_servidor(self, b):
        self._so_admin()
        self.servidores = [x for x in self.servidores if x['id'] != b['id']]
        return {'ok': True}

    def ac_listar_parceiros(self, b): self._so_admin(); return {'parceiros': self.parceiros}
    def ac_parceiros_config(self, b): self._so_admin(); return {'config': self.config}
    def ac_salvar_parceiros_config(self, b):
        self._so_admin(); self.config.update(b['config']); return {'ok': True}
    def ac_listar_faturas(self, b):
        self._so_admin()
        doms = {p['id']: p['dominio'] for p in self.parceiros}
        return {'faturas': [dict(f, dominio=doms.get(f['parceiro_id'], '—')) for f in self.faturas]}
    def ac_gerar_faturas(self, b):
        self._so_admin()
        criadas = 0
        for p in self.parceiros:
            if p['cobranca'] == 'gratuito' or not p['ativo']: continue
            per = iso((AGORA - timedelta(days=30)).date())
            if any(f['parceiro_id'] == p['id'] and f['periodo_ini'] == per for f in self.faturas):
                continue          # idempotente, igual ao índice único do banco
            self.faturas.append({
                'id': 'f%d' % (len(self.faturas) + 1), 'parceiro_id': p['id'], 'tipo': p['cobranca'],
                'periodo_ini': per, 'periodo_fim': iso(AGORA.date()), 'devices': p['devices'],
                'valor': p['valor'], 'status': 'aguardando', 'vencimento': iso(AGORA.date()),
                'carencia_ate': None, 'extensoes': 0})
            criadas += 1
        return {'ok': True, 'criadas': criadas}
    def ac_fatura_acao(self, b):
        self._so_admin()
        f = next(x for x in self.faturas if x['id'] == b['id'])
        if b['oque'] == 'pago': f['status'] = 'pago'
        elif b['oque'] == 'cancelar': f['status'] = 'cancelado'
        else:
            if f['extensoes'] >= self.config['carencia_extensoes']:
                raise ValueError('limite de %d extensão(ões) atingido para esta fatura'
                                 % self.config['carencia_extensoes'])
            f['extensoes'] += 1
            f['carencia_ate'] = iso((AGORA + timedelta(days=self.config['carencia_dias'] * f['extensoes'])).date())
        return {'ok': True, 'dias': self.config['carencia_dias'], 'carencia_ate': f['carencia_ate']}
