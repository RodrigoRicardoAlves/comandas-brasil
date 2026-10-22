import 'package:flutter/material.dart';

import '../app.dart';
import '../dados/estado.dart';
import '../util.dart';
import 'comum.dart';
import 'conta.dart';
import 'inicio.dart';
import 'lancar.dart';

class TelaComanda extends StatelessWidget {
  final String uuid;
  const TelaComanda(this.uuid, {super.key});

  Future<void> _cancelar(BuildContext context, ItemC i) async {
    final a = App.i;
    if (!await confirmar(context, 'Cancelar item?', '${i.qtd}x ${i.rotulo}\n\nVai sair um cupom de cancelamento se ele já foi impresso.',
        sim: 'Cancelar item', perigo: true)) {
      return;
    }
    if (!context.mounted) return;
    String? gerente;
    if (!a.usuario!.gerente) {
      gerente = await pedirPinGerente(context, 'Cancelar ${i.qtd}x ${i.rotulo}');
      if (gerente == null) return;
    }
    if (context.mounted) await tentar(context, () => a.cancelarItem(i, autorizadoPor: gerente), ok: 'Item cancelado');
  }

  @override
  Widget build(BuildContext context) {
    return ListenableBuilder(
      listenable: App.i,
      builder: (context, _) {
        final a = App.i;
        final c = a.estado.comandas[uuid];
        if (c == null) return const Scaffold(body: Center(child: Text('Comanda não encontrada')));
        final conflito = a.estado.emConflito(c);
        return Scaffold(
          appBar: AppBar(
            title: Text('${c.numero} · ${c.nome}'),
            actions: [
              if (c.aberta)
                IconButton(icon: const Icon(Icons.edit), tooltip: 'Editar', onPressed: () => dialogoComanda(context, editar: c)),
              if (c.aberta && c.itensAtivos.isEmpty)
                IconButton(
                  icon: const Icon(Icons.delete_outline),
                  tooltip: 'Descartar comanda vazia',
                  onPressed: () async {
                    if (await confirmar(context, 'Descartar comanda vazia?', 'Comanda ${c.numero} (${c.nome}) some da lista.', perigo: true) &&
                        context.mounted) {
                      if (await tentar(context, () => a.descartarComanda(c)) && context.mounted) Navigator.pop(context);
                    }
                  },
                ),
            ],
          ),
          body: Column(children: [
            const BarraStatus(),
            if (conflito)
              Container(
                width: double.infinity,
                color: corVermelha.withValues(alpha: .2),
                padding: const EdgeInsets.all(12),
                child: const Text(
                  '⚠ Há duas comandas com este número (abertas em celulares que estavam sem se comunicar). '
                  'Novos pedidos ficam bloqueados até uma delas ser fechada. Dica: troque o número de uma delas no lápis ✏️.',
                  style: TextStyle(color: corVermelha),
                ),
              ),
            if (!c.aberta)
              Container(
                width: double.infinity,
                color: corAzul.withValues(alpha: .15),
                padding: const EdgeInsets.all(12),
                child: Text(c.descartada ? 'Comanda descartada' : 'Fechada às ${hhmm(c.fechadaEm!)} por ${c.fechadaPor} · ${reais(c.total ?? 0)}'),
              ),
            Expanded(
              child: c.pedidos.isEmpty
                  ? const Center(child: Text('Nenhum pedido ainda', style: TextStyle(color: Colors.white54, fontSize: 16)))
                  : ListView(
                      padding: const EdgeInsets.only(bottom: 12),
                      children: [
                        for (final p in c.pedidos.reversed) ...[
                          _CabecalhoPedido(p),
                          for (final i in p.itens)
                            ListTile(
                              dense: true,
                              title: Text('${i.qtd}x ${i.rotulo}',
                                  style: TextStyle(
                                    fontSize: 17,
                                    decoration: i.cancelado ? TextDecoration.lineThrough : null,
                                    color: i.cancelado ? Colors.white38 : null,
                                  )),
                              subtitle: i.cancelado
                                  ? Text('cancelado por ${i.canceladoPor}')
                                  : (i.obs.isNotEmpty ? Text('>> ${i.obs}', style: const TextStyle(color: corAmbar)) : null),
                              trailing: Text(dinheiro(i.total), style: const TextStyle(fontSize: 16)),
                              onLongPress: c.aberta && !i.cancelado ? () => _cancelar(context, i) : null,
                            ),
                        ],
                        const Padding(
                          padding: EdgeInsets.all(12),
                          child: Text('Segure um item para cancelar.', textAlign: TextAlign.center, style: TextStyle(color: Colors.white38)),
                        ),
                      ],
                    ),
            ),
            SafeArea(
              top: false,
              child: Container(
                color: const Color(0xFF1C1D22),
                padding: const EdgeInsets.all(12),
                child: Column(children: [
                  Row(children: [
                    const Text('Total', style: TextStyle(fontSize: 18)),
                    const Spacer(),
                    Text(reais(c.subtotal), style: const TextStyle(fontSize: 24, fontWeight: FontWeight.bold)),
                  ]),
                  const SizedBox(height: 10),
                  if (c.aberta)
                    Row(children: [
                      Expanded(
                        child: OutlinedButton.icon(
                          icon: const Icon(Icons.receipt_long),
                          label: const Text('Conta'),
                          onPressed: () => Navigator.push(context, MaterialPageRoute(builder: (_) => TelaConta(c.uuid))),
                        ),
                      ),
                      const SizedBox(width: 10),
                      Expanded(
                        flex: 2,
                        child: FilledButton.icon(
                          icon: const Icon(Icons.add_shopping_cart),
                          label: const Text('Lançar pedido'),
                          onPressed: conflito
                              ? null
                              : () => Navigator.push(context, MaterialPageRoute(builder: (_) => TelaLancar(c.uuid))),
                        ),
                      ),
                    ])
                  else if (!c.descartada && a.usuario!.gerente)
                    SizedBox(
                      width: double.infinity,
                      child: OutlinedButton(
                          onPressed: () => tentar(context, () => a.reabrirComanda(c), ok: 'Comanda reaberta'),
                          child: const Text('Reabrir comanda')),
                    ),
                ]),
              ),
            ),
          ]),
        );
      },
    );
  }
}

