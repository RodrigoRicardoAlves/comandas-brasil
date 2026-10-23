from django.urls import path

from . import views

app_name = 'painel'
urlpatterns = [
    path('', views.inicio, name='inicio'),
    path('entrar/', views.entrar, name='entrar'),
    path('via-app/', views.via_app, name='via_app'),
    path('sair/', views.sair, name='sair'),
    path('cardapio/', views.cardapio, name='cardapio'),
    path('cardapio/categoria/nova/', views.categoria, name='categoria_nova'),
    path('cardapio/categoria/<int:pk>/', views.categoria, name='categoria'),
    path('cardapio/produto/novo/', views.produto, name='produto_novo'),
    path('cardapio/produto/<int:pk>/', views.produto, name='produto'),
    path('cardapio/produto/<int:pk>/esgotado/', views.esgotado, name='esgotado'),
    path('setores/', views.setores, name='setores'),
    path('setores/novo/', views.setor, name='setor_novo'),
    path('setores/<int:pk>/', views.setor, name='setor'),
    path('equipe/', views.equipe, name='equipe'),
    path('equipe/novo/', views.usuario, name='usuario_novo'),
    path('equipe/<int:pk>/', views.usuario, name='usuario'),
    path('configuracoes/', views.config, name='config'),
    path('aparelhos/', views.aparelhos, name='aparelhos'),
    path('aparelhos/<int:pk>/desconectar/', views.desconectar, name='desconectar'),
    path('relatorio/', views.relatorio, name='relatorio'),
    path('comanda/<int:pk>/', views.comanda, name='comanda'),
    path('qr/', views.qr, name='qr'),
    path('qr.svg', views.qr_svg, name='qr_svg'),
]
