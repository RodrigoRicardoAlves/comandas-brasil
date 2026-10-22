from django.conf import settings
from django.conf.urls.static import static
from django.contrib import admin
from django.urls import path
from django.views.generic import RedirectView

from .api import api

urlpatterns = [
    path('', RedirectView.as_view(url='/admin/')),
    path('admin/', admin.site.urls),
    path('api/v1/', api.urls),
] + static(settings.MEDIA_URL, document_root=settings.MEDIA_ROOT)
