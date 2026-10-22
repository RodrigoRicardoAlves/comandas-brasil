from django.contrib import admin

from .models import Bar

admin.site.site_header = 'Comandas · Super admin'
admin.site.site_title = 'Comandas'
admin.site.index_title = 'Bares e cadastros'


@admin.register(Bar)
class BarAdmin(admin.ModelAdmin):
    list_display = ['nome', 'slug', 'ativo', 'impressora', 'versao_cardapio', 'criado_em']
    prepopulated_fields = {'slug': ['nome']}
    readonly_fields = ['versao_cardapio', 'criado_em']
    fieldsets = [
        (None, {'fields': ['nome', 'slug', 'ativo']}),
        ('Impressão e conta', {'fields': ['impressora', 'colunas_papel', 'codificacao', 'cortar_papel',
                                          'taxa_servico', 'rodape', 'max_comanda']}),
        ('Sistema', {'fields': ['versao_cardapio', 'criado_em'], 'classes': ['collapse']}),
    ]
