"""Formulários do painel do gerente. Todo queryset de escolha é filtrado pelo bar do gerente."""
from decimal import Decimal, InvalidOperation

from django import forms
from django.forms import inlineformset_factory

from bares.models import Bar
from cardapio.models import Categoria, Produto, Setor, Variante
from contas.models import Usuario


def para_centavos(texto):
    t = str(texto or '').strip().replace('R$', '').replace(' ', '')
    if ',' in t:
        t = t.replace('.', '').replace(',', '.')  # 1.234,50 -> 1234.50
    try:
        v = Decimal(t)
    except InvalidOperation:
        raise forms.ValidationError('Valor inválido. Use por exemplo 12,50')
    if v < 0 or v > 100000:
        raise forms.ValidationError('Valor fora do normal')
    return int((v * 100).quantize(Decimal('1')))


def reais(centavos):
    return f'{centavos / 100:.2f}'.replace('.', ',') if centavos is not None else ''


class CampoReais(forms.CharField):
    def __init__(self, **kw):
        kw.setdefault('widget', forms.TextInput(attrs={'inputmode': 'decimal', 'placeholder': '0,00', 'size': 8}))
        super().__init__(**kw)

    def clean(self, value):
        value = super().clean(value)
        return None if value in (None, '') else para_centavos(value)


class EntrarForm(forms.Form):
    bar = forms.CharField(label='Código do bar', max_length=50)
    pin = forms.CharField(label='PIN de gerente', max_length=8, widget=forms.PasswordInput(attrs={'inputmode': 'numeric'}))


class BarForm(forms.ModelForm):
    class Meta:
        model = Bar
        fields = ['nome', 'rodape', 'taxa_servico', 'max_comanda', 'impressora', 'colunas_papel', 'codificacao', 'cortar_papel']


class SetorForm(forms.ModelForm):
    class Meta:
        model = Setor
        fields = ['nome', 'impressora', 'ordem']


class CategoriaForm(forms.ModelForm):
    class Meta:
        model = Categoria
        fields = ['nome', 'ordem', 'ativa']


class ProdutoForm(forms.ModelForm):
    class Meta:
        model = Produto
        fields = ['categoria', 'nome', 'descricao', 'foto', 'ordem', 'ativo', 'esgotado', 'imprime', 'setor']
        labels = {'imprime': 'Imprime cupom', 'esgotado': 'Esgotado (some do cardápio)'}

    def __init__(self, *a, bar, **kw):
        super().__init__(*a, **kw)
        self.fields['categoria'].queryset = Categoria.objects.filter(bar=bar)
        self.fields['setor'].queryset = Setor.objects.filter(bar=bar)
        self.fields['setor'].required = False


class VarianteForm(forms.ModelForm):
    preco = CampoReais(label='Preço (R$)')

    class Meta:
        model = Variante
        fields = ['nome', 'ordem']
        labels = {'nome': 'Tamanho/tipo (vazio = preço único)'}

    def __init__(self, *a, **kw):
        super().__init__(*a, **kw)
        if self.instance.pk:
            self.fields['preco'].initial = reais(self.instance.preco_centavos)
        self.fields['ordem'].required = False

    def clean(self):
        d = super().clean()
        if not self.cleaned_data.get('DELETE') and d.get('preco') is None and (d.get('nome') or self.instance.pk):
            self.add_error('preco', 'Informe o preço')
        return d

    def save(self, commit=True):
        self.instance.preco_centavos = self.cleaned_data['preco']
        self.instance.ordem = self.cleaned_data.get('ordem') or 0
        return super().save(commit)


Variantes = inlineformset_factory(Produto, Variante, form=VarianteForm, extra=2, can_delete=True)


class UsuarioForm(forms.ModelForm):
    pin = forms.CharField(label='PIN (4 a 8 números)', required=False, max_length=8,
                          widget=forms.PasswordInput(render_value=False,
                              attrs={'inputmode': 'numeric', 'autocomplete': 'new-password'}))

    class Meta:
        model = Usuario
        fields = ['nome', 'papel', 'ativo']

    def __init__(self, *a, **kw):
        super().__init__(*a, **kw)
        if self.instance.pk:
            self.fields['pin'].help_text = 'Deixe vazio para manter o PIN atual'
        else:
            self.fields['pin'].required = True

    def clean_pin(self):
        pin = self.cleaned_data['pin'].strip()
        if not pin:
            return ''
        try:
            self.instance.definir_pin(pin)
        except ValueError as e:
            raise forms.ValidationError(str(e))
        outro = Usuario.objects.filter(bar=self.instance.bar, pin_hash=self.instance.pin_hash).exclude(pk=self.instance.pk)
        if outro.exists():
            raise forms.ValidationError('Este PIN já é de outra pessoa do bar. Escolha outro.')
        return pin


class PeriodoForm(forms.Form):
    de = forms.DateField(label='De', widget=forms.DateInput(attrs={'type': 'date'}, format='%Y-%m-%d'))
    ate = forms.DateField(label='Até', widget=forms.DateInput(attrs={'type': 'date'}, format='%Y-%m-%d'))
