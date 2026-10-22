import 'package:flutter/material.dart';

import '../app.dart';
import '../util.dart';
import 'comanda.dart';

/// Comandas fechadas que este celular conhece (últimas horas).
class TelaFechadas extends StatelessWidget {
  const TelaFechadas({super.key});

  @override
  Widget build(BuildContext context) {
    return ListenableBuilder(
      listenable: App.i,
      builder: (context, _) {
        final lista = App.i.estado.fechadas;
        final total = lista.fold(0, (s, c) => s + (c.total ?? 0));
        return Scaffold(
          appBar: AppBar(title: const Text('Comandas fechadas')),
          body: lista.isEmpty
              ? const Center(child: Text('Nenhuma comanda fechada', style: TextStyle(color: Colors.white54)))
              : ListView(children: [
                  if (App.i.usuario!.gerente)
                    ListTile(
                      title: const Text('Total recebido (neste celular)'),
                      trailing: Text(reais(total), style: const TextStyle(fontSize: 18, fontWeight: FontWeight.bold)),
                    ),
                  for (final c in lista)
                    ListTile(
                      leading: Text('${c.numero}', style: const TextStyle(fontSize: 22, fontWeight: FontWeight.bold)),
                      title: Text(c.nome),
                      subtitle: Text('${hhmm(c.fechadaEm!)} · ${c.fechadaPor}'),
                      trailing: Text(reais(c.total ?? 0)),
                      onTap: () => Navigator.push(context, MaterialPageRoute(builder: (_) => TelaComanda(c.uuid))),
                    ),
                ]),
        );
      },
    );
  }
}
