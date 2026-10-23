"""Cadastra no django-q2 a tarefa que arquiva celulares parados (roda de hora em hora)."""
from django.db import migrations
from django.utils import timezone

FUNCAO = 'contas.tarefas.arquivar_aparelhos_parados'


def criar(apps, schema_editor):
    Schedule = apps.get_model('django_q', 'Schedule')
    Schedule.objects.update_or_create(
        func=FUNCAO,
        defaults={'name': 'Arquivar celulares parados', 'schedule_type': 'H', 'repeats': -1,
                  'next_run': timezone.now()})


def apagar(apps, schema_editor):
    apps.get_model('django_q', 'Schedule').objects.filter(func=FUNCAO).delete()


class Migration(migrations.Migration):
    dependencies = [
        ('contas', '0002_aparelho_arquivado'),
        ('django_q', '0019_alter_task_options_alter_ormq_key_alter_ormq_lock_and_more'),
    ]
    operations = [migrations.RunPython(criar, apagar)]
