from django.urls import path

from . import views

app_name = 'publico'
urlpatterns = [
    path('<slug:slug>/', views.cardapio, name='cardapio'),
    path('<slug:slug>/chamar', views.chamar, name='chamar'),
    path('<slug:slug>/chamado/<int:cid>', views.situacao, name='situacao'),
]
