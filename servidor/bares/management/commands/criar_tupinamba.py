"""Cria o Bar Tupinambá: bar de teste/exemplo, com cardápio, setores e PINs.

É o cardápio de exemplo do site (/c/tupinamba) e o bar usado para testar o app e o painel.
Pode rodar de novo sem duplicar.
"""
from django.core.management.base import BaseCommand
from django.db import transaction

from bares.models import Bar
from cardapio.models import Categoria, Produto, Setor, Variante
from contas.models import Usuario

# (categoria, setor ou None, [(produto, descrição, [(variante, preço em centavos)])])
CARDAPIO = [
    ('Cervejas', None, [
        ('Brahma', 'Bem gelada, trincando.', [('600ml', 1100), ('Lata', 650)]),
        ('Original', '', [('600ml', 1300)]),
        ('Heineken', '', [('600ml', 1600), ('Long neck', 1100)]),
        ('Chopp da casa', 'Pilsen tirado na hora.', [('Caneca 500ml', 1400), ('Tulipa 300ml', 900)]),
    ]),
    ('Sem álcool', None, [
        ('Coca-Cola', '', [('2L', 1500), ('Lata', 650)]),
        ('Guaraná Antarctica', '', [('2L', 1300), ('Lata', 650)]),
        ('Suco natural', 'Laranja, limão, maracujá ou abacaxi com hortelã.', [('Copo', 1000), ('Jarra', 2400)]),
        ('Água', '', [('Sem gás', 450), ('Com gás', 550)]),
    ]),
    ('Petiscos', 'Cozinha', [
        ('Batata frita', 'Com cheddar e bacon na versão especial.', [('Inteira', 3600), ('Meia', 2300), ('Especial', 4500)]),
        ('Bolinho de mandioca com carne seca', '10 unidades, acompanha molho da casa.', [('', 3900)]),
        ('Torresmo pururuca', 'Crocante, com limão.', [('Inteira', 3400), ('Meia', 2100)]),
        ('Pastel de feira', 'Carne, queijo ou palmito. 6 unidades.', [('', 3200)]),
        ('Isca de tilápia', 'Empanada, com molho tártaro.', [('Inteira', 5200), ('Meia', 3200)]),
    ]),
    ('Na brasa', 'Churrasqueira', [
        ('Espetinho de carne', '', [('', 1100)]),
        ('Espetinho de frango com bacon', '', [('', 1000)]),
        ('Espetinho de queijo coalho', 'Com melaço.', [('', 900)]),
        ('Picanha na tábua', 'Acompanha mandioca, farofa e vinagrete.', [('Inteira', 9400), ('Meia', 5600)]),
    ]),
    ('Pratos', 'Cozinha', [
        ('Feijoada', 'Sábado. Arroz, couve, farofa, torresmo e laranja.', [('Individual', 4200), ('Para dois', 7800)]),
        ('Escondidinho de carne seca', 'Purê de mandioca gratinado.', [('', 3900)]),
    ]),
    ('Drinks', 'Bar', [
        ('Caipirinha', 'Limão, morango, maracujá ou kiwi.', [('Cachaça', 1600), ('Vodka', 1900)]),
        ('Caju amigo', 'Cachaça com caju. Clássico.', [('', 1200)]),
        ('Gin tônica', 'Com especiarias.', [('', 2600)]),
        ('Dose de cachaça', 'Pergunte as artesanais do dia.', [('', 700)]),
    ]),
    ('Sobremesas', 'Cozinha', [
        ('Pudim de leite', '', [('Fatia', 1400)]),
        ('Petit gâteau', 'Com sorvete de creme.', [('', 2200)]),
    ]),
]


class Command(BaseCommand):
    help = 'Cria/atualiza o Bar Tupinambá (bar de teste e cardápio de exemplo do site)'

    @transaction.atomic
    def handle(self, *a, **kw):
        bar, criado = Bar.objects.get_or_create(slug='tupinamba', defaults={'nome': 'Bar Tupinambá'})
        setores = {}
        for i, nome in enumerate(['Cozinha', 'Churrasqueira', 'Bar']):
            setores[nome], _ = Setor.objects.get_or_create(bar=bar, nome=nome, defaults={'ordem': i})
        for ci, (cnome, setor, prods) in enumerate(CARDAPIO):
            cat, _ = Categoria.objects.get_or_create(bar=bar, nome=cnome, defaults={'ordem': ci})
            for pi, (pnome, desc, vars_) in enumerate(prods):
                p, novo = Produto.objects.get_or_create(bar=bar, categoria=cat, nome=pnome, defaults={
                    'descricao': desc, 'ordem': pi, 'imprime': setor is not None, 'setor': setores.get(setor)})
                if novo:
                    for vi, (vnome, preco) in enumerate(vars_):
                        Variante.objects.create(produto=p, nome=vnome, preco_centavos=preco, ordem=vi)
        for nome, papel, pin in [('Seu Antônio', 'gerente', '9999'), ('João', 'garcom', '1234'),
                                 ('Maria', 'garcom', '5678')]:
            if not Usuario.objects.filter(bar=bar, nome=nome).exists():
                u = Usuario(bar=bar, nome=nome, papel=papel)
                u.definir_pin(pin)
                u.save()
        self.stdout.write(self.style.SUCCESS(f'{"Criado" if criado else "Atualizado"}: {bar} → /c/{bar.slug}/'))
