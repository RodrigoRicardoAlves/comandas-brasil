"""Painel web do gerente (/painel/). Entra com código do bar + PIN de gerente.

Toda consulta usa `request.bar` (o bar do gerente logado): um gerente nunca vê outro bar.
"""
import csv
import io
import secrets
import time
from datetime import datetime, timedelta
from functools import wraps

import qrcode
import qrcode.image.svg
from django.conf import settings
from django.core import signing
from django.core.cache import cache
from django.contrib import messages
from django.db.models import Count, F, ProtectedError, Sum
from django.http import HttpResponse
from django.shortcuts import get_object_or_404, redirect, render
from django.urls import reverse
from django.utils import timezone
from django.views.decorators.http import require_POST

from bares.models import Bar
from cardapio.models import Categoria, Produto, Setor
from comandas.models import Comanda, Item, Pedido
from contas.models import Aparelho, Usuario, hash_pin
from publico.models import Chamado

from .forms import (BarForm, CategoriaForm, EntrarForm, PeriodoForm, ProdutoForm, SetorForm, UsuarioForm, Variantes,
                    reais)

ONLINE = timedelta(seconds=30)


# ------------------------------------------------------------------ acesso

def gerente_requerido(view):
    @wraps(view)
    def envolve(request, *a, **kw):
        uid = request.session.get('painel_usuario')
        u = (Usuario.objects.select_related('bar')
             .filter(pk=uid, ativo=True, papel=Usuario.GERENTE, bar__ativo=True).first()) if uid else None
        if not u:
            return redirect(f"{reverse('painel:entrar')}?next={request.path}")
        request.gerente, request.bar = u, u.bar
        return view(request, *a, **kw)
    return envolve


_tentativas = {}


def entrar(request):
    form = EntrarForm(request.POST or None, initial={'bar': request.GET.get('bar', '')})
    if request.method == 'POST' and form.is_valid():
        ip = request.META.get('REMOTE_ADDR', '')
        agora = time.time()
        t = [x for x in _tentativas.get(ip, []) if agora - x < 300]
        if len(t) >= 10:
            form.add_error(None, 'Muitas tentativas. Aguarde alguns minutos.')
        else:
            t.append(agora)
            _tentativas[ip] = t
            bar = Bar.objects.filter(slug=form.cleaned_data['bar'].strip().lower(), ativo=True).first()
            u = bar and Usuario.objects.filter(bar=bar, ativo=True, papel=Usuario.GERENTE,
                                               pin_hash=hash_pin(bar, form.cleaned_data['pin'].strip())).first()
            if u:
                request.session.cycle_key()
                request.session['painel_usuario'] = u.pk
                destino = request.GET.get('next', '')
                return redirect(destino if destino.startswith('/painel/') else 'painel:inicio')
            form.add_error(None, 'Código do bar ou PIN de gerente incorreto.')
    return render(request, 'painel/entrar.html', {'form': form})


# ------------------------------------------------------------------ entrada pelo app do gerente

VIA_APP_SEGUNDOS = 60


def link_via_app(u):
    """Link de entrada no painel, assinado, que vale uma vez e por pouco tempo (o app abre na hora)."""
    t = signing.dumps({'u': u.pk, 'n': secrets.token_urlsafe(12)}, salt='painel.via_app')
    return f"{reverse('painel:via_app')}?t={t}"


def via_app(request):
    try:
        d = signing.loads(request.GET.get('t', ''), salt='painel.via_app', max_age=VIA_APP_SEGUNDOS)
    except signing.BadSignature:
        d = None
    # cada link entra uma vez só
    u = d and cache.add(f"via_app:{d['n']}", 1, VIA_APP_SEGUNDOS * 2) and (
        Usuario.objects.filter(pk=d['u'], ativo=True, papel=Usuario.GERENTE, bar__ativo=True).first())
    if not u:
        messages.error(request, 'Link de acesso vencido. Abra a gestão de novo pelo app.')
        return redirect('painel:entrar')
    request.session.cycle_key()
    request.session['painel_usuario'] = u.pk
    request.session['via_app'] = True
    return redirect('painel:inicio')


def sair(request):
    request.session.flush()
    return redirect('painel:entrar')


# ------------------------------------------------------------------ expediente (06:00 às 05:59)

def inicio_do_dia(dia):
    return timezone.make_aware(datetime.combine(dia, datetime.min.time()) + timedelta(hours=settings.INICIO_EXPEDIENTE))


