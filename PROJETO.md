# Comandas — sistema de comandas para bares (multi-bar, celular + VPS)

> Documento-base do projeto. Serve como prompt para quem (pessoa ou agente) for
> implementar. Tudo aqui foi combinado com o dono do projeto; mudanças devem ser
> anotadas na seção "Registro de decisões" no final.

## 1. Contexto

Já existe um sistema que funciona bem: `~/PycharmProjects/bar_zemaria`
(Python puro + SQLite + PWA, rodando num notebook dentro do bar). A dinâmica dele
é boa e deve ser mantida: login por PIN, abrir comanda (número + nome), lançar
pedidos, fila offline sem duplicar, conflitos, cancelamento autorizado pelo
gerente, conta com taxa de serviço e divisão, fechamento seguro, relatório do dia,
cardápio público por QR com "chamar garçom".

**O que muda:**

1. Não existe mais computador no bar. O servidor vai para uma VPS (por enquanto
   roda local no PC do desenvolvedor).
2. O atendimento é só por celulares **Android** dos próprios garçons.
3. A impressora térmica fica na rede Wi-Fi do bar.
4. O bar precisa continuar funcionando **sem internet** (rede local) e, sem rede
   local, cada celular guarda o que fez até reconectar.
5. **Multi-bar**: vários bares no mesmo servidor, um sem enxergar o outro.
6. **Setores de impressão**: cada produto diz se imprime e em qual setor; um
   pedido com itens de setores diferentes gera um cupom separado por setor.

## 2. Decisões fixadas

| Tema | Decisão |
|---|---|
| Celular | App nativo **Flutter**, só Android. Distribuição por APK direto; Play Store depois. |
| Aparelhos | Celulares pessoais dos garçons. **Nenhum aparelho fixo** no bar. |
| Coordenação local | Um celular vira **líder** automaticamente; os outros sincronizam com ele. |
| Servidor | **Django** + **Django Ninja** (API) + **MariaDB**. Django Admin = painel do super admin. |
| Multi-bar | Para conhecidos: sem cobrança, sem bloqueio. Super admin cadastra os bares. |
| Domínio | `bar.rodrigoricardo.eng.br` (túnel Cloudflare em dev). Cardápio: `/c/<slug>`, ex. `/c/zemaria`. |
| Impressora | Padrão inicial: térmica 80mm, ESC/POS, TCP porta 9100, 48 colunas. Ajustar quando houver uma real. |
| Conflito de número | As duas comandas ficam **bloqueadas para novos pedidos** até uma delas ser fechada. |
| Conta | O cupom da conta **sempre** imprime (independe de setor). |
| Cardápio | Editado só com internet (painel web e tela de gerente no app). |
| QR / chamar garçom | Só funciona com a internet do bar no ar; sem ela, a página diz para chamar pessoalmente. |
| Fora do escopo | iOS, pagamento/PIX, NFC-e, estoque, cobrança de mensalidade. |
| Código | Repositório novo: `servidor/` (Django) e `app/` (Flutter). O projeto antigo é só referência. |

## 3. Arquitetura

```
                 ┌──────────── VPS (Django + MariaDB) ─────────────┐
                 │ API dos aparelhos · painel do gerente (web)     │
                 │ Django Admin (super admin) · cardápio /c/<slug> │
                 │ relatórios · histórico · backup                 │
                 └──────────────────▲──────────────────────────────┘
                                    │ internet (quando houver)
                                    │ Wi-Fi ou 4G de qualquer celular
   ┌───────────────────── rede Wi-Fi do bar ─────────────────────┐
   │  📱 LÍDER ──── TCP 9100 ────► 🖨 impressora                  │
   │   ▲  ▲   servidor HTTP local, ordena eventos, imprime,      │
   │   │  │   sobe eventos para a VPS, traz cardápio/chamados    │
   │  📱  📱  seguidores: cópia completa das comandas abertas     │
   └─────────────────────────────────────────────────────────────┘
```

Três níveis de funcionamento:

