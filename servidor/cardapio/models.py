from django.core.exceptions import ValidationError
from django.db import models
from django.db.models.signals import post_delete, post_save
from django.dispatch import receiver

from bares.models import Bar


class Setor(models.Model):
    """Para onde vai o cupom do pedido: "Cozinha", "Churrasqueira"... (texto livre)."""
    bar = models.ForeignKey(Bar, on_delete=models.CASCADE, related_name='setores')
    nome = models.CharField(max_length=40)
    impressora = models.CharField(max_length=80, blank=True,
                                  help_text='Vazio = impressora padrão do bar')
    ordem = models.PositiveIntegerField(default=0)

    class Meta:
        verbose_name_plural = 'setores'
        ordering = ['bar', 'ordem', 'nome']
        constraints = [models.UniqueConstraint(fields=['bar', 'nome'], name='setor_unico_no_bar')]

    def __str__(self):
        return self.nome


class Categoria(models.Model):
    bar = models.ForeignKey(Bar, on_delete=models.CASCADE, related_name='categorias')
    nome = models.CharField(max_length=40)
    ordem = models.PositiveIntegerField(default=0)
    ativa = models.BooleanField(default=True)

    class Meta:
        ordering = ['bar', 'ordem', 'nome']

    def __str__(self):
        return self.nome


class Produto(models.Model):
    bar = models.ForeignKey(Bar, on_delete=models.CASCADE, related_name='produtos')
    categoria = models.ForeignKey(Categoria, on_delete=models.CASCADE, related_name='produtos')
    nome = models.CharField(max_length=60)
    descricao = models.CharField('descrição', max_length=200, blank=True)
    foto = models.ImageField(upload_to='fotos/', blank=True)
    ordem = models.PositiveIntegerField(default=0)
    ativo = models.BooleanField(default=True)
    esgotado = models.BooleanField(default=False)
    imprime = models.BooleanField(default=False, help_text='Sai cupom quando for pedido?')
    setor = models.ForeignKey(Setor, null=True, blank=True, on_delete=models.PROTECT, related_name='produtos')

    class Meta:
        ordering = ['bar', 'categoria__ordem', 'ordem', 'nome']

    def __str__(self):
        return self.nome

    def clean(self):
        if self.imprime and not self.setor_id:
            raise ValidationError({'setor': 'Escolha o setor onde o cupom deste produto vai sair.'})
        if self.setor_id and self.setor.bar_id != self.bar_id:
            raise ValidationError({'setor': 'Setor de outro bar.'})
        if self.categoria_id and self.categoria.bar_id != self.bar_id:
            raise ValidationError({'categoria': 'Categoria de outro bar.'})


class Variante(models.Model):
    """Tamanho/tipo com preço próprio: "600ml", "Meia". Nome vazio = produto de um preço só."""
    produto = models.ForeignKey(Produto, on_delete=models.CASCADE, related_name='variantes')
    nome = models.CharField(max_length=40, blank=True)
    preco_centavos = models.PositiveIntegerField('preço (centavos)')
    ordem = models.PositiveIntegerField(default=0)

    class Meta:
        ordering = ['produto', 'ordem', 'id']

    def __str__(self):
        return f'{self.produto.nome} {self.nome}'.strip()


@receiver([post_save, post_delete], sender=Setor)
@receiver([post_save, post_delete], sender=Categoria)
@receiver([post_save, post_delete], sender=Produto)
def _mudou_cardapio(sender, instance, **kw):
    instance.bar.subir_versao_cardapio()


@receiver([post_save, post_delete], sender=Variante)
def _mudou_variante(sender, instance, **kw):
    try:
        instance.produto.bar.subir_versao_cardapio()
    except Produto.DoesNotExist:  # produto apagado junto
        pass
