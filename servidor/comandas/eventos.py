"""Aplica eventos vindos dos celulares nas tabelas de leitura.

O mesmo contrato é seguido pelo app (lib/dados/eventos.dart). Regras:
- cada evento tem UUID; se já existe, é ignorado (reenvio);
- eventos que chegam fora de ordem (ex.: pedido antes da abertura) ficam guardados e
  são reaplicados quando o que faltava chegar.
"""
from datetime import datetime, timezone
from decimal import Decimal

from django.db import transaction

from .models import Comanda, Evento, Item, Pedido

TIPOS = {
    'comanda_aberta', 'comanda_editada', 'pedido_lancado', 'item_cancelado', 'conta_impressa',
    'comanda_fechada', 'comanda_reaberta', 'comanda_descartada', 'impresso', 'chamado_atendido',
    'comanda_juntada', 'pendencia_resolvida',
}


class EventoInvalido(Exception):
    pass


def ler_hora(v):
    """Aceita milissegundos desde 1970 ou texto ISO."""
    if isinstance(v, (int, float)):
        return datetime.fromtimestamp(v / 1000, tz=timezone.utc)
    try:
        h = datetime.fromisoformat(str(v).replace('Z', '+00:00'))
    except ValueError:
        raise EventoInvalido('hora inválida')
    return h if h.tzinfo else h.replace(tzinfo=timezone.utc)


def txt(v, n):
    return ' '.join(str(v or '').split())[:n]


def receber(bar, ev):
    """Grava e aplica um evento. Devolve (seq, novo?)."""
    uuid = txt(ev.get('uuid'), 36)
    tipo = ev.get('tipo')
    dados = ev.get('dados')
    if len(uuid) < 8 or tipo not in TIPOS or not isinstance(dados, dict):
        raise EventoInvalido(f'evento inválido: {uuid or "?"} {tipo}')
    with transaction.atomic():
        velho = Evento.objects.filter(uuid=uuid).first()
        if velho:
            if velho.bar_id != bar.id:
                raise EventoInvalido('evento de outro bar')
            return velho.id, False
        e = Evento.objects.create(bar=bar, uuid=uuid, tipo=tipo, device_id=txt(ev.get('device_id'), 64),
                                  usuario=txt(ev.get('usuario'), 40), hora=ler_hora(ev.get('hora')), dados=dados)
        aplicar(e)
    return e.id, True


def aplicar(e):
    f = APLICAR.get(e.tipo)
    if f:
        f(e, e.dados)


def _comanda(e, uuid):
    return Comanda.objects.filter(bar=e.bar, uuid=uuid).first()


def _aberta(e, d):
    Comanda.objects.get_or_create(bar=e.bar, uuid=txt(d.get('comanda'), 36), defaults=dict(
        numero=int(d.get('numero') or 0), nome=txt(d.get('nome'), 40), aberta_em=e.hora, aberta_por=e.usuario))
    reaplicar_pendentes(e.bar)


def _editada(e, d):
    Comanda.objects.filter(bar=e.bar, uuid=d.get('comanda')).update(
        numero=int(d.get('numero') or 0), nome=txt(d.get('nome'), 40))


def _pedido(e, d):
    c = _comanda(e, d.get('comanda'))
    if not c:
        return  # a abertura ainda não chegou; reaplicar_pendentes cuida
    for _ in range(10):  # comanda juntada a outra: o pedido vai para a que ficou
        prox = _comanda(e, c.juntada_para) if c.juntada_para else None
        if not prox:
            break
        c = prox
    uuid = txt(d.get('pedido'), 36)
    # chegou depois do fechamento e quem fechou não conhecia: espera o gerente
    atrasado = c.fechada_em is not None and c.conhecidos is not None and uuid not in c.conhecidos
    p, novo = Pedido.objects.get_or_create(bar=e.bar, uuid=uuid, defaults=dict(
        comanda=c, feito_em=e.hora, garcom=e.usuario, offline=bool(d.get('offline')),
        situacao='pendente' if atrasado else ''))
    if not novo:
        return
    for it in d.get('itens') or []:
        Item.objects.create(
            bar=e.bar, uuid=txt(it.get('item'), 36), pedido=p, comanda=c, variante_id=it.get('variante_id'),
            categoria=txt(it.get('categoria'), 40), produto=txt(it.get('produto'), 60),
            variante=txt(it.get('variante'), 40), setor=txt(it.get('setor'), 40), imprime=bool(it.get('imprime')),
            preco_centavos=int(it.get('preco') or 0), qtd=max(1, int(it.get('qtd') or 1)), obs=txt(it.get('obs'), 80))
    # a decisão do gerente pode ter chegado antes do próprio pedido
    r = Evento.objects.filter(bar=e.bar, tipo='pendencia_resolvida', dados__pedido=uuid).order_by('-id').first()
    if r:
        _resolvida(r, r.dados)


