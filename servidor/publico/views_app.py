"""Download do app (APK direto, antes da Play Store) e política de privacidade."""
import io

import qrcode
import qrcode.image.svg
from django.conf import settings
from django.http import FileResponse, Http404, HttpResponse
from django.shortcuts import render

from config.api import info_app


def pagina_app(request):
    return render(request, 'publico/app.html', {'app': info_app(), 'url': f'{settings.SITE_URL}/app/'})


def baixar_apk(request):
    caminho = settings.MEDIA_ROOT / 'app' / 'comandas.apk'
    if not caminho.exists():
        raise Http404('App ainda não publicado')
    v = info_app() or {}
    return FileResponse(open(caminho, 'rb'), as_attachment=True, filename=f"comandas-brasil-{v.get('versao', '')}.apk",
                        content_type='application/vnd.android.package-archive')


def qr_app(request):
    img = qrcode.make(f'{settings.SITE_URL}/app/', image_factory=qrcode.image.svg.SvgPathImage, box_size=20)
    buf = io.BytesIO()
    img.save(buf)
    return HttpResponse(buf.getvalue(), content_type='image/svg+xml')


def privacidade(request):
    return render(request, 'publico/privacidade.html', {'contato': settings.CONTATO_EMAIL})


def home(request):
    return render(request, 'publico/home.html')
