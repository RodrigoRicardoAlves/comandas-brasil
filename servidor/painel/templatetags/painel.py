from django import template

register = template.Library()


@register.filter
def reais(centavos):
    """1234 -> "R$ 12,34" """
    if centavos is None:
        return '—'
    v = f'{abs(centavos) / 100:,.2f}'.replace(',', 'X').replace('.', ',').replace('X', '.')
    return f'{"-" if centavos < 0 else ""}R$ {v}'