def dia_atual():
    agora = timezone.localtime()
    d = agora.date()
    return d - timedelta(days=1) if agora.hour < settings.INICIO_EXPEDIENTE else d


def itens_validos(bar):
    return Item.objects.filter(bar=bar, cancelado_em=None, pedido__situacao='')


def valor():
    return Sum(F('preco_centavos') * F('qtd'))


# ------------------------------------------------------------------ início

@gerente_requerido
def inicio(request):
    bar = request.bar
    abertas = Comanda.objects.filter(bar=bar, fechada_em=None, descartada=False)
    em_aberto = itens_validos(bar).filter(comanda__in=abertas).aggregate(v=valor())['v'] or 0
    hoje = Comanda.objects.filter(bar=bar, descartada=False, fechada_em__gte=inicio_do_dia(dia_atual()))
    aparelhos = (Aparelho.objects.filter(bar=bar, usuario__isnull=False, ultimo_contato__gte=timezone.now() - ONLINE)
                 .select_related('usuario'))
    return render(request, 'painel/inicio.html', {
        'abertas': abertas.order_by('numero'),
        'em_aberto': em_aberto,
        'fechadas_hoje': hoje.count(),
        'faturado_hoje': hoje.aggregate(v=Sum('total_centavos'))['v'] or 0,
        'aparelhos': aparelhos,
        'pendentes': Pedido.objects.filter(bar=bar, situacao='pendente').select_related('comanda'),
        'chamados': Chamado.objects.filter(bar=bar, atendido_em=None, criado_em__gte=timezone.now() - timedelta(hours=2)),
        'url_cardapio': f'{settings.SITE_URL}/c/{bar.slug}',
    })


# ------------------------------------------------------------------ cardápio

@gerente_requerido
def cardapio(request):
    cats = Categoria.objects.filter(bar=request.bar).prefetch_related('produtos__variantes', 'produtos__setor')
    sem_categoria = Produto.objects.filter(bar=request.bar, categoria__isnull=True)
    return render(request, 'painel/cardapio.html', {'categorias': cats, 'sem_categoria': sem_categoria,
                                                    'setores': Setor.objects.filter(bar=request.bar).exists()})


@gerente_requerido
def categoria(request, pk=None):
    obj = get_object_or_404(Categoria, bar=request.bar, pk=pk) if pk else Categoria(bar=request.bar)
    form = CategoriaForm(request.POST or None, instance=obj)
    if request.method == 'POST':
        if 'apagar' in request.POST and obj.pk:
            if obj.produtos.exists():
                messages.error(request, 'Tire os produtos desta categoria antes de apagá-la.')
            else:
                obj.delete()
                messages.success(request, 'Categoria apagada.')
                return redirect('painel:cardapio')
        elif form.is_valid():
            form.save()
            messages.success(request, f'Categoria "{obj.nome}" salva.')
            return redirect('painel:cardapio')
    return render(request, 'painel/form.html', {'form': form, 'titulo': 'Categoria', 'pode_apagar': bool(obj.pk),
                                                'voltar': reverse('painel:cardapio')})


@gerente_requerido
def produto(request, pk=None):
    obj = get_object_or_404(Produto, bar=request.bar, pk=pk) if pk else Produto(bar=request.bar)
    if not pk and request.GET.get('categoria'):
        obj.categoria = Categoria.objects.filter(bar=request.bar, pk=request.GET['categoria']).first()
    form = ProdutoForm(request.POST or None, request.FILES or None, instance=obj, bar=request.bar)
    variantes = Variantes(request.POST or None, instance=obj, prefix='v')
    if request.method == 'POST':
        if 'apagar' in request.POST and obj.pk:
            obj.delete()
            messages.success(request, 'Produto apagado.')
            return redirect('painel:cardapio')
        if form.is_valid() and variantes.is_valid():
            vivas = [f for f in variantes.forms
                     if f.cleaned_data and not f.cleaned_data.get('DELETE') and (f.has_changed() or f.instance.pk)]
            if not vivas:
                form.add_error(None, 'Informe pelo menos um preço.')
            else:
                form.save()
                variantes.instance = obj
                variantes.save()
                messages.success(request, f'"{obj.nome}" salvo.')
                return redirect('painel:cardapio')
    return render(request, 'painel/produto.html', {'form': form, 'variantes': variantes, 'obj': obj})


@gerente_requerido
@require_POST
def esgotado(request, pk):
    p = get_object_or_404(Produto, bar=request.bar, pk=pk)
    p.esgotado = not p.esgotado
    p.save(update_fields=['esgotado'])
    messages.success(request, f'{p.nome}: {"esgotado" if p.esgotado else "disponível de novo"}.')
    return redirect(f"{reverse('painel:cardapio')}#p{p.pk}")