| Situação | Comportamento |
|---|---|
| Tudo no ar | Celulares ↔ líder ↔ VPS. Normal. |
| Sem internet | Bar funciona 100% na rede local, inclusive impressão. Eventos sobem quando voltar. |
| Sem rede local | Cada celular trabalha sozinho e guarda os eventos. Se tiver 4G, pode mandar para a VPS (que repassa ao líder quando ele aparecer). Impressão volta quando houver alguém alcançando a impressora. |

### 3.1 Fonte da verdade

- **Dados do dia (comandas abertas):** registro de eventos replicado em todos os
  celulares do bar; o líder define a ordem local.
- **Histórico, relatórios, cardápio, usuários, configurações:** VPS.
- O cardápio/usuários/configurações descem da VPS para o líder e do líder para os
  outros; cada celular guarda a última versão para funcionar offline.

## 4. Multi-bar

- Modelo `Bar` (nome, slug, ativo, configurações). **Toda** tabela de dados tem
  `bar_id`; toda consulta da API filtra pelo bar do aparelho/usuário logado
  (fazer isso num lugar só: manager/mixin + dependência da API, com teste
  automatizado que tenta acessar dados de outro bar e deve falhar).
- Super admin (Django Admin): cria bar, cria o primeiro gerente, vê tudo.
- Gerente: só o próprio bar (painel web + telas de gerente no app).
- Usuário pertence a um bar. PIN é único **dentro do bar**.
- Login no app: primeiro uso pede o **código do bar** (slug) + PIN; depois o
  aparelho lembra o bar.
- Chave secreta por bar (`lan_key`) entregue ao aparelho no login: usada para
  assinar a comunicação na rede local (evita que um celular qualquer na mesma
  Wi-Fi mande pedidos falsos).

## 5. Modelo de dados (servidor)

Nomes indicativos; ajustar no código.

- `Bar`: nome, slug, ativo, lan_key, criado_em.
- `ConfigBar` (1:1 com Bar): nome no cupom, rodapé, colunas do papel (48/32),
  codificação (ascii/cp860/cp850), cortar papel, taxa de serviço %, número máximo
  de comanda, endereço padrão da impressora (`ip:porta`).
- `Usuario`: bar, nome, pin_hash (com sal), papel (`garcom` | `gerente`), ativo.
- `Aparelho`: bar, device_id (UUID gerado no app), nome/modelo, usuário atual,
  token, último contato, último IP local, versão do app.
- `Setor`: bar, nome livre ("Cozinha", "Churrasqueira"), impressora opcional
  (vazio = impressora padrão do bar), ordem.
- `Categoria`: bar, nome, ordem, ativa.
- `Produto`: bar, categoria, nome, descrição, foto, ordem, ativo, esgotado,
  **imprime** (bool), **setor** (FK, obrigatório se imprime).
- `Variante`: produto, nome ("600ml", "Meia"), preço em centavos, ordem.
- `Evento`: bar, uuid (único), device_id, usuário, tipo, payload JSON,
  hora do aparelho (HLC), seq_local (dado pelo líder), seq_servidor, recebido_em.
- Tabelas de leitura montadas a partir dos eventos (para relatório e painel):
  `Comanda`, `Pedido`, `Item`, `Chamado`.
- `VersaoCardapio` por bar (número que sobe a cada alteração).

Valores sempre em **centavos (inteiro)**. Horários em UTC no banco, exibidos em
America/Sao_Paulo. "Dia de expediente" vai das 06:00 às 05:59 (como hoje).

## 6. Sincronização por eventos

Toda alteração do dia vira um **evento imutável** com UUID gerado no celular.
O estado das comandas é sempre "a soma dos eventos". Reenviar o mesmo evento não
duplica nada (chave = UUID).

Tipos mínimos:

| Evento | Payload |
|---|---|
| `comanda_aberta` | comanda_uuid, número, nome |
| `comanda_editada` | comanda_uuid, número, nome |
| `pedido_lancado` | pedido_uuid, comanda_uuid, itens[variante_id, nome/preço congelados, qtd, obs, setor] |
| `item_cancelado` | item_uuid, qtd, autorizado_por |
| `conta_impressa` | comanda_uuid, serviço, pessoas |
| `comanda_fechada` | comanda_uuid, serviço %, total, forçado |
| `comanda_reaberta` | comanda_uuid (só gerente) |
| `conflito_resolvido` | comandas envolvidas, ação (juntar/renumerar/descartar) |
| `impresso` | referência do cupom, setor, líder que imprimiu |
| `chamado_criado` / `chamado_atendido` | vindo da VPS / do garçom |

