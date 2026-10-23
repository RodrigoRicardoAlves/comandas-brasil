# Comandas Brasil na Play Store — o que já está pronto e o que falta

## Pronto
- App assinado com chave própria (`~/chaves-comandas/`), pacote `br.eng.rodrigoricardo.comandas`.
- Pacote para a loja: `AAB=1 app/publicar.sh "notas"` gera `loja/comandas-<versão>.aab`.
- Ícone 512 px: `loja/icone-512.png`. Logo: `loja/logo.png`.
- Política de privacidade: https://bar.rodrigoricardo.eng.br/privacidade/ (defina `CONTATO_EMAIL` no .env).

## Falta (feito por você no Play Console)
1. Conta de desenvolvedor Google (taxa única) e verificação de identidade.
2. Criar o app, enviar o .aab em "Teste interno" primeiro (até 100 testadores por e-mail).
3. Contas novas de pessoa física precisam de **teste fechado com 12 testadores por 14 dias** antes de publicar.
4. Imagem de destaque 1024×500 e 2 a 8 prints do celular (tire do próprio app).
5. Questionários: classificação etária (Livre), público-alvo (18+, uso profissional), anúncios (não).

## Textos sugeridos
- **Nome:** Comandas Brasil
- **Descrição curta (80):** Comandas de bar no celular do garçom. Imprime na cozinha e funciona sem internet.
- **Descrição completa:** O Comandas Brasil troca o bloquinho e o computador do balcão pelo celular dos garçons.
  Abra a comanda, lance o pedido e o cupom sai na cozinha ou na churrasqueira (bebida não imprime à toa).
  Caiu a internet? Os celulares continuam conversando pelo Wi-Fi do bar. Conta com taxa de serviço e divisão,
  cancelamento autorizado pelo gerente, cardápio por QR Code com "chamar garçom" e relatórios do dia.
  Precisa de cadastro do bar (o gerente recebe o código e os PINs).

## Declarações que a Google vai pedir
- **Serviço em primeiro plano (connectedDevice):** "Quando o celular é o líder do bar, mantém a conexão com a
  impressora térmica de rede (TCP 9100) para imprimir os pedidos dos outros garçons. A notificação fica visível
  enquanto isso." Grave um vídeo curto mostrando a notificação e um cupom saindo.
- **REQUEST_IGNORE_BATTERY_OPTIMIZATIONS:** pode ser questionado. Justificativa: o app mantém conexão com
  dispositivo externo (impressora) durante o expediente. Se a Google recusar, troque o botão "Permitir" do guia
  de bateria pela abertura da lista de configurações (já existe como alternativa no código).
- **Segurança dos dados:** coleta nome do cliente digitado pelo garçom, registros de pedidos, ID do aparelho;
  nada é compartilhado com terceiros; dados criptografados em trânsito (HTTPS); o bar pode pedir exclusão.
- **ACCESS_LOCAL_NETWORK / Wi-Fi:** comunicação com outros celulares do bar e com a impressora.
