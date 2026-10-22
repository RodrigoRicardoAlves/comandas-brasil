import json

from django.test import TestCase

from bares.models import Bar
from comandas.models import Comanda, Evento
from contas.models import Usuario


def ev(uuid, tipo, dados, hora=1792700000000):
    return {'uuid': uuid, 'tipo': tipo, 'device_id': 'd', 'usuario': 'X', 'hora': hora, 'dados': dados}


class Base(TestCase):
    def setUp(self):
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
