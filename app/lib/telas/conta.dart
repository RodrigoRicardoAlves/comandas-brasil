import 'package:flutter/material.dart';

import '../app.dart';
import '../dados/estado.dart';
import '../util.dart';
import 'comum.dart';

class TelaConta extends StatefulWidget {
  final String comanda;
  const TelaConta(this.comanda, {super.key});
  @override
  State<TelaConta> createState() => _TelaContaState();
}

class _TelaContaState extends State<TelaConta> {
  late bool _servico = App.i.boot!.bar.taxaServico > 0;
  int _pessoas = 1;

  @override
  Widget build(BuildContext context) {
    return ListenableBuilder(
      listenable: App.i,
      builder: (context, _) {
        final a = App.i;
        final c = a.estado.comandas[widget.comanda]!;
        final taxa = a.boot!.bar.taxaServico;
        final total = a.totalComServico(c, _servico);
        final linhas = Estado.linhasConta(c);
        return Scaffold(
          appBar: AppBar(title: Text('Conta · ${c.numero} ${c.nome}')),
          body: Column(children: [
            const BarraStatus(),
            Expanded(
              child: ListView(padding: const EdgeInsets.all(12), children: [
                for (final l in linhas)
                  ListTile(
                    dense: true,
                    title: Text('${l.qtd}x ${l.rotulo}', style: const TextStyle(fontSize: 16)),
                    subtitle: l.qtd > 1 ? Text('${dinheiro(l.preco)} cada') : null,
                    trailing: Text(dinheiro(l.total), style: const TextStyle(fontSize: 16)),
                  ),
                const Divider(),
                ListTile(title: const Text('Subtotal'), trailing: Text(reais(c.subtotal), style: const TextStyle(fontSize: 16))),
                if (taxa > 0)
                  SwitchListTile(
                    title: Text('Taxa de serviço (${taxa.toStringAsFixed(taxa % 1 == 0 ? 0 : 1)}%)'),
                    subtitle: _servico ? Text(reais(total - c.subtotal)) : const Text('não cobrar'),
                    value: _servico,
                    onChanged: (v) => setState(() => _servico = v),
                  ),
                ListTile(
                  title: const Text('Dividir por'),
                  subtitle: _pessoas > 1 ? Text('${reais((total / _pessoas).ceil())} por pessoa') : null,
                  trailing: Row(mainAxisSize: MainAxisSize.min, children: [
                    IconButton(onPressed: _pessoas > 1 ? () => setState(() => _pessoas--) : null, icon: const Icon(Icons.remove_circle_outline)),
                    Text('$_pessoas', style: const TextStyle(fontSize: 20)),
                    IconButton(onPressed: () => setState(() => _pessoas++), icon: const Icon(Icons.add_circle_outline)),
                  ]),
                ),
              ]),
            ),
            SafeArea(
              top: false,
              child: Container(
                color: const Color(0xFF1C1D22),
                padding: const EdgeInsets.all(12),
                child: Column(children: [
                  Row(children: [
                    const Text('TOTAL', style: TextStyle(fontSize: 20)),
                    const Spacer(),
                    Text(reais(total), style: const TextStyle(fontSize: 28, fontWeight: FontWeight.bold, color: corAmbar)),
                  ]),
                  const SizedBox(height: 10),
                  Row(children: [
                    Expanded(
                      child: OutlinedButton.icon(
                        icon: const Icon(Icons.print),
                        label: const Text('Imprimir'),
                        onPressed: () => tentar(context, () => a.imprimirConta(c, servico: _servico, pessoas: _pessoas), ok: 'Conta impressa'),
                      ),
                    ),
                    const SizedBox(width: 10),
                    Expanded(
                      child: FilledButton.icon(
                        icon: const Icon(Icons.lock),
                        label: const Text('Fechar'),
                        onPressed: c.aberta
                            ? () async {
                                if (!await confirmar(context, 'Fechar comanda ${c.numero}?', '${c.nome} · ${reais(total)}\n\nConfirme que o pagamento foi recebido.',
                                    sim: 'Fechar')) {
                                  return;
                                }
                                if (!context.mounted) return;
                                if (await tentar(context, () => a.fecharComanda(c, servico: _servico), ok: 'Comanda ${c.numero} fechada') &&
                                    context.mounted) {
                                  Navigator.of(context).popUntil((r) => r.isFirst);
                                }
                              }
                            : null,
                      ),
                    ),
                  ]),
                ]),
              ),
            ),
          ]),
        );
      },
    );
  }
}
