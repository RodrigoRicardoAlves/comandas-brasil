from django.contrib import admin

from .models import Chamado


@admin.register(Chamado)
class ChamadoAdmin(admin.ModelAdmin):
    list_display = ['criado_em', 'bar', 'quem', 'motivo', 'atendido_em', 'atendido_por']
    list_filter = ['bar']
