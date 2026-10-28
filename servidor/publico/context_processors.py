from django.conf import settings


def analytics(request):
    return {'GTM_ID': settings.GTM_ID}
