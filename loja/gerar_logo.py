"""Gera o logo "Comandas Brasil" (estilo letreiro de cinema americano antigo).
Uso: .venv/bin/python loja/gerar_logo.py   → loja/logo*.png e cópias usadas pelo app e pelo site."""
import math
import random
from pathlib import Path

from PIL import Image, ImageDraw, ImageFilter, ImageFont

AQUI = Path(__file__).parent
F_SCRIPT = str(AQUI / 'fontes' / 'Lobster-Regular.ttf')
F_BLOCO = str(AQUI / 'fontes' / 'BebasNeue-Regular.ttf')
MARINHO = (30, 58, 95)
MARINHO_ESC = (18, 34, 58)
CREME = (243, 230, 200)
VERMELHO = (200, 55, 45)
VERMELHO_ESC = (120, 28, 24)
AMARELO = (242, 179, 61)
LAMPADAS = []  # posições (o desgaste "queima" algumas)


def estrela(d, cx, cy, r, cor):
    pts = []
    for i in range(8):
        ang = math.pi / 4 * i - math.pi / 2
        rr = r if i % 2 == 0 else r * 0.28
        pts.append((cx + rr * math.cos(ang), cy + rr * math.sin(ang)))
    d.polygon(pts, fill=cor)


def texto_3d(im, xy, txt, fonte, prof, cor, contorno, sombra, borda):
    """Letra com contorno e "extrusão" diagonal, como nos letreiros dos anos 50."""
    d = ImageDraw.Draw(im)
    x, y = xy
    for k in range(prof, 0, -1):
        d.text((x + k, y + k), txt, font=fonte, fill=sombra, stroke_width=borda, stroke_fill=sombra, anchor='mm')
    d.text((x, y), txt, font=fonte, fill=cor, stroke_width=borda, stroke_fill=contorno, anchor='mm')


def logo(L=1600, A=900):
    im = Image.new('RGBA', (L, A), (0, 0, 0, 0))
    d = ImageDraw.Draw(im)
    m = 40
    # moldura: sombra, borda amarela, painel marinho
    d.rounded_rectangle([m + 18, m + 22, L - m + 18, A - 150 + 22], radius=70, fill=(0, 0, 0, 90))
    d.rounded_rectangle([m, m, L - m, A - 150], radius=70, fill=AMARELO)
    d.rounded_rectangle([m + 22, m + 22, L - m - 22, A - 150 - 22], radius=54, fill=MARINHO)
    # lâmpadas na borda
    x0, y0, x1, y1 = m + 11, m + 11, L - m - 11, A - 150 - 11
    lampadas = LAMPADAS
    lampadas.clear()
    passo = 62
    for x in range(int(x0 + 70), int(x1 - 60), passo):
        lampadas += [(x, y0), (x, y1)]
    for y in range(int(y0 + 70), int(y1 - 60), passo):
        lampadas += [(x0, y), (x1, y)]
    brilho = Image.new('RGBA', im.size, (0, 0, 0, 0))
    db = ImageDraw.Draw(brilho)
    for (x, y) in lampadas:
        db.ellipse([x - 22, y - 22, x + 22, y + 22], fill=(255, 230, 150, 120))
    im.alpha_composite(brilho.filter(ImageFilter.GaussianBlur(10)))
    for (x, y) in lampadas:
        d.ellipse([x - 9, y - 9, x + 9, y + 9], fill=(255, 244, 205))
    # raios de fundo (luz de holofote)
    cx, cy = L / 2, (A - 150) / 2 + 10
    raios = Image.new('RGBA', im.size, (0, 0, 0, 0))
    dr = ImageDraw.Draw(raios)
    for i in range(18):
        a0 = i * 2 * math.pi / 18
        a1 = a0 + math.pi / 36
        dr.polygon([(cx, cy), (cx + 1400 * math.cos(a0), cy + 1400 * math.sin(a0)),
                    (cx + 1400 * math.cos(a1), cy + 1400 * math.sin(a1))], fill=(255, 255, 255, 14))
    mascara = Image.new('L', im.size, 0)
    ImageDraw.Draw(mascara).rounded_rectangle([m + 22, m + 22, L - m - 22, A - 150 - 22], radius=54, fill=255)
    im.paste(Image.alpha_composite(im, raios), (0, 0), mascara)
    d = ImageDraw.Draw(im)
    # estrelinhas
    for (sx, sy, r) in [(190, 170, 34), (270, 250, 18), (1410, 170, 34), (1330, 250, 18), (215, 600, 20), (1385, 600, 20)]:
        estrela(d, sx, sy, r, CREME)
    # "Comandas" em letra cursiva
    f = ImageFont.truetype(F_SCRIPT, 300)
    texto_3d(im, (cx - 6, cy - 30), 'Comandas', f, 18, VERMELHO, CREME, MARINHO_ESC, 12)
    # faixa "BRASIL"
    d = ImageDraw.Draw(im)
    fy0, fy1 = A - 205, A - 40
    fx0, fx1 = 330, L - 330
    for (a, b, c) in [((fx0 - 90, fy0 + 30), (fx0 + 10, fy0 + 30), (fx0 - 50, (fy0 + fy1) / 2 + 30)),
                      ((fx1 + 90, fy0 + 30), (fx1 - 10, fy0 + 30), (fx1 + 50, (fy0 + fy1) / 2 + 30))]:
        pass
    # pontas da faixa
    d.polygon([(fx0 - 110, fy0 + 35), (fx0 + 20, fy0 + 35), (fx0 + 20, fy1 + 15), (fx0 - 110, fy1 + 15), (fx0 - 60, (fy0 + fy1) / 2 + 25)], fill=VERMELHO_ESC)
    d.polygon([(fx1 + 110, fy0 + 35), (fx1 - 20, fy0 + 35), (fx1 - 20, fy1 + 15), (fx1 + 110, fy1 + 15), (fx1 + 60, (fy0 + fy1) / 2 + 25)], fill=VERMELHO_ESC)
    d.rounded_rectangle([fx0 + 6, fy0 + 6, fx1 + 6, fy1 + 6], radius=14, fill=(0, 0, 0, 90))
    d.rounded_rectangle([fx0, fy0, fx1, fy1], radius=14, fill=VERMELHO, outline=CREME, width=8)
    fb = ImageFont.truetype(F_BLOCO, 150)
    d.text((L / 2 + 5, (fy0 + fy1) / 2 + 9), 'B R A S I L', font=fb, fill=MARINHO_ESC, anchor='mm')
    d.text((L / 2, (fy0 + fy1) / 2 + 4), 'B R A S I L', font=fb, fill=CREME, anchor='mm')
    for sx in (fx0 + 70, fx1 - 70):
        estrela(d, sx, (fy0 + fy1) / 2, 30, AMARELO)
    return envelhecer(desgastar(im), forca=34)