class _CabecalhoPedido extends StatelessWidget {
  final PedidoC p;
  const _CabecalhoPedido(this.p);

  @override
  Widget build(BuildContext context) {
    final a = App.i;
    final setores = p.setores;
    final impresso = a.estado.pedidoImpresso(p);
    return Container(
      color: Colors.white.withValues(alpha: .04),
      padding: const EdgeInsets.fromLTRB(16, 6, 4, 6),
      child: Row(children: [
        Expanded(
          child: Text(
            '${hhmm(p.hora)} · ${p.garcom}${p.offline ? ' · sem conexão' : ''}',
            style: const TextStyle(color: Colors.white60),
          ),
        ),
        if (setores.isNotEmpty) ...[
          Icon(impresso ? Icons.print : Icons.print_disabled, size: 18, color: impresso ? corVerde : corAmbar),
          const SizedBox(width: 4),
          Text(setores.join(', '), style: TextStyle(color: impresso ? corVerde : corAmbar, fontSize: 13)),
          IconButton(
            icon: const Icon(Icons.replay, size: 20),
            tooltip: 'Reimprimir',
            onPressed: () async {
              if (await confirmar(context, 'Reimprimir pedido?', 'Sai de novo o cupom de: ${setores.join(', ')}.', sim: 'Reimprimir') &&
                  context.mounted) {
                await tentar(context, () => a.reimprimirPedido(p), ok: 'Enviado para a impressora');
              }
            },
          ),
        ],
      ]),
    );
  }
}