def _cancelado(e, d):
    quem = e.usuario + (f" (autorizado por {d['autorizado_por']})" if d.get('autorizado_por') else '')
    Item.objects.filter(bar=e.bar, uuid=d.get('item'), cancelado_em=None).update(
        cancelado_em=e.hora, cancelado_por=quem[:60])


def _fechada(e, d):
    quem = e.usuario
    if d.get('forcado'):
        quem += f" (forçado por {d['autorizado_por']})" if d.get('autorizado_por') else ' (forçado)'
    conhecidos = [str(x) for x in d['pedidos']] if isinstance(d.get('pedidos'), list) else None
    c = _comanda(e, d.get('comanda'))
    if not c:
        return
    Comanda.objects.filter(pk=c.pk).update(
        fechada_em=e.hora, fechada_por=quem[:60], taxa_servico=Decimal(str(d.get('taxa_servico') or 0)),
        total_centavos=int(d.get('total') or 0), conhecidos=conhecidos)
    if conhecidos is not None:
        # pedidos que já estavam aqui mas quem fechou não via (chegaram por outro caminho)
        Pedido.objects.filter(comanda=c, situacao='').exclude(uuid__in=conhecidos).exclude(
            uuid__in=_resolvidos(e.bar)).update(situacao='pendente')


def _resolvidos(bar):
    return [x for x in Evento.objects.filter(bar=bar, tipo='pendencia_resolvida').values_list('dados__pedido', flat=True)]


def _reaberta(e, d):
    c = _comanda(e, d.get('comanda'))
    if not c:
        return
    Comanda.objects.filter(pk=c.pk).update(fechada_em=None, fechada_por='', total_centavos=None, conhecidos=None)
    Pedido.objects.filter(comanda=c, situacao='pendente').update(situacao='')


def _juntada(e, d):
    """Conflito de número resolvido juntando: pedidos de `comanda` passam para `para`."""
    de, para = _comanda(e, d.get('comanda')), _comanda(e, d.get('para'))
    if not de or not para or de.pk == para.pk:
        return
    Pedido.objects.filter(comanda=de).update(comanda=para)
    Item.objects.filter(comanda=de).update(comanda=para)
    Comanda.objects.filter(pk=de.pk).update(descartada=True, juntada_para=para.uuid)


def _resolvida(e, d):
    """Gerente decidiu sobre um pedido atrasado: mover para outra comanda ou descartar."""
    p = Pedido.objects.filter(bar=e.bar, uuid=d.get('pedido')).first()
    if not p:
        return  # o pedido ainda não chegou; _pedido aplica quando chegar
    if d.get('acao') == 'descartar':
        Pedido.objects.filter(pk=p.pk).update(situacao='descartado')
    elif d.get('acao') == 'mover':
        para = _comanda(e, d.get('para'))
        if para:
            Pedido.objects.filter(pk=p.pk).update(comanda=para, situacao='')
            Item.objects.filter(pedido=p).update(comanda=para)


def _descartada(e, d):
    Comanda.objects.filter(bar=e.bar, uuid=d.get('comanda')).update(descartada=True)


APLICAR = {
    'comanda_aberta': _aberta, 'comanda_editada': _editada, 'pedido_lancado': _pedido,
    'item_cancelado': _cancelado, 'comanda_fechada': _fechada, 'comanda_reaberta': _reaberta,
    'comanda_descartada': _descartada, 'comanda_juntada': _juntada, 'pendencia_resolvida': _resolvida,
}


def reaplicar_pendentes(bar):
    """Pedidos cuja comanda ainda não existia quando chegaram."""
    feitos = set(Pedido.objects.filter(bar=bar).values_list('uuid', flat=True))
    for e in Evento.objects.filter(bar=bar, tipo='pedido_lancado').order_by('-id')[:500]:
        if e.dados.get('pedido') not in feitos:
            _pedido(e, e.dados)