Regras:

- Comanda é identificada por **UUID**; o número é só um atributo.
- **Conflito:** duas comandas abertas com o mesmo número (aconteceu porque
  estavam em redes separadas) → as duas ficam marcadas "⚠ conflito", **não
  aceitam novos pedidos**, mas podem ser fechadas. Quando uma fecha, a outra
  libera. A tela de conflito oferece atalhos: juntar, renumerar uma, descartar
  (só se vazia).
- Pedido em comanda já fechada (chegou atrasado da fila): vira pendência para
  o gerente decidir (lançar em outra comanda, reabrir ou descartar) — como hoje.
- Preço e nome do produto são **congelados no pedido** (mudar o cardápio não
  altera pedidos antigos).
- **Fechar comanda:** só com o celular conectado ao líder (ou sendo o líder).
  Se algum aparelho conhecido estiver com eventos não entregues, a tela mostra
  qual; o gerente pode "Forçar fechamento" (como hoje).
- **Encerrar turno:** só com a fila do aparelho vazia; se for o líder, passa a
  liderança antes de sair.
- Líder → VPS: envia eventos em lote assim que houver internet; a VPS responde
  com `seq_servidor` e o líder marca como entregues. Qualquer celular com
  internet e eventos não confirmados pela VPS também pode enviar direto
  (idempotente).
- VPS → líder: consulta a cada ~5 s (polling simples, sem WebSocket na primeira
  versão) para receber chamados do QR e nova versão do cardápio/config.

## 7. Líder na rede local

### 7.1 Descoberta

Usar as três formas, juntas:
1. mDNS/NSD: serviço `_comandas._tcp` com `bar_slug` e `device_id`.
2. Broadcast UDP periódico numa porta fixa (para roteadores que bloqueiam mDNS).
3. Pela VPS, quando houver internet: cada aparelho informa o IP local; a VPS
   devolve a lista dos aparelhos do mesmo bar.

Se os celulares estão na mesma Wi-Fi mas não se alcançam, o app avisa:
"Esta rede não deixa os celulares conversarem (isolamento de clientes). Use a
rede principal do bar."

### 7.2 Eleição (automática)

- **Um celular só:** ele é o líder, sem notificação fixa e sem serviço em segundo
  plano. Imprime no momento em que o garçom lança (app aberto). Com o app
  fechado, uma tarefa periódica leve (WorkManager) sobe eventos para a VPS.
- **Dois ou mais:** cada aparelho anuncia uma nota:
  - carga da bateria (0–100);
  - +40 se estiver carregando;
  - −30 se o modo economia de bateria estiver ligado;
  - pequeno peso para o sinal do Wi-Fi;
  - abaixo de 20% de bateria (sem carregar) nunca vira líder.
- Eleição com **mandato numerado** (term): vence a maior nota; empate = menor
  device_id. Quem está com mandato maior manda; o outro obedece.
- **Histerese:** só troca de líder se o candidato tiver nota ≥ 25 pontos acima,
  ou se o líder cair abaixo de 25% de bateria. Isso gera o revezamento natural
  ao longo da noite sem troca a todo instante.
- **Troca combinada:** acontece em momento calmo (nenhum cupom imprimindo). O
  novo líder confirma que tem todos os eventos antes de o antigo largar.
- **Líder sumiu** (bateria, saiu da rede): sem batida por ~8–10 s, nova eleição.
  Como todos têm cópia completa, nada se perde.
- **Dois líderes** (rede partida): quando se enxergam de novo, o de mandato
  menor entrega seus eventos ao outro e vira seguidor. Números repetidos viram
  conflito (regra da seção 6).

### 7.3 Serviço em segundo plano

- Só o **líder com 2+ aparelhos** roda serviço em primeiro plano com notificação
  fixa ("Comandas · você está cuidando da impressora").
- Seguidores não precisam ficar ativos: sincronizam ao abrir o app e enquanto
  ele está na tela.
