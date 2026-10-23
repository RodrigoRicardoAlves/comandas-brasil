# Como testar o Comandas Brasil

Endereços (com o PC ligado e o túnel da Cloudflare no ar):

| O quê | Onde |
|---|---|
| Página inicial | https://bar.rodrigoricardo.eng.br/ |
| Baixar o app (garçons) | https://bar.rodrigoricardo.eng.br/app/ |
| Painel do gerente | https://bar.rodrigoricardo.eng.br/painel/ — código `zemaria`, PIN de gerente `9999` |
| Cardápio do cliente (QR) | https://bar.rodrigoricardo.eng.br/c/zemaria/ |
| Admin (super admin, criar bares) | https://bar.rodrigoricardo.eng.br/admin/ |

PINs de exemplo do bar zemaria: Zé Maria (gerente) `9999`, Maria `5678`. O do João foi trocado no painel.

## Ligar o servidor no PC
```bash
cd ~/PycharmProjects/comandas/servidor
../.venv/bin/python manage.py runserver --insecure 0.0.0.0:8100
../.venv/bin/python tools/impressora_fake.py   # impressora de mentira (porta 9100), se não houver uma real
```
No painel → Configurações, a "impressora padrão" do Zé Maria aponta para o PC (`192.168.3.19:9100`).
Com impressora de verdade, troque pelo IP dela.

## Roteiro rápido
1. **Instalar:** no celular, abra `/app/`, baixe e instale. Primeiro acesso: código `zemaria` + PIN.
   O guia de bateria abre sozinho: faça os passos.
2. **Atender:** abra comanda, lance cerveja + porção + espetinho → saem 2 cupons (cozinha e churrasqueira).
3. **Conta:** Conta → 10% → dividir → Imprimir → Fechar.
4. **Dois celulares:** entre com garçons diferentes. Um vira líder (ícone 🖨 no topo). Lance pelo outro:
   o cupom sai pelo líder. Desligue o líder: em ~10 s o outro assume.
5. **Sem internet:** desligue o servidor (ou a internet do roteador). Continue lançando: imprime normal.
   Ligue de novo: tudo aparece no painel sem duplicar.
6. **Mesmo PIN em dois celulares:** tente entrar com a Maria em dois — o segundo é recusado.
7. **Gerente:** menu ⋮ → Esgotados (marca/desmarca); Painel → Relatórios, Cardápio, Equipe, QR Code.
8. **Cliente:** abra o cardápio do QR, toque "Chamar o garçom" → sai cupom e aparece no app.
9. **Maquininha Sunmi (P2):** menu ⋮ → Status e impressora → "Usar a impressora desta maquininha".
   Ela vira a líder e imprime os pedidos de todos (papel 58 mm, 32 colunas).
10. **Atualização:** quando houver versão nova publicada, aparece uma faixa azul no app: toque e instale.

## Publicar nova versão do app
Suba `version:` em `app/pubspec.yaml` (ex.: `1.0.3+4`) e rode `app/publicar.sh "o que mudou"`.

Mais detalhes: `PROJETO.md` (especificação e decisões), `deploy/LEIA-ME.md` (VPS), `loja/PLAY_STORE.md`.