# ------------------------------------------------------------------ setores

@gerente_requerido
def setores(request):
    return render(request, 'painel/setores.html', {
        'setores': Setor.objects.filter(bar=request.bar).annotate(n=Count('produtos'))})


@gerente_requerido
def setor(request, pk=None):
    obj = get_object_or_404(Setor, bar=request.bar, pk=pk) if pk else Setor(bar=request.bar)
    form = SetorForm(request.POST or None, instance=obj)
    if request.method == 'POST':
        if 'apagar' in request.POST and obj.pk:
            try:
                obj.delete()
                messages.success(request, 'Setor apagado.')
                return redirect('painel:setores')
            except ProtectedError:
                messages.error(request, 'Há produtos imprimindo neste setor. Mude-os de setor antes.')
        elif form.is_valid():
            if Setor.objects.filter(bar=request.bar, nome__iexact=form.cleaned_data['nome']).exclude(pk=obj.pk).exists():
                form.add_error('nome', 'Já existe um setor com esse nome.')
            else:
                form.save()
                messages.success(request, f'Setor "{obj.nome}" salvo.')
                return redirect('painel:setores')
    return render(request, 'painel/form.html', {
        'form': form, 'titulo': 'Setor de impressão', 'pode_apagar': bool(obj.pk), 'voltar': reverse('painel:setores'),
        'ajuda': 'Cada setor recebe um cupom separado com os itens dele. Impressora vazia = impressora padrão do bar.'})


# ------------------------------------------------------------------ equipe

@gerente_requerido
def equipe(request):
    return render(request, 'painel/equipe.html', {'usuarios': Usuario.objects.filter(bar=request.bar)})


@gerente_requerido
def usuario(request, pk=None):
    obj = get_object_or_404(Usuario, bar=request.bar, pk=pk) if pk else Usuario(bar=request.bar)
    form = UsuarioForm(request.POST or None, instance=obj)
    if request.method == 'POST' and form.is_valid():
        if obj.pk == request.gerente.pk and (form.cleaned_data['papel'] != Usuario.GERENTE or not form.cleaned_data['ativo']):
            form.add_error(None, 'Você não pode tirar o seu próprio acesso de gerente.')
        else:
            form.save()
            # PIN, nome ou papel mudou: os celulares baixam a lista de novo
            request.bar.subir_versao_cardapio()
            messages.success(request, f'{obj.nome} salvo.')
            return redirect('painel:equipe')
    return render(request, 'painel/form.html', {'form': form, 'titulo': 'Garçom / gerente', 'voltar': reverse('painel:equipe'),
                                                'ajuda': 'O PIN é usado para entrar no app. Cada pessoa do bar tem o seu.'})


# ------------------------------------------------------------------ configurações e aparelhos

@gerente_requerido
def config(request):
    form = BarForm(request.POST or None, instance=request.bar)
    if request.method == 'POST' and form.is_valid():
        form.save()
        messages.success(request, 'Configurações salvas. Os celulares atualizam sozinhos em alguns segundos.')
        return redirect('painel:config')
    return render(request, 'painel/form.html', {'form': form, 'titulo': 'Configurações do bar', 'voltar': reverse('painel:inicio')})


@gerente_requerido
def aparelhos(request):
    lista = Aparelho.objects.filter(bar=request.bar).select_related('usuario').order_by('-ultimo_contato')
    corte = timezone.now() - ONLINE
    return render(request, 'painel/aparelhos.html', {
        'aparelhos': [(a, a.ultimo_contato and a.ultimo_contato >= corte) for a in lista]})


@gerente_requerido
@require_POST
def desconectar(request, pk):
    a = get_object_or_404(Aparelho, bar=request.bar, pk=pk)
    a.token, a.usuario, a.lider = None, None, False
    a.save()
    messages.success(request, f'{a.modelo} desconectado. Para usar de novo, o garçom entra com o PIN e internet.')
    return redirect('painel:aparelhos')


# ------------------------------------------------------------------ relatórios

