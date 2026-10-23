"""Tarefas agendadas (django-q2) do app contas."""
from datetime import timedelta

from django.db import transaction
from django.db.models import Q
from django.utils import timezone

from .models import Aparelho, AparelhoArquivado

PARADO = timedelta(hours=24)


def arquivar_aparelhos_parados():
    """Move para a tabela morta os celulares sem contato há mais de 24 h e sem pedido pendente.
    Se o celular voltar, o login cria o registro de novo (o garçom só digita o PIN outra vez)."""
    corte = timezone.now() - PARADO
    parados = Aparelho.objects.filter(pendentes=0).filter(
        Q(ultimo_contato__lt=corte) | Q(ultimo_contato__isnull=True, criado_em__lt=corte))
    with transaction.atomic():
        lista = list(parados.select_for_update())
        AparelhoArquivado.objects.bulk_create([
            AparelhoArquivado(aparelho_id=a.pk, bar_id=a.bar_id, device_id=a.device_id, modelo=a.modelo,
                              usuario_id=a.usuario_id, versao_app=a.versao_app, ultimo_contato=a.ultimo_contato,
                              ip_local=a.ip_local, bateria=a.bateria, criado_em=a.criado_em)
            for a in lista])
        Aparelho.objects.filter(pk__in=[a.pk for a in lista]).delete()
    return f'{len(lista)} aparelho(s) arquivado(s)'
