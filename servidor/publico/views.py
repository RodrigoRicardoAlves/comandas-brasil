"""Cardápio público do QR Code (/c/<código>) e "chamar garçom".

Só funciona com o bar na internet: o chamado vai para a VPS e o celular líder (que consulta
a VPS a cada poucos segundos) imprime e mostra para os garçons. Se o líder não está online,
a página pede para chamar pessoalmente (não adianta registrar um chamado que ninguém vai ver).
"""
import time
from datetime import timedelta

from django.http import JsonResponse
from django.shortcuts import get_object_or_404, render
from django.utils import timezone
from django.views.decorators.http import require_POST

from bares.models import Bar
from config.api import cardapio_do_bar
from contas.models import Aparelho

from .models import Chamado

ONLINE = timedelta(seconds=30)
_limite = {}  # ip -> [horários]


def _bar(slug):
    return get_object_or_404(Bar, slug=slug, ativo=True)


def bar_online(bar):
    """Há um celular líder conversando com a VPS agora?"""
    return Aparelho.objects.filter(bar=bar, lider=True, usuario__isnull=False,
                                   ultimo_contato__gte=timezone.now() - ONLINE).exists()


def cardapio(request, slug):
    bar = _bar(slug)
    return render(request, 'publico/cardapio.html', {
        'bar': bar, 'categorias': cardapio_do_bar(bar, publico=True), 'online': bar_online(bar),
        'motivos': Chamado.MOTIVOS})


def _ip(request):
    # atrás do túnel da Cloudflare o IP do cliente vem neste cabeçalho
    return (request.META.get('HTTP_CF_CONNECTING_IP') or request.META.get('REMOTE_ADDR', ''))[:45]


@require_POST
def chamar(request, slug):
    bar = _bar(slug)
    quem = ' '.join(request.POST.get('quem', '').split())[:40]
    motivo = request.POST.get('motivo', 'outro')
    if motivo not in dict(Chamado.MOTIVOS):
        motivo = 'outro'
    if not quem:
        return JsonResponse({'erro': 'Diga o número da sua comanda ou seu nome/mesa.'}, status=400)
    if not bar_online(bar):
        return JsonResponse({'erro': 'O bar está sem internet agora. Por favor, chame o garçom pessoalmente.'}, status=503)
    ip, agora = _ip(request), time.time()
    t = [x for x in _limite.get(ip, []) if agora - x < 600]
    if t and agora - t[-1] < 20 or len(t) >= 6:
        return JsonResponse({'erro': 'Você acabou de chamar. Aguarde o garçom um instante.'}, status=429)
    t.append(agora)
    _limite[ip] = t
    # o mesmo cliente chamando de novo pelo mesmo motivo: reaproveita o chamado aberto
    ch = Chamado.objects.filter(bar=bar, quem__iexact=quem, motivo=motivo, atendido_em=None,
                                criado_em__gte=timezone.now() - timedelta(minutes=10)).first()
    if not ch:
        numero = int(quem) if quem.isdigit() and int(quem) <= bar.max_comanda else None
        ch = Chamado.objects.create(bar=bar, quem=quem, numero=numero, motivo=motivo, ip=ip)
    return JsonResponse({'id': ch.id, 'ok': True})


def situacao(request, slug, cid):
    bar = _bar(slug)
    ch = get_object_or_404(Chamado, bar=bar, id=cid)
    return JsonResponse({'impresso': ch.impresso, 'atendido': ch.atendido_em is not None})
