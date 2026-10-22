from django.contrib import admin

from .models import Comanda, Evento, Item


class ItemInline(admin.TabularInline):
    model = Item
    extra = 0
    fields = ['qtd', 'produto', 'variante', 'setor', 'preco_centavos', 'obs', 'cancelado_em']
    readonly_fields = fields
    can_delete = False


@admin.register(Comanda)
class ComandaAdmin(admin.ModelAdmin):
    list_display = ['numero', 'nome', 'bar', 'aberta_em', 'aberta_por', 'fechada_em', 'total_centavos']
    list_filter = ['bar']
    inlines = [ItemInline]
    readonly_fields = [f.name for f in Comanda._meta.fields]


@admin.register(Evento)
class EventoAdmin(admin.ModelAdmin):
    list_display = ['id', 'tipo', 'bar', 'usuario', 'hora', 'recebido_em']
    list_filter = ['bar', 'tipo']
    readonly_fields = [f.name for f in Evento._meta.fields]
