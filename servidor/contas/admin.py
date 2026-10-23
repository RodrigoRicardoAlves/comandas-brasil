from django import forms
from django.contrib import admin

from .models import Aparelho, AparelhoArquivado, Usuario


class UsuarioForm(forms.ModelForm):
    pin = forms.CharField(label='PIN', required=False, max_length=8,
                          help_text='4 a 8 números. Deixe vazio para manter o atual.')

    class Meta:
        model = Usuario
        fields = ['bar', 'nome', 'papel', 'ativo']

    def clean(self):
        d = super().clean()
        pin = d.get('pin')
        if not self.instance.pk and not pin:
            self.add_error('pin', 'Informe o PIN')
        if pin and d.get('bar'):
            self.instance.bar = d['bar']
            try:
                self.instance.definir_pin(pin)
            except ValueError as e:
                self.add_error('pin', str(e))
                return d
            dup = Usuario.objects.filter(bar=d['bar'], pin_hash=self.instance.pin_hash).exclude(pk=self.instance.pk)
            if dup.exists():
                self.add_error('pin', 'Outra pessoa deste bar já usa esse PIN')
        return d


@admin.register(Usuario)
class UsuarioAdmin(admin.ModelAdmin):
    form = UsuarioForm
    list_display = ['nome', 'bar', 'papel', 'ativo']
    list_filter = ['bar', 'papel', 'ativo']
    search_fields = ['nome']


@admin.register(Aparelho)
class AparelhoAdmin(admin.ModelAdmin):
    list_display = ['modelo', 'bar', 'usuario', 'ultimo_contato', 'ip_local', 'bateria', 'carregando', 'lider',
                    'pendentes']
    list_filter = ['bar']
    readonly_fields = [f.name for f in Aparelho._meta.fields]


@admin.register(AparelhoArquivado)
class AparelhoArquivadoAdmin(admin.ModelAdmin):
    list_display = ['modelo', 'bar', 'usuario', 'ultimo_contato', 'versao_app', 'arquivado_em']
    list_filter = ['bar']
    search_fields = ['modelo', 'device_id']
    readonly_fields = [f.name for f in AparelhoArquivado._meta.fields]

    def has_add_permission(self, request):
        return False
