"""Cria o Bar do Zé Maria com cardápio, setores e PINs de exemplo (pode rodar de novo sem duplicar)."""
from django.core.management.base import BaseCommand
from django.db import transaction

from bares.models import Bar
from cardapio.models import Categoria, Produto, Setor, Variante
from contas.models import Usuario

# (categoria, setor ou None, [(produto, [(variante, preço em centavos)])])
CARDAPIO = [
    ('Cervejas', None, [
        ('Brahma', [('1L', 1500), ('600ml', 1000), ('Lata', 600)]),
        ('Skol', [('1L', 1500), ('600ml', 1000), ('Lata', 600)]),
        ('Original', [('600ml', 1200)]),
        ('Heineken', [('600ml', 1500), ('Long neck', 1000)]),
    ]),
    ('Refrigerantes', None, [
        ('Coca-Cola', [('2L', 1400), ('600ml', 800), ('Lata', 600)]),
        ('Guaraná Antarctica', [('2L', 1200), ('Lata', 600)]),
        ('Água', [('Sem gás', 400), ('Com gás', 500)]),
    ]),
    ('Porções', 'Cozinha', [
        ('Batata frita', [('Inteira', 3500), ('Meia', 2200)]),
        ('Calabresa acebolada', [('Inteira', 4000), ('Meia', 2500)]),
        ('Frango a passarinho', [('Inteira', 4500), ('Meia', 2800)]),
        ('Mandioca frita', [('Inteira', 3000), ('Meia', 1900)]),
    ]),
    ('Churrasco', 'Churrasqueira', [
        ('Espetinho de carne', [('', 1000)]),
        ('Espetinho de frango', [('', 900)]),
        ('Espetinho de linguiça', [('', 900)]),
        ('Picanha na chapa', [('Inteira', 8900), ('Meia', 5200)]),
    ]),
    ('Doses', 'Bar', [
        ('Cachaça', [('', 500)]),
        ('Caipirinha', [('Limão', 1500), ('Morango', 1800)]),
    ]),
]


class Command(BaseCommand):
    help = 'Cria/atualiza o bar de exemplo do Zé Maria'

    @transaction.atomic
    def handle(self, *a, **kw):
        bar, criado = Bar.objects.get_or_create(slug='zemaria', defaults={'nome': 'Bar do Zé Maria'})
        setores = {}
        for i, nome in enumerate(['Cozinha', 'Churrasqueira', 'Bar']):
            setores[nome], _ = Setor.objects.get_or_create(bar=bar, nome=nome, defaults={'ordem': i})
        for ci, (cnome, setor, prods) in enumerate(CARDAPIO):
            cat, _ = Categoria.objects.get_or_create(bar=bar, nome=cnome, defaults={'ordem': ci})
            for pi, (pnome, vars_) in enumerate(prods):
                p, novo = Produto.objects.get_or_create(bar=bar, categoria=cat, nome=pnome, defaults={
                    'ordem': pi, 'imprime': setor is not None, 'setor': setores.get(setor)})
                if novo:
                    for vi, (vnome, preco) in enumerate(vars_):
                        Variante.objects.create(produto=p, nome=vnome, preco_centavos=preco, ordem=vi)
        for nome, papel, pin in [('Zé Maria', 'gerente', '9999'), ('João', 'garcom', '1234'),
                                 ('Maria', 'garcom', '5678')]:
            if not Usuario.objects.filter(bar=bar, nome=nome).exists():
                u = Usuario(bar=bar, nome=nome, papel=papel)
                u.definir_pin(pin)
                u.save()
        self.stdout.write(self.style.SUCCESS(f'{"Criado" if criado else "Atualizado"}: {bar} (código "{bar.slug}")'))
