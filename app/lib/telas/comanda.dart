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
            if (conflito) _Conflito(c, a.estado.abertaComNumero(c.numero, exceto: c.uuid)!),
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

/// Duas comandas abertas com o mesmo número: mostra as duas e os atalhos para resolver.
class _Conflito extends StatelessWidget {
  final ComandaC c, outra;
  const _Conflito(this.c, this.outra);

  @override
  Widget build(BuildContext context) {
    final a = App.i;
    return Container(
      width: double.infinity,
      color: corVermelha.withValues(alpha: .2),
      padding: const EdgeInsets.all(12),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Text(
          '⚠ Há duas comandas ${c.numero} abertas: esta (${c.nome}, ${reais(c.subtotal)}) e a de '
          '${outra.nome} (${reais(outra.subtotal)}, aberta por ${outra.abertaPor}). '
          'Nenhuma aceita pedido até resolver. Fechar uma também resolve.',
          style: const TextStyle(color: corVermelha),
        ),
        const SizedBox(height: 8),
        Wrap(spacing: 8, runSpacing: 8, children: [
          FilledButton.tonal(onPressed: () => dialogoComanda(context, editar: c), child: const Text('Trocar o número desta')),
          OutlinedButton(
            onPressed: () async {
              if (await confirmar(context, 'Juntar comandas?',
                      'Os pedidos desta comanda (${c.nome}) passam para a de ${outra.nome}, e esta deixa de existir.',
                      sim: 'Juntar') &&
                  context.mounted) {
                if (await tentar(context, () => a.juntarComanda(c, outra), ok: 'Comandas juntadas') && context.mounted) {
                  Navigator.pushReplacement(context, MaterialPageRoute(builder: (_) => TelaComanda(outra.uuid)));
                }
              }
            },
            child: Text('Juntar na de ${outra.nome}'),
          ),
          if (c.itensAtivos.isEmpty)
            TextButton(
              onPressed: () async {
                if (await tentar(context, () => a.descartarComanda(c), ok: 'Comanda descartada') && context.mounted) {
                  Navigator.pop(context);
                }
              },
              child: const Text('Descartar esta (vazia)', style: TextStyle(color: corVermelha)),
            ),
        ]),
      ]),
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
            '${hhmm(p.hora)} · ${p.garcom}${p.offline ? ' · sem conexão' : ''}'
            '${p.pendente ? ' · ATRASADO (fora da conta)' : ''}${p.descartado ? ' · DESCARTADO' : ''}',
            style: TextStyle(color: p.conta ? Colors.white60 : corVermelha),
          ),
        ),
        if (setores.isNotEmpty && p.conta) ...[
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
