from django.db import models

from bares.models import Bar


class Chamado(models.Model):
    """Cliente apertou "chamar garçom" no cardápio do QR Code."""
    MOTIVOS = [('pedir', 'Quer fazer um pedido'), ('conta', 'Quer a conta'), ('outro', 'Precisa de ajuda')]

    bar = models.ForeignKey(Bar, on_delete=models.CASCADE, related_name='chamados')
    criado_em = models.DateTimeField(auto_now_add=True)
    quem = models.CharField(max_length=40, help_text='Número da comanda ou nome digitado')
    numero = models.PositiveIntegerField(null=True, blank=True)
    motivo = models.CharField(max_length=10, choices=MOTIVOS, default='outro')
    ip = models.CharField(max_length=45, blank=True)
    impresso = models.BooleanField(default=False)
    atendido_em = models.DateTimeField(null=True, blank=True)
    atendido_por = models.CharField(max_length=40, blank=True)

    class Meta:
        ordering = ['-criado_em']

    def __str__(self):
        return f'{self.quem}: {self.get_motivo_display()}'

    def como_dict(self):
        return {'id': self.id, 'quem': self.quem, 'numero': self.numero, 'motivo': self.motivo,
                'motivo_texto': self.get_motivo_display(), 'criado_em': self.criado_em.isoformat(),
                'impresso': self.impresso}
