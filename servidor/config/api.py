"""API dos celulares (/api/v1/...).

Toda rota autenticada recebe o aparelho logado em `request.auth`, e TODA consulta é
filtrada por `request.auth.bar` — é isso que impede um bar de ver os dados do outro.
"""
import time
from datetime import timedelta

from django.db.models import Prefetch
from django.utils import timezone
from ninja import NinjaAPI, Schema
from ninja.errors import HttpError
from ninja.security import HttpBearer

from bares.models import Bar
from cardapio.models import Categoria, Produto
from comandas.eventos import EventoInvalido, receber
from comandas.models import Evento
from contas.models import Aparelho, Usuario, hash_pin
from publico.models import Chamado

ONLINE_SEGUNDOS = 30  # aparelho sem presença há mais que isso = sem internet
OCUPADO_SEGUNDOS = 120  # garçom ativo em outro celular há menos que isso: não deixa entrar em um segundo


class TokenAparelho(HttpBearer):
    def authenticate(self, request, token):
        ap = (Aparelho.objects.select_related('bar', 'usuario')
              .filter(token=token, usuario__isnull=False, usuario__ativo=True, bar__ativo=True).first())
        return ap


api = NinjaAPI(title='Comandas', version='1', auth=TokenAparelho(), urls_namespace='api')


# ------------------------------------------------------------------ login

_tentativas = {}  # ip -> [horários]  (contra adivinhar PIN)


def _limitar(ip):
    agora = time.time()
    t = [x for x in _tentativas.get(ip, []) if agora - x < 300]
    if len(t) >= 15:
        raise HttpError(429, 'Muitas tentativas. Aguarde alguns minutos.')
    t.append(agora)
    _tentativas[ip] = t


class LoginIn(Schema):
    bar: str
    pin: str
    device_id: str
    modelo: str = ''
    versao_app: str = ''


def usuario_dict(u):
    return {'id': u.id, 'nome': u.nome, 'papel': u.papel}


def bar_dict(b):
    return {'id': b.id, 'nome': b.nome, 'slug': b.slug, 'rodape': b.rodape, 'colunas_papel': b.colunas_papel,
            'codificacao': b.codificacao, 'cortar_papel': b.cortar_papel, 'taxa_servico': float(b.taxa_servico),
            'max_comanda': b.max_comanda, 'impressora': b.impressora, 'versao_cardapio': b.versao_cardapio}


@api.post('/login', auth=None)
def login(request, d: LoginIn):
    _limitar(request.META.get('REMOTE_ADDR', ''))
    bar = Bar.objects.filter(slug=d.bar.strip().lower(), ativo=True).first()
    if not bar:
        raise HttpError(404, 'Bar não encontrado. Confira o código do bar.')
    u = Usuario.objects.filter(bar=bar, ativo=True, pin_hash=hash_pin(bar, d.pin.strip())).first()
    if not u:
        raise HttpError(401, 'PIN incorreto')
    # o mesmo garçom não pode estar em dois celulares ao mesmo tempo
    outros = Aparelho.objects.filter(bar=bar, usuario=u, token__isnull=False).exclude(device_id=d.device_id[:64])
    ativo = outros.filter(ultimo_contato__gte=timezone.now() - timedelta(seconds=OCUPADO_SEGUNDOS)).first()
    if ativo:
        raise HttpError(409, f'{u.nome} já está usando outro celular ({ativo.modelo or "sem nome"}). '
                             'Encerre o turno nele ou peça ao gerente para desconectá-lo.')
    outros.update(token=None, usuario=None, lider=False)  # celular desligado/sumido: a sessão velha cai
    ap, _ = Aparelho.objects.get_or_create(bar=bar, device_id=d.device_id[:64])
    ap.usuario = u
    ap.modelo = d.modelo[:80]
    ap.versao_app = d.versao_app[:20]
    ap.ultimo_contato = timezone.now()
    ap.novo_token()
    ap.save()
    return {'token': ap.token, 'usuario': usuario_dict(u), 'bar': bar_dict(bar), 'lan_key': bar.lan_key}


@api.post('/logout')
def logout(request):
    ap = request.auth
    ap.token = None
    ap.usuario = None
    ap.lider = False
    ap.pendentes = 0
    ap.save()
    return {'ok': True}


# ------------------------------------------------------------------ dados para trabalhar offline

