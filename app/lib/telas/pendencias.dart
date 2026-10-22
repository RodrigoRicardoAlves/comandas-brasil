import 'package:flutter/material.dart';

import '../app.dart';
import '../dados/estado.dart';
import '../util.dart';
import 'comum.dart';

/// Pedidos que chegaram depois de a comanda ser fechada (vieram da fila de um celular
/// que estava sem conexão). O gerente decide: lançar em outra comanda, reabrir ou descartar.
class TelaPendencias extends StatelessWidget {
  const TelaPendencias({super.key});

  Future<String?> _gerente(BuildContext context, String motivo) async {
    final u = App.i.usuario!;
    if (u.gerente) return u.nome;
    return pedirPinGerente(context, motivo);
  }

  Future<void> _mover(BuildContext context, PedidoC p) async {
    final a = App.i;
    final abertas = a.estado.abertas;
    if (abertas.isEmpty) {
      aviso(context, 'Não há comanda aberta. Abra uma antes.', erro: true);
      return;
    }
    final para = await showDialog<ComandaC>(
      context: context,
      builder: (c) => SimpleDialog(
        title: const Text('Lançar em qual comanda?'),
        children: [
          for (final x in abertas)
            SimpleDialogOption(
              onPressed: () => Navigator.pop(c, x),
              child: Text('${x.numero} · ${x.nome}', style: const TextStyle(fontSize: 18)),
            ),
        ],
      ),
    );
    if (para == null || !context.mounted) return;
    final g = await _gerente(context, 'Lançar o pedido na comanda ${para.numero}');
    if (g == null || !context.mounted) return;
    await tentar(context, () => a.resolverPendencia(p, 'mover', para: para, gerente: g), ok: 'Lançado na comanda ${para.numero}');
  }

  Future<void> _reabrir(BuildContext context, ComandaC c) async {
    final a = App.i;
    final g = await _gerente(context, 'Reabrir a comanda ${c.numero}');
    if (g == null || !context.mounted) return;
    await tentar(context, () => a.reabrirComanda(c, autorizadoPor: g), ok: 'Comanda ${c.numero} reaberta');
  }

  Future<void> _descartar(BuildContext context, PedidoC p) async {
    if (!await confirmar(context, 'Descartar pedido?', 'Ele não entra em conta nenhuma e não é impresso.', sim: 'Descartar', perigo: true) ||
        !context.mounted) {
      return;
    }
    final g = await _gerente(context, 'Descartar pedido atrasado');
    if (g == null || !context.mounted) return;
    await tentar(context, () => App.i.resolverPendencia(p, 'descartar', gerente: g), ok: 'Pedido descartado');
  }

  @override
  Widget build(BuildContext context) {
    return ListenableBuilder(
      listenable: App.i,
      builder: (context, _) {
        final e = App.i.estado;
        final lista = e.pendencias;
        return Scaffold(
          appBar: AppBar(title: const Text('Pedidos atrasados')),
          body: lista.isEmpty
              ? const Center(child: Text('Nenhum pedido esperando decisão', style: TextStyle(color: Colors.white54, fontSize: 16)))
              : ListView(padding: const EdgeInsets.all(12), children: [
                  const Text(
                    'Estes pedidos foram feitos num celular sem conexão e só chegaram depois de a comanda ser fechada. '
                    'Ainda não foram impressos nem cobrados.',
                    style: TextStyle(color: Colors.white70),
                  ),
                  const SizedBox(height: 12),
                  for (final p in lista) _cartao(context, e, p),
                ]),
        );
      },
    );
  }

  Widget _cartao(BuildContext context, Estado e, PedidoC p) {
    final c = e.comandas[p.comanda]!;
    final total = p.itens.where((i) => !i.cancelado).fold(0, (s, i) => s + i.total);
    return Card(
      margin: const EdgeInsets.only(bottom: 12),
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Text('Comanda ${c.numero} · ${c.nome}', style: const TextStyle(fontSize: 18, fontWeight: FontWeight.bold)),
          Text('Fechada às ${hhmm(c.fechadaEm!)} por ${c.fechadaPor}', style: const TextStyle(color: Colors.white60)),
          Text('Pedido de ${p.garcom} às ${hhmm(p.hora)}${p.offline ? ' (sem conexão)' : ''}',
              style: const TextStyle(color: corAmbar)),
          const SizedBox(height: 6),
          for (final i in p.itens.where((i) => !i.cancelado))
            Text('${i.qtd}x ${i.rotulo}  ${dinheiro(i.total)}', style: const TextStyle(fontSize: 16)),
          Text('Total ${reais(total)}', style: const TextStyle(fontWeight: FontWeight.bold)),
          const SizedBox(height: 10),
          Wrap(spacing: 8, runSpacing: 8, children: [
            FilledButton.tonal(onPressed: () => _mover(context, p), child: const Text('Lançar em outra')),
            OutlinedButton(
              onPressed: e.abertaComNumero(c.numero) == null ? () => _reabrir(context, c) : null,
              child: Text('Reabrir ${c.numero}'),
            ),
            TextButton(
              onPressed: () => _descartar(context, p),
              child: const Text('Descartar', style: TextStyle(color: corVermelha)),
            ),
          ]),
        ]),
      ),
    );
  }
}