def desgastar(im, semente=11):
    """Marcas do tempo: parafusos com ferrugem escorrendo, tinta descascada, arranhões,
    sujeira nas bordas, sol amarelando e lâmpadas queimadas."""
    rnd = random.Random(semente)
    L, A = im.size
    alfa = im.getchannel('A')
    placa = alfa.point(lambda v: 255 if v > 200 else 0)

    def so_na_placa(camada):
        vazio = Image.new('RGBA', im.size, (0, 0, 0, 0))
        return Image.composite(camada, vazio, placa)

    # 1) sol: dessatura um pouco e puxa para o amarelado
    rgb = im.convert('RGB')
    cinza = rgb.convert('L').convert('RGB')
    rgb = Image.blend(rgb, cinza, 0.18)
    sepia = Image.new('RGB', im.size, (226, 196, 140))
    rgb = Image.blend(rgb, sepia, 0.10)
    im = Image.merge('RGBA', (*rgb.split(), alfa))

    # 2) sujeira acumulada nas bordas (escurece por fora, limpo no meio)
    borda = Image.new('L', im.size, 0)
    ImageDraw.Draw(borda).rounded_rectangle([90, 90, L - 90, A - 240], radius=60, fill=255)
    borda = borda.filter(ImageFilter.GaussianBlur(70))
    sujo = Image.new('RGBA', im.size, (60, 40, 20, 0))
    painel = Image.new('L', im.size, 0)
    ImageDraw.Draw(painel).rounded_rectangle([62, 62, L - 62, A - 172], radius=54, fill=255)
    sujo.putalpha(Image.composite(borda.point(lambda v: int((255 - v) * 0.38)), Image.new('L', im.size, 0), painel))
    im = Image.alpha_composite(im, sujo)

    # 3) manchas de ferrugem espalhadas
    ferr = Image.new('RGBA', im.size, (0, 0, 0, 0))
    df = ImageDraw.Draw(ferr)
    for _ in range(26):
        lado = rnd.choice('cbed')
        if lado in 'cb':
            x, y = rnd.uniform(60, L - 60), (rnd.uniform(55, 110) if lado == 'c' else rnd.uniform(A - 230, A - 170))
        else:
            x, y = (rnd.uniform(55, 120) if lado == 'e' else rnd.uniform(L - 120, L - 55)), rnd.uniform(60, A - 180)
        for _ in range(rnd.randint(2, 5)):  # mancha irregular = várias bolhas juntas
            r = rnd.uniform(5, 18)
            ox, oy = rnd.uniform(-14, 14), rnd.uniform(-10, 10)
            df.ellipse([x + ox - r, y + oy - r * 0.7, x + ox + r, y + oy + r * 0.7],
                       fill=(rnd.randint(120, 160), rnd.randint(55, 75), rnd.randint(20, 35), rnd.randint(60, 120)))
    im = Image.alpha_composite(im, so_na_placa(ferr.filter(ImageFilter.GaussianBlur(4))))

    # 4) tinta descascada: lascas mostrando o metal por baixo
    d = ImageDraw.Draw(im)
    for _ in range(60):
        x, y = rnd.uniform(50, L - 50), rnd.uniform(50, A - 60)
        if placa.getpixel((int(x), int(y))) == 0:
            continue
        dist = min(x - 40, L - 40 - x, y - 40, abs(y - (A - 150)), abs(y - (A - 205)))
        if dist > 70 and rnd.random() < 0.9:
            continue
        r = rnd.uniform(3, 12) if dist > 70 else rnd.uniform(5, 20)
        pts = [(x + r * rnd.uniform(0.5, 1.3) * math.cos(t), y + r * rnd.uniform(0.5, 1.3) * math.sin(t))
               for t in [i * 2 * math.pi / 7 for i in range(7)]]
        d.polygon([(px + 2, py + 2) for px, py in pts], fill=(40, 30, 22, 160))  # sombra da borda da lasca
        d.polygon(pts, fill=(rnd.randint(150, 175), rnd.randint(148, 165), rnd.randint(135, 150), 255))

    # 5) arranhões finos
    arr = Image.new('RGBA', im.size, (0, 0, 0, 0))
    da = ImageDraw.Draw(arr)
    for _ in range(45):
        x, y = rnd.uniform(60, L - 60), rnd.uniform(60, A - 100)
        ang = rnd.uniform(-0.6, 0.6) + (math.pi if rnd.random() < 0.5 else 0)
        comp = rnd.uniform(25, 140)
        da.line([(x, y), (x + comp * math.cos(ang), y + comp * math.sin(ang))],
                fill=(255, 245, 225, rnd.randint(25, 70)), width=rnd.choice([1, 1, 2]))
    im = Image.alpha_composite(im, so_na_placa(arr))

    # 6) parafusos com ferrugem escorrendo
    escorrido = Image.new('RGBA', im.size, (0, 0, 0, 0))
    de = ImageDraw.Draw(escorrido)
    parafusos = [(115, 115), (L - 115, 115), (115, A - 225), (L - 115, A - 225)]
    for (x, y) in parafusos:
        for k in range(3):
            dx = rnd.uniform(-10, 10)
            comp = rnd.uniform(60, 150)
            de.line([(x + dx, y), (x + dx * 1.4, y + comp)], fill=(120, 55, 25, 130), width=rnd.randint(5, 11))
        de.ellipse([x - 26, y - 26, x + 26, y + 26], fill=(130, 60, 25, 150))
    im = Image.alpha_composite(im, so_na_placa(escorrido.filter(ImageFilter.GaussianBlur(5))))
    d = ImageDraw.Draw(im)
    for (x, y) in parafusos:
        d.ellipse([x - 15, y - 15, x + 15, y + 15], fill=(120, 116, 108), outline=(60, 50, 40), width=3)
        a = rnd.uniform(0, math.pi)
        d.line([(x - 10 * math.cos(a), y - 10 * math.sin(a)), (x + 10 * math.cos(a), y + 10 * math.sin(a))],
               fill=(45, 38, 30), width=4)
        d.ellipse([x - 6, y - 12, x + 2, y - 6], fill=(200, 196, 185))  # brilho

    # 7) algumas lâmpadas queimadas
    for (x, y) in rnd.sample(LAMPADAS, k=min(5, len(LAMPADAS))):
        d.ellipse([x - 10, y - 10, x + 10, y + 10], fill=(92, 80, 60), outline=(50, 42, 30), width=2)
    im.putalpha(alfa)
    return im


