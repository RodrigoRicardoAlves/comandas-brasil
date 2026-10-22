import '../dados/estado.dart';
import '../dados/modelos.dart';
import '../util.dart';
import 'escpos.dart';

Cupom _novo(BarCfg b) => Cupom(colunas: b.colunas, codificacao: b.codificacao, cortar: b.cortar);

/// Cupom de um setor (Cozinha, Churrasqueira...) com só os itens daquele setor.
List<int> cupomPedido(BarCfg b, ComandaC c, PedidoC p, String setor, {bool reimpressao = false}) {
  final itens = p.itens.where((i) => i.imprime && i.setor == setor && !i.cancelado);
  final k = _novo(b);
  k.centro().negrito().texto(setor.toUpperCase()).negrito(false);
  if (reimpressao) k.texto('** REIMPRESSAO **');
  k.tamanho(2, 2).texto('COMANDA ${c.numero}').tamanho();
  k.negrito().texto(c.nome).negrito(false).esquerda().linha();
  k.tamanho(1, 2).negrito();
  for (final i in itens) {
    k.quebrar('${i.qtd}x ${i.rotulo}');
    if (i.obs.isNotEmpty) k.quebrar('   >> ${i.obs}', recuo: '      ');
  }
  k.negrito(false).tamanho().linha();
  if (p.offline) k.negrito().texto('Feito as ${hhmm(p.hora)} (sem conexao)').negrito(false);
  k.texto('${p.garcom}  ${ddmmHhmm(p.hora)}  #${p.uuid.length > 6 ? p.uuid.substring(0, 6) : p.uuid}');
  return (k..avancar()..corte()).bytes;
}

List<int> cupomCancelamento(BarCfg b, ComandaC c, ItemC i, String quem) {
  final k = _novo(b);
  k.centro().negrito().texto(i.setor.toUpperCase()).negrito(false);
  k.tamanho(2, 2).texto('CANCELADO').tamanho().negrito().texto('Comanda ${c.numero} - ${c.nome}');
  k.negrito(false).esquerda().linha().tamanho(1, 2).quebrar('${i.qtd}x ${i.rotulo}').tamanho().linha();
  k.texto('$quem  ${ddmmHhmm(agoraMs())}');
  return (k..avancar()..corte()).bytes;
}

List<int> cupomConta(BarCfg b, ComandaC c, {required bool servico, required int pessoas}) {
  final linhas = Estado.linhasConta(c);
  final sub = c.subtotal;
  final pct = servico ? b.taxaServico : 0.0;
  final svc = (sub * pct / 100).round();
  final total = sub + svc;
  final k = _novo(b);
  k.centro().negrito().tamanho(1, 2).texto(b.nome).tamanho().negrito(false);
  k.texto('Comanda ${c.numero} - ${c.nome}').texto(ddmmHhmm(agoraMs())).esquerda().linha();
  for (final l in linhas) {
    k.ladoALado('${l.qtd}x ${l.rotulo}', dinheiro(l.total));
    if (l.qtd > 1) k.texto('   ${dinheiro(l.preco)} cada');
  }
  k.linha();
  if (svc > 0) {
    k.ladoALado('Subtotal', dinheiro(sub));
    k.ladoALado('Servico ${pct.toStringAsFixed(pct % 1 == 0 ? 0 : 1)}%', dinheiro(svc));
  }
  k.negrito().tamanho(1, 2).ladoALado('TOTAL', reais(total)).tamanho().negrito(false);
  if (pessoas > 1) k.ladoALado('Dividido por $pessoas', reais((total / pessoas).ceil()));
  k.linha().centro();
  if (b.rodape.isNotEmpty) k.texto(b.rodape);
  k.texto('Nao e documento fiscal');
  return (k..avancar()..corte()).bytes;
}

List<int> cupomChamado(BarCfg b, Map<String, dynamic> ch) {
  final k = _novo(b);
  k.centro().tamanho(2, 2).texto('GARCOM!').tamanho().linha('=');
  if (ch['numero'] != null) {
    k.tamanho(2, 2).texto('COMANDA ${ch['numero']}').tamanho();
  } else {
    k.tamanho(1, 2).negrito().texto('${ch['quem']}').negrito(false).tamanho();
  }
  k.tamanho(1, 2).texto('${ch['motivo_texto']}').tamanho();
  k.texto('Chamado pelo cardapio ${hhmm(agoraMs())}');
  return (k..avancar()..corte()).bytes;
}

List<int> cupomTeste(BarCfg b, String alvo, String aparelho) {
  final k = _novo(b);
  k.centro().tamanho(2, 2).texto('TESTE').tamanho().negrito().texto(b.nome).negrito(false);
  k.esquerda().linha().texto('Impressora: $alvo').texto('Enviado por: $aparelho').texto('Hora: ${ddmmHhmm(agoraMs())}');
  k.texto('Acentos: ação, pão, café, órgão, Ç');
  k.linha().texto('1234567890' * (b.colunas ~/ 10)).linha();
  return (k..avancar()..corte()).bytes;
}
