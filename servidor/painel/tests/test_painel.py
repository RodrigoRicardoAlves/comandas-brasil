from datetime import timedelta

from django.test import TestCase
from django.utils import timezone

from bares.models import Bar
from cardapio.models import Categoria, Produto, Setor, Variante
from comandas.models import Comanda, Item, Pedido
from contas.models import Aparelho, Usuario
from publico.models import Chamado


class Base(TestCase):
    def setUp(self):
        self.a = Bar.objects.create(nome='Bar A', slug='bar-a', max_comanda=100)
        self.b = Bar.objects.create(nome='Bar B', slug='bar-b')
        for bar in (self.a, self.b):
            for nome, papel, pin in (('Gê', 'gerente', '9999'), ('Gar', 'garcom', '1234')):
                u = Usuario(bar=bar, nome=nome, papel=papel)
                u.definir_pin(pin)
                u.save()
        self.cat_b = Categoria.objects.create(bar=self.b, nome='Cervejas B')
        self.prod_b = Produto.objects.create(bar=self.b, categoria=self.cat_b, nome='Skol B')

    def entrar(self, slug='bar-a', pin='9999'):
        return self.client.post('/painel/entrar/', {'bar': slug, 'pin': pin})


class AcessoTest(Base):
    def test_sem_login_vai_para_entrar(self):
        r = self.client.get('/painel/')
        self.assertEqual(r.status_code, 302)
        self.assertIn('/painel/entrar/', r['Location'])

    def test_garcom_nao_entra(self):
        r = self.entrar(pin='1234')
        self.assertEqual(r.status_code, 200)
        self.assertContains(r, 'incorreto')

    def test_gerente_entra(self):
        self.assertEqual(self.entrar().status_code, 302)
        self.assertContains(self.client.get('/painel/'), 'Agora no bar')

    def test_nao_ve_produto_de_outro_bar(self):
        self.entrar()
        self.assertEqual(self.client.get(f'/painel/cardapio/produto/{self.prod_b.pk}/').status_code, 404)
        self.assertEqual(self.client.post(f'/painel/cardapio/produto/{self.prod_b.pk}/esgotado/').status_code, 404)
        self.assertNotContains(self.client.get('/painel/cardapio/'), 'Skol B')


class CardapioTest(Base):
    def test_criar_produto_com_precos(self):
        self.entrar()
        cat = Categoria.objects.create(bar=self.a, nome='Porções')
        setor = Setor.objects.create(bar=self.a, nome='Cozinha')
        versao = Bar.objects.get(pk=self.a.pk).versao_cardapio
        r = self.client.post('/painel/cardapio/produto/novo/', {
            'categoria': cat.pk, 'nome': 'Batata', 'descricao': '', 'ordem': 0, 'ativo': 'on', 'imprime': 'on', 'setor': setor.pk,
            'v-TOTAL_FORMS': 2, 'v-INITIAL_FORMS': 0, 'v-MIN_NUM_FORMS': 0, 'v-MAX_NUM_FORMS': 1000,
            'v-0-nome': 'Inteira', 'v-0-preco': '35,50', 'v-0-ordem': '', 'v-1-nome': 'Meia', 'v-1-preco': '22', 'v-1-ordem': '1',
        })
        self.assertEqual(r.status_code, 302, r.content.decode()[:2000])
        p = Produto.objects.get(bar=self.a, nome='Batata')
        self.assertEqual(sorted(p.variantes.values_list('preco_centavos', flat=True)), [2200, 3550])
        self.assertGreater(Bar.objects.get(pk=self.a.pk).versao_cardapio, versao)  # celulares baixam de novo

    def test_imprime_sem_setor_da_erro(self):
        self.entrar()
        cat = Categoria.objects.create(bar=self.a, nome='Porções')
        r = self.client.post('/painel/cardapio/produto/novo/', {
            'categoria': cat.pk, 'nome': 'Batata', 'ordem': 0, 'ativo': 'on', 'imprime': 'on',
            'v-TOTAL_FORMS': 1, 'v-INITIAL_FORMS': 0, 'v-MIN_NUM_FORMS': 0, 'v-MAX_NUM_FORMS': 1000, 'v-0-preco': '10'})
        self.assertEqual(r.status_code, 200)
        self.assertFalse(Produto.objects.filter(nome='Batata').exists())

    def test_nao_aceita_setor_de_outro_bar(self):
        self.entrar()
        cat = Categoria.objects.create(bar=self.a, nome='Porções')
        setor_b = Setor.objects.create(bar=self.b, nome='Cozinha B')
        r = self.client.post('/painel/cardapio/produto/novo/', {
            'categoria': cat.pk, 'nome': 'X', 'ordem': 0, 'ativo': 'on', 'imprime': 'on', 'setor': setor_b.pk,
            'v-TOTAL_FORMS': 1, 'v-INITIAL_FORMS': 0, 'v-MIN_NUM_FORMS': 0, 'v-MAX_NUM_FORMS': 1000, 'v-0-preco': '10'})
        self.assertEqual(r.status_code, 200)
        self.assertFalse(Produto.objects.filter(nome='X').exists())