def envelhecer(im, forca=26):
    """Grão de filme e leve desgaste, só onde há desenho."""
    random.seed(7)
    ruido = Image.effect_noise(im.size, forca).convert('L')
    grao = Image.merge('RGBA', [ruido, ruido, ruido, Image.new('L', im.size, 22)])
    alfa = im.getchannel('A')
    saida = Image.alpha_composite(im, Image.composite(grao, Image.new('RGBA', im.size, (0, 0, 0, 0)), alfa))
    saida.putalpha(alfa)
    return saida


if __name__ == '__main__':
    g = logo()
    g.save(AQUI / 'logo.png')
    g.resize((800, 450), Image.LANCZOS).save(AQUI / 'logo-800.png')
    g.resize((400, 225), Image.LANCZOS).save(AQUI / 'logo-400.png')
    # usado no app (tela de entrada) e nas páginas do site
    raiz = AQUI.parent
    (raiz / 'app' / 'assets').mkdir(exist_ok=True)
    g.resize((800, 450), Image.LANCZOS).save(raiz / 'app' / 'assets' / 'logo.png')
    estat = raiz / 'servidor' / 'publico' / 'static' / 'publico'
    estat.mkdir(parents=True, exist_ok=True)
    g.resize((800, 450), Image.LANCZOS).save(estat / 'logo.png')
    print('ok')
