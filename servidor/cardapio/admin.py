from django.contrib import admin

from .models import Categoria, Produto, Setor, Variante


@admin.register(Setor)
class SetorAdmin(admin.ModelAdmin):
    list_display = ['nome', 'bar', 'impressora', 'ordem']
    list_filter = ['bar']


@admin.register(Categoria)
class CategoriaAdmin(admin.ModelAdmin):
    list_display = ['nome', 'bar', 'ordem', 'ativa']
    list_filter = ['bar']
    list_editable = ['ordem', 'ativa']


class VarianteInline(admin.TabularInline):
    model = Variante
    extra = 1


@admin.register(Produto)
class ProdutoAdmin(admin.ModelAdmin):
    list_display = ['nome', 'categoria', 'bar', 'imprime', 'setor', 'ativo', 'esgotado']
    list_filter = ['bar', 'categoria', 'imprime', 'setor', 'esgotado']
    list_editable = ['imprime', 'setor', 'esgotado']
    search_fields = ['nome']
    inlines = [VarianteInline]
