from django.conf import settings
from django.conf.urls.static import static
from django.contrib import admin
from django.urls import include, path
from django.views.generic import RedirectView

from .api import api

urlpatterns = [
    path('', RedirectView.as_view(url='/painel/')),
    path('painel/', include('painel.urls')),
    path('c/', include('publico.urls')),
    path('admin/', admin.site.urls),
    path('api/v1/', api.urls),
] + static(settings.MEDIA_URL, document_root=settings.MEDIA_ROOT)
