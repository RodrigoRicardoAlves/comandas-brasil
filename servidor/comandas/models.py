from django.db import models

from bares.models import Bar


class Evento(models.Model):
    """Registro imutável de tudo que acontece no bar. O UUID vem do celular: reenviar não duplica."""
    bar = models.ForeignKey(Bar, on_delete=models.CASCADE, related_name='eventos')
    uuid = models.CharField(max_length=36, unique=True)
    tipo = models.CharField(max_length=30)
    device_id = models.CharField(max_length=64)
    usuario = models.CharField(max_length=40)
    hora = models.DateTimeField(help_text='Hora em que aconteceu, no celular')
    dados = models.JSONField()
    recebido_em = models.DateTimeField(auto_now_add=True)

    class Meta:
        ordering = ['id']  # id = seq_servidor
        indexes = [models.Index(fields=['bar', 'id'])]

    def __str__(self):
        return f'{self.tipo} {self.uuid[:8]}'

    def como_dict(self):
        return {'uuid': self.uuid, 'tipo': self.tipo, 'device_id': self.device_id, 'usuario': self.usuario,
                'hora': self.hora.isoformat(), 'dados': self.dados, 'seq': self.id}


# ---- tabelas de leitura (montadas a partir dos eventos; servem para relatório e painel)

class Comanda(models.Model):
    bar = models.ForeignKey(Bar, on_delete=models.CASCADE, related_name='comandas')
    uuid = models.CharField(max_length=36, unique=True)
    numero = models.PositiveIntegerField()
    nome = models.CharField(max_length=40)
    aberta_em = models.DateTimeField()
    aberta_por = models.CharField(max_length=40)
    fechada_em = models.DateTimeField(null=True, blank=True)
    fechada_por = models.CharField(max_length=60, blank=True)
    taxa_servico = models.DecimalField(max_digits=4, decimal_places=1, default=0)
    total_centavos = models.IntegerField(null=True, blank=True)
    descartada = models.BooleanField(default=False)
    juntada_para = models.CharField(max_length=36, blank=True, help_text='Conflito resolvido juntando nesta comanda (uuid)')
    conhecidos = models.JSONField(null=True, blank=True, help_text='Pedidos que quem fechou conhecia')

    class Meta:
        ordering = ['-aberta_em']
        indexes = [models.Index(fields=['bar', 'fechada_em'])]

    def __str__(self):
        return f'Comanda {self.numero} - {self.nome}'

    @property
    def aberta(self):
        return self.fechada_em is None and not self.descartada


class Pedido(models.Model):
    bar = models.ForeignKey(Bar, on_delete=models.CASCADE)
    uuid = models.CharField(max_length=36, unique=True)
    comanda = models.ForeignKey(Comanda, on_delete=models.CASCADE, related_name='pedidos')
    feito_em = models.DateTimeField()
    garcom = models.CharField(max_length=40)
    offline = models.BooleanField(default=False)
    SITUACOES = [('', 'normal'), ('pendente', 'atrasado: aguarda o gerente'), ('descartado', 'descartado pelo gerente')]
    situacao = models.CharField(max_length=12, blank=True, default='', choices=SITUACOES)

    class Meta:
        ordering = ['feito_em']


class Item(models.Model):
    bar = models.ForeignKey(Bar, on_delete=models.CASCADE)
    uuid = models.CharField(max_length=36, unique=True)
    pedido = models.ForeignKey(Pedido, on_delete=models.CASCADE, related_name='itens')
    comanda = models.ForeignKey(Comanda, on_delete=models.CASCADE, related_name='itens')
    variante_id = models.IntegerField(null=True)
    categoria = models.CharField(max_length=40)
    produto = models.CharField(max_length=60)
    variante = models.CharField(max_length=40, blank=True)
    setor = models.CharField(max_length=40, blank=True)
    imprime = models.BooleanField(default=False)
    preco_centavos = models.IntegerField()
    qtd = models.PositiveIntegerField()
    obs = models.CharField(max_length=80, blank=True)
    cancelado_em = models.DateTimeField(null=True, blank=True)
    cancelado_por = models.CharField(max_length=60, blank=True)

    class Meta:
        ordering = ['id']

    @property
    def total(self):
        return self.preco_centavos * self.qtd
