from django.conf import settings
from django.contrib import admin
from django.urls import include, path, re_path
from django.views.static import serve
from django.views.generic import RedirectView

from .api import api

urlpatterns = [
    path('', RedirectView.as_view(url='/painel/')),
    path('painel/', include('painel.urls')),
    path('c/', include('publico.urls')),
    path('admin/', admin.site.urls),
    path('api/v1/', api.urls),
    # fotos do cardápio (na VPS, o nginx pode servir isto direto)
    re_path(r'^media/(?P<path>.*)$', serve, {'document_root': settings.MEDIA_ROOT}),
]
