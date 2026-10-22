import secrets

from django.db import models


def nova_chave():
    return secrets.token_hex(16)


class Bar(models.Model):
    """Um bar atendido pelo sistema. Tudo que é do dia a dia pertence a um bar."""
    CODIFICACOES = [('ascii', 'Sem acentos'), ('cp860', 'CP860 (português)'), ('cp850', 'CP850')]

    nome = models.CharField(max_length=80)
    slug = models.SlugField('código', unique=True, help_text='Usado no login do app e no endereço do cardápio (/c/código)')
    ativo = models.BooleanField(default=True)
    criado_em = models.DateTimeField(auto_now_add=True)
    # segredos (não aparecem para o gerente)
    lan_key = models.CharField(max_length=64, default=nova_chave, editable=False,
                               help_text='Assina a conversa entre os celulares na rede local')
    pin_salt = models.CharField(max_length=64, default=nova_chave, editable=False)
    versao_cardapio = models.PositiveIntegerField(default=1, editable=False)

    # configurações do bar
    rodape = models.CharField('rodapé da conta', max_length=120, blank=True, default='Obrigado pela preferência!')
    colunas_papel = models.PositiveSmallIntegerField('colunas do papel', default=48,
                                                     choices=[(48, '80mm (48 colunas)'), (32, '58mm (32 colunas)')])
    codificacao = models.CharField('acentos na impressora', max_length=8, choices=CODIFICACOES, default='ascii')
    cortar_papel = models.BooleanField('cortar papel', default=True)
    taxa_servico = models.DecimalField('taxa de serviço (%)', max_digits=4, decimal_places=1, default=0)
    max_comanda = models.PositiveIntegerField('maior número de comanda', default=200)
    impressora = models.CharField('impressora padrão', max_length=80, blank=True,
                                  help_text='IP da impressora na rede do bar, ex.: 192.168.1.50:9100')

    class Meta:
        verbose_name = 'bar'
        verbose_name_plural = 'bares'
        ordering = ['nome']

    def __str__(self):
        return self.nome

    def subir_versao_cardapio(self):
        Bar.objects.filter(pk=self.pk).update(versao_cardapio=models.F('versao_cardapio') + 1)
