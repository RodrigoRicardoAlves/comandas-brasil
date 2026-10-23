import json

from django.test import TestCase

from bares.models import Bar
from comandas.models import Comanda, Evento
from contas.models import Usuario


def ev(uuid, tipo, dados, hora=1792700000000):
    return {'uuid': uuid, 'tipo': tipo, 'device_id': 'd', 'usuario': 'X', 'hora': hora, 'dados': dados}


class Base(TestCase):
    def setUp(self):
        from config import api
        api._tentativas.clear()  # o limite de tentativas é por processo
        self.a = Bar.objects.create(nome='Bar A', slug='bar-a')
        self.b = Bar.objects.create(nome='Bar B', slug='bar-b')
        for bar in (self.a, self.b):
            u = Usuario(bar=bar, nome='Garçom', papel='garcom')
            u.definir_pin('1234')  # mesmo PIN em bares diferentes é permitido
            u.save()

    def post(self, url, body, token=None):
        h = {'HTTP_AUTHORIZATION': f'Bearer {token}'} if token else {}
        return self.client.post('/api/v1' + url, json.dumps(body), content_type='application/json', **h)

    def get(self, url, token):
        return self.client.get('/api/v1' + url, HTTP_AUTHORIZATION=f'Bearer {token}')

    def login(self, slug, pin='1234', dev='cel1'):
        r = self.post('/login', {'bar': slug, 'pin': pin, 'device_id': dev})
        self.assertEqual(r.status_code, 200, r.content)
        return r.json()['token']


class LoginTest(Base):
    def test_pin_errado(self):
        r = self.post('/login', {'bar': 'bar-a', 'pin': '0000', 'device_id': 'x'})
        self.assertEqual(r.status_code, 401)

    def test_bar_inexistente(self):
        self.assertEqual(self.post('/login', {'bar': 'nada', 'pin': '1234', 'device_id': 'x'}).status_code, 404)

    def test_sem_token(self):
        self.assertEqual(self.client.get('/api/v1/bootstrap').status_code, 401)

    def test_logout_invalida_token(self):
        t = self.login('bar-a')
        self.post('/logout', {}, t)
        self.assertEqual(self.get('/bootstrap', t).status_code, 401)


class IsolamentoTest(Base):
    def test_bar_nao_ve_eventos_do_outro(self):
        ta, tb = self.login('bar-a'), self.login('bar-b', dev='cel2')
        self.post('/eventos', {'eventos': [ev('e-aaaa-1', 'comanda_aberta', {'comanda': 'ca', 'numero': 1, 'nome': 'A'})]}, ta)
        self.assertEqual(self.get('/eventos', tb).json()['eventos'], [])
        self.assertEqual(len(self.get('/eventos', ta).json()['eventos']), 1)

    def test_nao_sobrescreve_evento_de_outro_bar(self):
        ta, tb = self.login('bar-a'), self.login('bar-b', dev='cel2')
        self.post('/eventos', {'eventos': [ev('e-aaaa-1', 'comanda_aberta', {'comanda': 'ca', 'numero': 1, 'nome': 'A'})]}, ta)
        r = self.post('/eventos', {'eventos': [ev('e-aaaa-1', 'comanda_aberta', {'comanda': 'cb', 'numero': 2, 'nome': 'B'})]}, tb).json()
        self.assertEqual(r['aceitos'], [])
        self.assertFalse(Comanda.objects.filter(bar=self.b).exists())

    def test_bootstrap_so_do_proprio_bar(self):
        tb = self.login('bar-b', dev='cel2')
        d = self.get('/bootstrap', tb).json()
        self.assertEqual(d['bar']['slug'], 'bar-b')
        self.assertTrue(all(u['nome'] for u in d['usuarios']))
        self.assertEqual(len(d['usuarios']), 1)


