<div align="center">

# 🍺 Comandas Brasil

**Comandas para bares e restaurantes — simples, offline e sem travar.**

App Android para os garçons lançarem pedidos + servidor web com painel do gerente
e cardápio por QR Code. Os pedidos ficam guardados no próprio celular e sincronizam
entre os aparelhos e com o servidor quando há internet, **sem duplicar**.

[![Licença: MIT](https://img.shields.io/badge/Licença-MIT-FFB020.svg)](LICENSE)
![Plataforma](https://img.shields.io/badge/App-Android%20(Flutter)-02569B.svg)
![Servidor](https://img.shields.io/badge/Servidor-Django-092E20.svg)

**▶ Versão pronta, hospedada e com suporte:** https://comandasbrasil.com.br
<br>Prefere rodar por conta própria? O código é aberto (MIT) — baixe e use.

</div>

---

## ✨ O que faz

- 📝 **Comandas e pedidos** com cupons separados por setor (cozinha, churrasqueira, bar…)
- 🖨️ **Impressão flexível**: impressora WiFi (rede) ou a impressora embutida de uma
  maquininha (Sunmi) — escolhida por setor e para a conta
- 📱 **Vários celulares no mesmo bar**, com um líder de impressão eleito sozinho
- 📶 **Funciona sem internet**: tudo é guardado no aparelho e sincroniza depois, sem duplicar
- 👔 **Painel do gerente**: equipe, cardápio, setores, relatórios e QR Code
- 🙋 **Cardápio do cliente por QR Code**, com botão "chamar o garçom"

## 🗂️ Estrutura

| Pasta | O que é |
|---|---|
| `app/` | App Android (Flutter): atendimento, impressão, rede local entre celulares |
| `servidor/` | Servidor web (Django): painel do gerente, cardápio do cliente, API e admin |
| `deploy/` | Arquivos de serviço (systemd) e exemplo de Nginx para colocar no ar |
| `loja/` | Logo e textos para a Play Store |

## 🚀 Como rodar

- **Servidor:** veja [`COMO-TESTAR.md`](COMO-TESTAR.md) e [`deploy/LEIA-ME.md`](deploy/LEIA-ME.md)
- **App:** Flutter; `app/publicar.sh` gera e publica o APK
- **Especificação e decisões de projeto:** [`PROJETO.md`](PROJETO.md)

> 🔑 As chaves e segredos (`.env`, chave de assinatura do app, senha do banco) ficam
> **fora** do repositório. Configure os seus a partir de [`.env.example`](.env.example).

## 👤 Créditos

Projeto **idealizado e concebido por [Rodrigo Ricardo Alves](https://github.com/RodrigoRicardoAlves)** —
a visão do produto, as regras do negócio e as decisões de como o bar funciona no dia a dia.

Implementação **realizada com o [Claude](https://claude.com/claude-code)** (Claude Code, da Anthropic),
sob a direção do autor.

## 📄 Licença

[MIT](LICENSE) — uso livre, inclusive comercial, mantendo o aviso de direitos autorais.