def cardapio_do_bar(bar, publico=False):
    prods = Produto.objects.filter(ativo=True).select_related('setor').prefetch_related('variantes')
    if publico:
        prods = prods.filter(esgotado=False)
    cats = (Categoria.objects.filter(bar=bar, ativa=True)
            .prefetch_related(Prefetch('produtos', queryset=prods)))
    out = []
    for c in cats:
        ps = []
        for p in c.produtos.all():
            vs = [{'id': v.id, 'nome': v.nome, 'preco': v.preco_centavos} for v in p.variantes.all()]
            if not vs:
                continue
            item = {'id': p.id, 'nome': p.nome, 'descricao': p.descricao,
                    'foto': p.foto.url if p.foto else None, 'variantes': vs}
            if not publico:
                item.update(esgotado=p.esgotado, imprime=p.imprime and p.setor_id is not None,
                            setor=p.setor.nome if p.setor else '')
            ps.append(item)
        if ps:
            out.append({'id': c.id, 'nome': c.nome, 'produtos': ps})
    return out


@api.get('/bootstrap')
def bootstrap(request):
    """Tudo que o celular precisa guardar para funcionar sem internet."""
    bar = request.auth.bar
    return {
        'bar': bar_dict(bar),
        'lan_key': bar.lan_key,
        'pin_salt': bar.pin_salt,
        'usuarios': [{**usuario_dict(u), 'pin_hash': u.pin_hash} for u in bar.usuarios.filter(ativo=True)],
        'setores': [{'id': s.id, 'nome': s.nome, 'impressora': s.impressora} for s in bar.setores.all()],
        'cardapio': cardapio_do_bar(bar),
    }


# ------------------------------------------------------------------ eventos

class EventosIn(Schema):
    eventos: list[dict]


@api.post('/eventos')
def enviar_eventos(request, d: EventosIn):
    bar = request.auth.bar
    aceitos, erros = [], []
    for ev in d.eventos[:500]:
        try:
            seq, _ = receber(bar, ev)
            aceitos.append({'uuid': ev.get('uuid'), 'seq': seq})
        except (EventoInvalido, ValueError, TypeError) as e:
            erros.append({'uuid': ev.get('uuid'), 'erro': str(e)})
    return {'aceitos': aceitos, 'erros': erros}


@api.get('/eventos')
def baixar_eventos(request, desde: int = 0):
    """Eventos recentes do bar (para um celular que acabou de chegar se atualizar)."""
    limite = timezone.now() - timedelta(hours=36)
    evs = Evento.objects.filter(bar=request.auth.bar, id__gt=desde, recebido_em__gte=limite).order_by('id')[:2000]
    return {'eventos': [e.como_dict() for e in evs]}


# ------------------------------------------------------------------ presença e chamados

class PresencaIn(Schema):
    ip: str = ''
    porta: int | None = None
    bateria: int | None = None
    carregando: bool = False
    lider: bool = False
    pendentes: int = 0


@api.post('/presenca')
def presenca(request, d: PresencaIn):
    ap = request.auth
    ap.ultimo_contato = timezone.now()
    ap.ip_local = d.ip[:45]
    ap.porta_local = d.porta
    ap.bateria = d.bateria
    ap.carregando = d.carregando
    ap.lider = d.lider
    ap.pendentes = max(0, d.pendentes)
    ap.save()
    corte = timezone.now() - timedelta(seconds=ONLINE_SEGUNDOS)
    outros = (Aparelho.objects.filter(bar=ap.bar, usuario__isnull=False, ultimo_contato__gte=corte)
              .select_related('usuario'))
    chamados = Chamado.objects.filter(bar=ap.bar, atendido_em=None,
                                      criado_em__gte=timezone.now() - timedelta(hours=2)).order_by('id')
    return {
        'agora': timezone.now().isoformat(),
        'versao_cardapio': Bar.objects.values_list('versao_cardapio', flat=True).get(pk=ap.bar_id),
        'aparelhos': [{'device_id': o.device_id, 'modelo': o.modelo, 'usuario': o.usuario.nome,
                       'usuario_id': o.usuario_id, 'ip': o.ip_local,
                       'porta': o.porta_local, 'bateria': o.bateria, 'carregando': o.carregando, 'lider': o.lider,
                       'pendentes': o.pendentes} for o in outros],
        'chamados': [c.como_dict() for c in chamados],
    }


@api.post('/chamados/{cid}/impresso')
def chamado_impresso(request, cid: int):
    Chamado.objects.filter(bar=request.auth.bar, id=cid).update(impresso=True)
    return {'ok': True}


@api.post('/chamados/{cid}/atendido')
def chamado_atendido(request, cid: int):
    Chamado.objects.filter(bar=request.auth.bar, id=cid, atendido_em=None).update(
        atendido_em=timezone.now(), atendido_por=request.auth.usuario.nome)
    return {'ok': True}