class EventosTest(Base):
    def test_reenvio_nao_duplica_e_fora_de_ordem(self):
        t = self.login('bar-a')
        pedido = ev('ev-teste-0002', 'pedido_lancado', {'pedido': 'p1', 'comanda': 'c1', 'itens': [
            {'item': 'i1', 'produto': 'Batata', 'preco': 2200, 'qtd': 2, 'setor': 'Cozinha', 'imprime': True}]})
        abre = ev('ev-teste-0001', 'comanda_aberta', {'comanda': 'c1', 'numero': 15, 'nome': 'Teste'})
        self.post('/eventos', {'eventos': [pedido]}, t)       # chegou antes da abertura
        self.post('/eventos', {'eventos': [abre, pedido]}, t)  # e reenviado depois
        c = Comanda.objects.get(uuid='c1')
        self.assertEqual(c.itens.count(), 1)
        self.assertEqual(Evento.objects.count(), 2)
        self.post('/eventos', {'eventos': [ev('ev-teste-0003', 'comanda_fechada', {'comanda': 'c1', 'total': 4400})]}, t)
        c.refresh_from_db()
        self.assertFalse(c.aberta)
        self.assertEqual(c.total_centavos, 4400)

    def test_evento_invalido(self):
        t = self.login('bar-a')
        r = self.post('/eventos', {'eventos': [ev('ev-teste-0009', 'apagar_tudo', {})]}, t).json()
        self.assertEqual(len(r['erros']), 1)


class Etapa5Test(Base):
    """Pedido atrasado, decisão do gerente e junção de comandas em conflito."""

    def enviar(self, t, *evs):
        r = self.post('/eventos', {'eventos': list(evs)}, t)
        self.assertEqual(r.json()['erros'], [])

    def setUp(self):
        super().setUp()
        self.t = self.login('bar-a')
        it = {'item': 'i-1', 'produto': 'Coca', 'preco': 600, 'qtd': 1}
        self.enviar(self.t,
                    ev('evento5-001', 'comanda_aberta', {'comanda': 'c1', 'numero': 7, 'nome': 'Ana'}),
                    ev('evento5-002', 'pedido_lancado', {'pedido': 'p1', 'comanda': 'c1', 'itens': [it]}),
                    ev('evento5-003', 'comanda_fechada', {'comanda': 'c1', 'total': 600, 'pedidos': ['p1']}),
                    ev('evento5-004', 'comanda_aberta', {'comanda': 'c2', 'numero': 8, 'nome': 'Bia'}))
        self.atrasado = ev('evento5-005', 'pedido_lancado', {'pedido': 'p2', 'comanda': 'c1', 'itens': [
            {'item': 'i-2', 'produto': 'Batata', 'preco': 3500, 'qtd': 1}]})

    def test_pedido_atrasado_fica_pendente(self):
        from comandas.models import Pedido
        self.enviar(self.t, self.atrasado)
        self.assertEqual(Pedido.objects.get(uuid='p2').situacao, 'pendente')
        self.assertEqual(Pedido.objects.get(uuid='p1').situacao, '')

    def test_gerente_move_para_outra(self):
        from comandas.models import Item, Pedido
        self.enviar(self.t, self.atrasado, ev('evento5-006', 'pendencia_resolvida', {'pedido': 'p2', 'acao': 'mover', 'para': 'c2'}))
        p = Pedido.objects.get(uuid='p2')
        self.assertEqual((p.comanda.uuid, p.situacao), ('c2', ''))
        self.assertEqual(Item.objects.get(uuid='i-2').comanda.uuid, 'c2')

    def test_decisao_chega_antes_do_pedido(self):
        from comandas.models import Pedido
        self.enviar(self.t, ev('evento5-006', 'pendencia_resolvida', {'pedido': 'p2', 'acao': 'descartar'}), self.atrasado)
        self.assertEqual(Pedido.objects.get(uuid='p2').situacao, 'descartado')

    def test_reabrir_devolve_pedido(self):
        from comandas.models import Pedido
        self.enviar(self.t, self.atrasado, ev('evento5-006', 'comanda_reaberta', {'comanda': 'c1'}))
        self.assertEqual(Pedido.objects.get(uuid='p2').situacao, '')

    def test_juntar_comandas(self):
        from comandas.models import Pedido
        self.enviar(self.t,
                    ev('evento5-010', 'comanda_aberta', {'comanda': 'x1', 'numero': 15, 'nome': 'A'}),
                    ev('evento5-011', 'comanda_aberta', {'comanda': 'x2', 'numero': 15, 'nome': 'B'}),
                    ev('evento5-012', 'pedido_lancado', {'pedido': 'px', 'comanda': 'x2', 'itens': []}),
                    ev('evento5-013', 'comanda_juntada', {'comanda': 'x2', 'para': 'x1'}),
                    ev('evento5-014', 'pedido_lancado', {'pedido': 'py', 'comanda': 'x2', 'itens': []}))
        self.assertTrue(Comanda.objects.get(uuid='x2').descartada)
        self.assertEqual(set(Pedido.objects.filter(comanda__uuid='x1').values_list('uuid', flat=True)), {'px', 'py'})