- Avaliar o tipo de foreground service exigido pelo Android 14+ (o `dataSync`
  tem limite de 6 h/dia no Android 15); provável `connectedDevice` ou
  `specialUse` com justificativa para a Play Store. Pedir também a permissão de
  rede local das versões novas do Android.
- No primeiro uso: tela que guia o garçom a tirar o app da otimização de bateria,
  com instruções por fabricante (Xiaomi, Samsung, Motorola).

## 8. Impressão

- Só o **líder** imprime (impressora aceita uma conexão por vez → cupons nunca se
  misturam). Fila de impressão própria, com nova tentativa e aviso de erro na
  tela de quem lançou ("Impressora não respondeu — sem papel/desligada?").
- ESC/POS via TCP (`ip:9100`), 48 colunas (80mm), opção 32 (58mm), codificação
  ascii (sem acentos, padrão) / cp860 / cp850, corte opcional. Reaproveitar a
  lógica da classe `Ticket` do projeto antigo (`bar_zemaria/server.py`).
- **Cupons:**
  - **Pedido por setor:** os itens com `imprime = sim` são agrupados por setor;
    um cupom cortado para cada setor, com o nome do setor no topo, número e nome
    da comanda, itens em fonte grande, observações, garçom, hora e "feito sem
    conexão às HH:MM" quando veio da fila. Itens que não imprimem não saem.
  - **Cancelamento:** só se o item cancelado tinha sido impresso; vai para o
    setor do item.
  - **Conta:** sempre imprime (todos os itens, subtotal, serviço, total,
    divisão por pessoas, "Não é documento fiscal").
  - **Chamar garçom:** vindo do cardápio QR.
  - **Teste de impressão.**
- Cada setor pode ter impressora própria no futuro; vazio = impressora padrão.
- Reimpressão manual de um pedido pela tela da comanda.
- Na troca de líder, cupons ainda não marcados como `impresso` são impressos pelo
  novo líder (aceitar o risco raro de duplicar um cupom; o cupom traz o número
  do pedido para a cozinha perceber).
- **Simulador de impressora** (`servidor/tools/impressora_fake.py`): escuta na
  porta 9100, interpreta os comandos ESC/POS básicos e mostra o cupom no
  terminal (e salva em arquivo). Usado até existir impressora real.

## 9. Servidor Django

- Projeto `servidor/` com apps sugeridos: `bares`, `contas` (usuários/PIN/
  aparelhos), `cardapio`, `comandas` (eventos + tabelas de leitura),
  `publico` (cardápio QR e chamados), `relatorios`.
- API em **Django Ninja** em `/api/v1/…`, autenticação por token do aparelho
  (`Authorization: Bearer`). Endpoints mínimos:
  - `POST /auth/login` (slug do bar + PIN + device_id) → token, usuário, lan_key
  - `GET /bootstrap` → cardápio, setores, usuários (nome + hash para login
    offline), configurações, versão
  - `POST /eventos` (lote) → seq_servidor de cada um
  - `GET /eventos?desde=` → eventos do dia (recuperar celular novo)
  - `POST /presenca` → IP local, bateria, é líder?, fila pendente;
    devolve aparelhos do bar + chamados abertos + versão do cardápio
- Painel do gerente na web (templates Django simples, responsivo): produtos,
  variantes, fotos, setores, categorias, garçons/PINs, configurações, impressora,
  aparelhos, relatório por período, QR do cardápio para imprimir.
- Cardápio público `/c/<slug>`: sem login, cache curto, produtos esgotados somem.
  "Chamar garçom" com as mesmas proteções contra trote do sistema antigo; se o
  líder do bar não fala com a VPS há mais de ~30 s, mostra "Chame o garçom
  pessoalmente".
- Configuração por variáveis de ambiente (`.env`, **fora do git**):
  `DATABASE_NAME`, `DATABASE_USER`, `DATABASE_PASSWORD`, `DATABASE_HOST`,
  `DATABASE_PORT`, `SECRET_KEY`, `DEBUG`, `ALLOWED_HOSTS`, `CSRF_TRUSTED_ORIGINS`.
  Fornecer `.env.example` sem senhas.
- Dev: MariaDB local (banco `bar`), `runserver` ou gunicorn, túnel Cloudflare
  `bar.rodrigoricardo.eng.br → localhost:8000`.

