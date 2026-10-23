from django.conf import settings
from django.contrib import admin
from django.urls import include, path, re_path
from django.views.static import serve

from publico import views_app

from .api import api

urlpatterns = [
    path('', views_app.home, name='home'),
    path('painel/', include('painel.urls')),
    path('c/', include('publico.urls')),
    path('app/', views_app.pagina_app, name='app'),
    path('app/comandas.apk', views_app.baixar_apk, name='app_apk'),
    path('app/qr.svg', views_app.qr_app, name='app_qr'),
    path('privacidade/', views_app.privacidade, name='privacidade'),
    path('admin/', admin.site.urls),
    path('api/v1/', api.urls),
    # fotos do cardápio (na VPS, o nginx pode servir isto direto)
    re_path(r'^media/(?P<path>.*)$', serve, {'document_root': settings.MEDIA_ROOT}),
]