class UmCelularPorGarcomTest(Base):
    def test_nao_entra_em_segundo_celular_ativo(self):
        from contas.models import Aparelho
        t1 = self.login('bar-a', dev='cel1')
        self.post('/presenca', {}, t1)
        r = self.post('/login', {'bar': 'bar-a', 'pin': '1234', 'device_id': 'cel2', 'modelo': 'Outro'})
        self.assertEqual(r.status_code, 409)
        self.assertIn('já está usando outro celular', r.json()['detail'])
        # o mesmo celular pode entrar de novo (ex.: reinstalou o app)
        self.login('bar-a', dev='cel1')
        # o primeiro sumiu há tempo: o segundo assume e a sessão velha cai
        from datetime import timedelta
        from django.utils import timezone
        Aparelho.objects.filter(device_id='cel1').update(ultimo_contato=timezone.now() - timedelta(minutes=5))
        t1 = Aparelho.objects.get(device_id='cel1').token
        self.login('bar-a', dev='cel2')
        self.assertEqual(self.get('/bootstrap', t1).status_code, 401)


class GerenteAppTest(Base):
    def setUp(self):
        super().setUp()
        from cardapio.models import Categoria, Produto
        g = Usuario(bar=self.a, nome='Gê', papel='gerente')
        g.definir_pin('9999')
        g.save()
        cat = Categoria.objects.create(bar=self.a, nome='Porções')
        self.p = Produto.objects.create(bar=self.a, categoria=cat, nome='Batata')
        cb = Categoria.objects.create(bar=self.b, nome='X')
        self.pb = Produto.objects.create(bar=self.b, categoria=cb, nome='Do outro bar')

    def test_garcom_nao_pode(self):
        t = self.login('bar-a')
        self.assertEqual(self.post(f'/produtos/{self.p.pk}/esgotado', {'esgotado': True}, t).status_code, 403)

    def test_gerente_marca_e_versao_sobe(self):
        t = self.login('bar-a', pin='9999', dev='g1')
        antes = Bar.objects.get(pk=self.a.pk).versao_cardapio
        r = self.post(f'/produtos/{self.p.pk}/esgotado', {'esgotado': True}, t)
        self.assertEqual(r.status_code, 200)
        self.p.refresh_from_db()
        self.assertTrue(self.p.esgotado)
        self.assertGreater(r.json()['versao_cardapio'], antes)
        # produto de outro bar: não encontra
        self.assertEqual(self.post(f'/produtos/{self.pb.pk}/esgotado', {'esgotado': True}, t).status_code, 404)

    def test_versao_do_app_sem_publicar(self):
        import tempfile
        from pathlib import Path

        from django.test import override_settings
        with override_settings(MEDIA_ROOT=Path(tempfile.mkdtemp())):
            self._sem_app()

    def _sem_app(self):
        r = self.client.get('/api/v1/app')
        self.assertEqual(r.status_code, 200)
        self.assertEqual(r.json()['build'], 0)
        self.assertEqual(self.client.get('/app/comandas.apk').status_code, 404)
        self.assertEqual(self.client.get('/privacidade/').status_code, 200)
        self.assertContains(self.client.get('/'), 'TABELA DA CASA')