## 10. App Flutter

- Pastas: `app/` — Android apenas (`minSdk` a definir, mirar Android 8+).
- Pacotes de referência (validar versões no início): banco local SQLite (`drift`),
  servidor HTTP local (`shelf`), descoberta (`nsd` / `multicast_dns`), bateria
  (`battery_plus`), rede (`connectivity_plus`, `network_info_plus`), serviço em
  primeiro plano (`flutter_foreground_task`), tarefas periódicas (`workmanager`),
  geração ESC/POS própria ou `esc_pos_utils_plus`.
- Comunicação na rede local: HTTP JSON no líder (porta fixa, ex. 8787) com
  requisições assinadas (HMAC com a `lan_key` do bar). Batidas a cada ~2 s.
- Login offline: PIN validado contra os hashes recebidos no `bootstrap`.
- **Telas** (seguir a dinâmica do app atual, `bar_zemaria/static/app.js`):
  login por PIN · lista de comandas abertas (com total, quantidade, avisos de
  fila/conflito) · abrir comanda · cardápio para lançar (categorias, variantes,
  quantidade, observação, carrinho) · detalhe da comanda (itens, pedidos,
  reimprimir, cancelar com PIN do gerente) · conta (serviço, dividir, imprimir,
  fechar) · conflitos/pendências · chamados do QR com "Atendido" · status da
  rede (quem é o líder, aparelhos, impressora, internet) · encerrar turno ·
  telas de gerente (configurações rápidas, teste de impressora, aparelhos).
- Barra de status sempre visível: 🟢 online · 🟡 só rede local · 🔴 sozinho
  (N na fila) · ícone de líder.

## 11. Etapas de entrega

Cada etapa termina com algo testável.

1. **Base:** repositório, Django + MariaDB + `.env`, modelos de bar/usuário/
   cardápio/setor, Django Admin, simulador de impressora.
2. **API e painel:** login de aparelho, bootstrap, eventos, presença; painel web
   do gerente (cardápio, setores, garçons, config). Teste de isolamento entre
   bares.
3. **App com 1 celular:** login, comandas, lançar pedido, impressão direta por
   setor, conta, fechamento, banco local + fila offline, envio para a VPS.
4. **Rede local:** descoberta, eleição por bateria, replicação, troca de líder,
   serviço em primeiro plano, aviso de isolamento de clientes.
5. **Conflitos e fechamento seguro:** bloqueio de comandas duplicadas, pendências,
   forçar fechamento, encerrar turno com passagem de liderança.
6. **Público e relatórios:** cardápio `/c/<slug>`, chamar garçom via líder,
   relatório por período, QR para imprimir.
7. **Acabamento:** guia de bateria por fabricante, APK assinado para distribuir,
   preparação para Play Store.

## 12. Cenários de teste obrigatórios

1. Três celulares, internet caindo no meio do movimento: pedidos continuam
   imprimindo; quando volta, tudo aparece na VPS sem duplicar.
2. Líder desligado de repente: outro assume em ≤ 10 s e imprime o que faltava.
3. Wi-Fi do bar cai: garçom lança offline; ao voltar, pedido imprime com
   "feito sem conexão às HH:MM".
4. Dois celulares separados abrem a comanda 15: ao se reencontrarem, as duas
   ficam bloqueadas para pedidos; fechar uma libera a outra.
5. Pedido com cerveja + porção + churrasco: saem 2 cupons (Cozinha e
   Churrasqueira); a cerveja não sai.
6. Bateria: líder em 30% e outro carregando em 60% → troca; líder em 70% e
   outro em 75% → não troca.
7. Bar A nunca vê nem altera dados do Bar B (teste automatizado na API).
8. Um celular só, app fechado e reaberto: nada perdido, nada duplicado.
9. Cliente chama garçom pelo QR com internet: cupom sai e aparece nos celulares;
   sem internet no bar: a página manda chamar pessoalmente.

## 13. Pontos em aberto

- Modelo real da impressora (ajustar codificação/corte quando chegar).
- Tipo de foreground service aceito pela Play Store.
- Hospedagem da VPS (quando sair do PC local).

## 14. Registro de decisões

- 2026-10-22: documento inicial combinado com o dono do projeto.