def resumo(bar, de, ate):
    ini, fim = inicio_do_dia(de), inicio_do_dia(ate + timedelta(days=1))
    comandas = Comanda.objects.filter(bar=bar, descartada=False, fechada_em__gte=ini, fechada_em__lt=fim)
    itens = itens_validos(bar).filter(comanda__in=comandas)
    faturado = comandas.aggregate(v=Sum('total_centavos'))['v'] or 0
    consumo = itens.aggregate(v=valor())['v'] or 0
    n = comandas.count()
    dias = {}
    for c in comandas.only('fechada_em', 'total_centavos'):
        h = timezone.localtime(c.fechada_em)
        d = (h - timedelta(hours=settings.INICIO_EXPEDIENTE)).date()
        x = dias.setdefault(d, [0, 0])
        x[0] += 1
        x[1] += c.total_centavos or 0
    return {
        'de': de, 'ate': ate, 'comandas': comandas.order_by('-fechada_em'), 'n': n,
        'faturado': faturado, 'consumo': consumo, 'servico': faturado - consumo,
        'ticket': faturado // n if n else 0,
        'por_produto': itens.values('categoria', 'produto', 'variante').annotate(quantidade=Sum('qtd'), valor=valor()).order_by('-valor'),
        'por_categoria': itens.values('categoria').annotate(quantidade=Sum('qtd'), valor=valor()).order_by('-valor'),
        'por_garcom': itens.values('pedido__garcom').annotate(quantidade=Sum('qtd'), valor=valor()).order_by('-valor'),
        'por_dia': sorted(dias.items()),
        'cancelados': Item.objects.filter(bar=bar, comanda__in=comandas, cancelado_em__isnull=False).select_related('comanda'),
        'forcadas': comandas.filter(fechada_por__contains='forçado'),
        'descartados': Pedido.objects.filter(bar=bar, comanda__in=comandas, situacao='descartado').count(),
    }


@gerente_requerido
def relatorio(request):
    hoje = dia_atual()
    atalho = request.GET.get('p')
    if atalho == 'ontem':
        de = ate = hoje - timedelta(days=1)
    elif atalho == '7':
        de, ate = hoje - timedelta(days=6), hoje
    elif atalho == 'mes':
        de, ate = hoje.replace(day=1), hoje
    else:
        de = ate = hoje
    form = PeriodoForm(request.GET if 'de' in request.GET else None, initial={'de': de, 'ate': ate})
    if form.is_bound and form.is_valid():
        de, ate = form.cleaned_data['de'], form.cleaned_data['ate']
        if ate < de:
            de, ate = ate, de
    r = resumo(request.bar, de, ate)
    if request.GET.get('formato') == 'csv':
        return _csv(request.bar, r)
    return render(request, 'painel/relatorio.html', {'form': form, 'r': r, 'query': request.GET.urlencode()})


def _csv(bar, r):
    buf = io.StringIO()
    w = csv.writer(buf, delimiter=';')
    w.writerow(['Categoria', 'Produto', 'Tamanho', 'Quantidade', 'Valor (R$)'])
    for x in r['por_produto']:
        w.writerow([x['categoria'], x['produto'], x['variante'], x['quantidade'], reais(x['valor'])])
    w.writerow([])
    w.writerow(['Comanda', 'Nome', 'Aberta', 'Fechada', 'Fechada por', 'Total (R$)'])
    for c in r['comandas']:
        w.writerow([c.numero, c.nome, timezone.localtime(c.aberta_em).strftime('%d/%m/%Y %H:%M'),
                    timezone.localtime(c.fechada_em).strftime('%d/%m/%Y %H:%M'), c.fechada_por, reais(c.total_centavos)])
    resp = HttpResponse('﻿' + buf.getvalue(), content_type='text/csv; charset=utf-8')
    resp['Content-Disposition'] = f'attachment; filename="{bar.slug}_{r["de"]}_{r["ate"]}.csv"'
    return resp


@gerente_requerido
def comanda(request, pk):
    c = get_object_or_404(Comanda, bar=request.bar, pk=pk)
    pedidos = c.pedidos.prefetch_related('itens').order_by('feito_em')
    return render(request, 'painel/comanda.html', {'c': c, 'pedidos': pedidos,
                                                   'consumo': itens_validos(request.bar).filter(comanda=c).aggregate(v=valor())['v'] or 0})


# ------------------------------------------------------------------ QR Code do cardápio

@gerente_requerido
def qr(request):
    return render(request, 'painel/qr.html', {'url': f'{settings.SITE_URL}/c/{request.bar.slug}'})


@gerente_requerido
def qr_svg(request):
    img = qrcode.make(f'{settings.SITE_URL}/c/{request.bar.slug}', image_factory=qrcode.image.svg.SvgPathImage, box_size=20)
    buf = io.BytesIO()
    img.save(buf)
    return HttpResponse(buf.getvalue(), content_type='image/svg+xml')
