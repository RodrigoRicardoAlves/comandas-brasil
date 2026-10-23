import hashlib
import secrets

from django.db import models

from bares.models import Bar


def hash_pin(bar, pin):
    """Mesmo cálculo é feito no celular para o login sem internet."""
    return hashlib.sha256((bar.pin_salt + str(pin)).encode()).hexdigest()


class Usuario(models.Model):
    GARCOM, GERENTE = 'garcom', 'gerente'
    PAPEIS = [(GARCOM, 'Garçom'), (GERENTE, 'Gerente')]

    bar = models.ForeignKey(Bar, on_delete=models.CASCADE, related_name='usuarios')
    nome = models.CharField(max_length=40)
    pin_hash = models.CharField(max_length=64, editable=False)
    papel = models.CharField(max_length=10, choices=PAPEIS, default=GARCOM)
    ativo = models.BooleanField(default=True)
    criado_em = models.DateTimeField(auto_now_add=True)

    class Meta:
        verbose_name = 'garçom / gerente'
        verbose_name_plural = 'garçons e gerentes'
        ordering = ['bar', 'nome']
        constraints = [models.UniqueConstraint(fields=['bar', 'pin_hash'], name='pin_unico_no_bar')]

    def __str__(self):
        return f'{self.nome} ({self.get_papel_display()})'

    @property
    def gerente(self):
        return self.papel == self.GERENTE

    def definir_pin(self, pin):
        pin = str(pin).strip()
        if not pin.isdigit() or not 4 <= len(pin) <= 8:
            raise ValueError('O PIN precisa ter de 4 a 8 números')
        self.pin_hash = hash_pin(self.bar, pin)


class Aparelho(models.Model):
    """Um celular que entrou no sistema. O token vale até o garçom encerrar o turno."""
    bar = models.ForeignKey(Bar, on_delete=models.CASCADE, related_name='aparelhos')
    device_id = models.CharField(max_length=64)
    modelo = models.CharField(max_length=80, blank=True)
    usuario = models.ForeignKey(Usuario, null=True, blank=True, on_delete=models.SET_NULL)
    token = models.CharField(max_length=64, unique=True, null=True, blank=True, editable=False)
    versao_app = models.CharField(max_length=20, blank=True)
    # presença (atualizada a cada poucos segundos pelo celular)
    ultimo_contato = models.DateTimeField(null=True, blank=True)
    ip_local = models.CharField(max_length=45, blank=True)
    porta_local = models.PositiveIntegerField(null=True, blank=True)
    bateria = models.PositiveSmallIntegerField(null=True, blank=True)
    carregando = models.BooleanField(default=False)
    lider = models.BooleanField(default=False)
    pendentes = models.PositiveIntegerField(default=0)
    criado_em = models.DateTimeField(auto_now_add=True)

    class Meta:
        ordering = ['bar', 'modelo']
        constraints = [models.UniqueConstraint(fields=['bar', 'device_id'], name='aparelho_unico_no_bar')]

    def __str__(self):
        return f'{self.modelo or "Aparelho"} ({self.usuario.nome if self.usuario else "sem login"})'

    def novo_token(self):
        self.token = secrets.token_hex(24)
        return self.token


class AparelhoArquivado(models.Model):
    """Tabela morta: celulares parados há mais de 24 h, sem nada pendente, tirados de Aparelho
    pela tarefa contas.tarefas.arquivar_aparelhos_parados. Só para consulta."""
    aparelho_id = models.PositiveIntegerField('id original')
    bar = models.ForeignKey(Bar, on_delete=models.CASCADE, related_name='aparelhos_arquivados')
    device_id = models.CharField(max_length=64)
    modelo = models.CharField(max_length=80, blank=True)
    usuario = models.ForeignKey(Usuario, null=True, blank=True, on_delete=models.SET_NULL)
    versao_app = models.CharField(max_length=20, blank=True)
    ultimo_contato = models.DateTimeField(null=True, blank=True)
    ip_local = models.CharField(max_length=45, blank=True)
    bateria = models.PositiveSmallIntegerField(null=True, blank=True)
    criado_em = models.DateTimeField()
    arquivado_em = models.DateTimeField(auto_now_add=True)

    class Meta:
        ordering = ['-arquivado_em']
        verbose_name = 'aparelho arquivado'
        verbose_name_plural = 'aparelhos arquivados'

    def __str__(self):
        return f'{self.modelo or "Aparelho"} (arquivado em {self.arquivado_em:%d/%m/%Y})'
