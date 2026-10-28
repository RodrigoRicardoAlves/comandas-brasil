from django.contrib.sitemaps import Sitemap
from django.http import HttpResponse
from django.urls import reverse


class PaginasSitemap(Sitemap):
    """Páginas públicas do site. Os cardápios (/c/<bar>/) ficam de fora: são acessados pelo QR Code."""
    protocol = 'https'
    changefreq = 'monthly'

    def items(self):
        return ['home', 'app', 'privacidade']

    def location(self, item):
        return reverse(item)

    def priority(self, item):
        return {'home': 1.0, 'app': 0.8}.get(item, 0.3)


def robots_txt(request):
    linhas = [
        'User-agent: *',
        'Allow: /',
        'Disallow: /admin/',
        'Disallow: /painel/',
        'Disallow: /api/',
        'Disallow: /c/',
        f'Sitemap: https://{request.get_host()}/sitemap.xml',
    ]
    return HttpResponse('\n'.join(linhas) + '\n', content_type='text/plain')
