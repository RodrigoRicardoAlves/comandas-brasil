# Comandas Brasil

Sistema de comandas para bares e restaurantes: um app Android para os garçons
lançarem pedidos e um servidor web com painel do gerente e cardápio por QR Code.
Funciona **offline** — os pedidos são guardados no próprio celular e sincronizam
entre os aparelhos (rede local) e com o servidor quando há internet, sem duplicar.

Versão hospedada (pronta para usar, com suporte): **https://bar.rodrigoricardo.eng.br**
Código aberto sob licença MIT — baixe e rode por conta própria se preferir.

## O que tem aqui

| Pasta | O que é |
|---|---|
| `app/` | App Android (Flutter): atendimento, impressão, rede local entre celulares |
| `servidor/` | Servidor web (Django): painel do gerente, cardápio do cliente, API e admin |
| `deploy/` | Arquivos de serviço (systemd) e exemplo de Nginx para colocar no ar |
| `loja/` | Logo e textos para a Play Store |

## Principais recursos

- Comandas e pedidos, com cupons separados por setor (cozinha, churrasqueira, bar…)
- Impressão em impressora WiFi (rede) ou na impressora embutida de uma maquininha
  (Sunmi), configurável por setor e para a conta
- Vários celulares no mesmo bar, com um líder de impressão eleito automaticamente
- Painel do gerente: equipe, cardápio, setores, relatórios e QR Code
- Cardápio do cliente por QR Code, com "chamar o garçom"

## Como rodar

- Servidor: veja [`COMO-TESTAR.md`](COMO-TESTAR.md) e [`deploy/LEIA-ME.md`](deploy/LEIA-ME.md).
- App: Flutter; `app/publicar.sh` gera e publica o APK.
- Especificação e decisões de projeto: [`PROJETO.md`](PROJETO.md).

> As chaves e segredos (`.env`, chave de assinatura do app, senha do banco) ficam
> fora do repositório. Configure os seus a partir de [`.env.example`](.env.example).

## Licença

[MIT](LICENSE) — uso livre, inclusive comercial, mantendo o aviso de direitos autorais.
