#!/usr/bin/env python3
"""Impressora térmica de mentira: escuta na porta 9100 (como uma impressora de rede ESC/POS),
mostra cada cupom no terminal e guarda uma cópia em cupons/AAAA-MM-DD_HH-MM-SS.txt.

Uso:  python tools/impressora_fake.py [porta] [colunas]
No app, configure a impressora como  IP_DO_PC:9100
"""
import os
import socket
import sys
import threading
from datetime import datetime

PORTA = int(sys.argv[1]) if len(sys.argv) > 1 else 9100
COLS = int(sys.argv[2]) if len(sys.argv) > 2 else 48
PASTA = os.path.join(os.path.dirname(os.path.abspath(__file__)), '..', '..', 'cupons')
CODIF = {0: 'cp437', 2: 'cp850', 3: 'cp860', 16: 'cp1252'}


def interpretar(dados):
    """Converte bytes ESC/POS em linhas de texto. Negrito vira *texto*, fonte grande vira LETRAS ESPAÇADAS."""
    linhas, atual = [], ''
    alinhar, negrito, largo, alto, cod = 'e', False, 1, 1, 'cp437'
    cortes = 0
    i, n = 0, len(dados)

    def fecha():
        nonlocal atual
        txt = atual
        if largo > 1:
            txt = ' '.join(txt)
        if negrito and txt.strip():
            txt = f'*{txt}*'
        if alinhar == 'c':
            txt = txt.center(COLS)
        elif alinhar == 'd':
            txt = txt.rjust(COLS)
        linhas.append(txt.rstrip())
        if alto > 1:
            linhas.append('')
        atual = ''

    while i < n:
        b = dados[i]
        if b == 0x1B and i + 1 < n:  # ESC
            c = dados[i + 1]
            if c == ord('@'):
                alinhar, negrito, largo, alto = 'e', False, 1, 1
                i += 2
            elif c == ord('a') and i + 2 < n:
                alinhar = {0: 'e', 1: 'c', 2: 'd', 48: 'e', 49: 'c', 50: 'd'}.get(dados[i + 2], 'e')
                i += 3
            elif c == ord('E') and i + 2 < n:
                negrito = bool(dados[i + 2] & 1)
                i += 3
            elif c == ord('t') and i + 2 < n:
                cod = CODIF.get(dados[i + 2], 'cp437')
                i += 3
            elif c == ord('d') and i + 2 < n:
                if atual:
                    fecha()
                linhas.extend([''] * min(dados[i + 2], 3))
                i += 3
            elif c == ord('!') and i + 2 < n:
                largo = 2 if dados[i + 2] & 0x20 else 1
                alto = 2 if dados[i + 2] & 0x10 else 1
                i += 3
            else:
                i += 3
        elif b == 0x1D and i + 1 < n:  # GS
            c = dados[i + 1]
            if c == ord('!') and i + 2 < n:
                largo = (dados[i + 2] >> 4) + 1
                alto = (dados[i + 2] & 0x0F) + 1
                i += 3
            elif c == ord('V'):
                if atual:
                    fecha()
                linhas.append('✂' + '-' * (COLS - 1))
                cortes += 1
                i += 4 if i + 2 < n and dados[i + 2] in (65, 66) else 3
            else:
                i += 3
        elif b == 0x0A:
            fecha()
            i += 1
        elif b < 0x20:
            i += 1
        else:
            j = i
            while j < n and dados[j] >= 0x20:
                j += 1
            atual += dados[i:j].decode(cod, 'replace')
            i = j
    if atual:
        fecha()
    return linhas, cortes


def atender(con, end):
    partes = []
    con.settimeout(3)
    try:
        while True:
            p = con.recv(65536)
            if not p:
                break
            partes.append(p)
    except socket.timeout:
        pass
    finally:
        con.close()
    dados = b''.join(partes)
    if not dados:
        return
    linhas, cortes = interpretar(dados)
    agora = datetime.now()
    borda = '+' + '-' * (COLS + 2) + '+'
    saida = [f'\n🖨  Cupom de {end[0]} às {agora:%H:%M:%S} ({len(dados)} bytes, {cortes} corte(s))', borda]
    saida += [f'| {ln[:COLS].ljust(COLS)} |' for ln in linhas]
    saida.append(borda)
    print('\n'.join(saida), flush=True)
    os.makedirs(PASTA, exist_ok=True)
    nome = os.path.join(PASTA, agora.strftime('%Y-%m-%d_%H-%M-%S-%f')[:-3] + '.txt')
    with open(nome, 'w', encoding='utf-8') as f:
        f.write('\n'.join(linhas) + '\n')


def main():
    s = socket.socket(socket.AF_INET, socket.SOCK_STREAM)
    s.setsockopt(socket.SOL_SOCKET, socket.SO_REUSEADDR, 1)
    s.bind(('0.0.0.0', PORTA))
    s.listen(5)
    print(f'Impressora simulada escutando na porta {PORTA} ({COLS} colunas). Ctrl+C para sair.', flush=True)
    while True:
        con, end = s.accept()
        # uma conexão por vez, como uma impressora de verdade
        threading.Thread(target=atender, args=(con, end)).run()


if __name__ == '__main__':
    try:
        main()
    except KeyboardInterrupt:
        pass