class EquipeTest(Base):
    def test_pin_repetido(self):
        self.entrar()
        r = self.client.post('/painel/equipe/novo/', {'nome': 'Novo', 'papel': 'garcom', 'ativo': 'on', 'pin': '1234'})
        self.assertContains(r, 'já é de outra pessoa')
        r = self.client.post('/painel/equipe/novo/', {'nome': 'Novo', 'papel': 'garcom', 'ativo': 'on', 'pin': '4321'})
        self.assertEqual(r.status_code, 302)

    def test_nao_tira_proprio_acesso(self):
        self.entrar()
        eu = Usuario.objects.get(bar=self.a, nome='Gê')
        r = self.client.post(f'/painel/equipe/{eu.pk}/', {'nome': 'Gê', 'papel': 'garcom', 'ativo': 'on'})
        self.assertContains(r, 'próprio acesso')


class RelatorioTest(Base):
    def test_soma_do_dia(self):
        self.entrar()
        agora = timezone.now()
        c = Comanda.objects.create(bar=self.a, uuid='c1', numero=1, nome='X', aberta_em=agora, aberta_por='Gar',
                                   fechada_em=agora, fechada_por='Gar', total_centavos=1100)
        p = Pedido.objects.create(bar=self.a, uuid='p1', comanda=c, feito_em=agora, garcom='Gar')
        Item.objects.create(bar=self.a, uuid='i1', pedido=p, comanda=c, categoria='Cervejas', produto='Skol',
                            preco_centavos=1000, qtd=1)
        Item.objects.create(bar=self.a, uuid='i2', pedido=p, comanda=c, categoria='Cervejas', produto='Brahma',
                            preco_centavos=500, qtd=1, cancelado_em=agora)
        # comanda do outro bar não entra
        Comanda.objects.create(bar=self.b, uuid='c2', numero=1, nome='Y', aberta_em=agora, aberta_por='G',
                               fechada_em=agora, total_centavos=99999)
        r = self.client.get('/painel/relatorio/')
        self.assertEqual(r.context['r']['faturado'], 1100)
        self.assertEqual(r.context['r']['consumo'], 1000)
        self.assertEqual(r.context['r']['servico'], 100)
        csv = self.client.get('/painel/relatorio/?formato=csv').content.decode()
        self.assertIn('Skol', csv)
        self.assertNotIn('Brahma;', csv.split('\n\n')[0] if '\n\n' in csv else csv.split('Comanda;')[0])


class PublicoTest(Base):
    def test_cardapio_publico_so_do_bar(self):
        Variante.objects.create(produto=self.prod_b, nome='', preco_centavos=900)
        r = self.client.get('/c/bar-b/')
        self.assertContains(r, 'Skol B')
        self.assertNotContains(self.client.get('/c/bar-a/'), 'Skol B')
        self.assertEqual(self.client.get('/c/nao-existe/').status_code, 404)

    def test_esgotado_some(self):
        Variante.objects.create(produto=self.prod_b, nome='', preco_centavos=900)
        Produto.objects.filter(pk=self.prod_b.pk).update(esgotado=True)
        self.assertNotContains(self.client.get('/c/bar-b/'), 'Skol B')

    def test_chamar_sem_lider_online(self):
        r = self.client.post('/c/bar-a/chamar', {'quem': '15', 'motivo': 'conta'})
        self.assertEqual(r.status_code, 503)
        self.assertIn('pessoalmente', r.json()['erro'])
        self.assertFalse(Chamado.objects.exists())

    def test_chamar_com_lider_online(self):
        u = Usuario.objects.get(bar=self.a, nome='Gar')
        Aparelho.objects.create(bar=self.a, device_id='d1', usuario=u, lider=True, ultimo_contato=timezone.now())
        r = self.client.post('/c/bar-a/chamar', {'quem': '15', 'motivo': 'conta'})
        self.assertEqual(r.status_code, 200)
        ch = Chamado.objects.get()
        self.assertEqual((ch.bar_id, ch.numero, ch.motivo), (self.a.id, 15, 'conta'))
        # chamar de novo logo em seguida é barrado
        self.assertEqual(self.client.post('/c/bar-a/chamar', {'quem': '15', 'motivo': 'conta'}).status_code, 429)
        self.assertEqual(self.client.get(f'/c/bar-a/chamado/{ch.id}').json(), {'impresso': False, 'atendido': False})
        self.assertEqual(self.client.get(f'/c/bar-b/chamado/{ch.id}').status_code, 404)

    def test_lider_antigo_nao_conta(self):
        u = Usuario.objects.get(bar=self.a, nome='Gar')
        Aparelho.objects.create(bar=self.a, device_id='d1', usuario=u, lider=True,
                                ultimo_contato=timezone.now() - timedelta(minutes=5))
        self.assertEqual(self.client.post('/c/bar-a/chamar', {'quem': 'Mesa 3'}).status_code, 503)
