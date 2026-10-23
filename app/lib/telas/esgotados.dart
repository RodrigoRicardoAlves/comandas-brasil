import 'package:flutter/material.dart';

import '../app.dart';
import 'comum.dart';

/// Gerente: marcar produto esgotado / disponível (precisa de internet).
class TelaEsgotados extends StatefulWidget {
  const TelaEsgotados({super.key});
  @override
  State<TelaEsgotados> createState() => _TelaEsgotadosState();
}

class _TelaEsgotadosState extends State<TelaEsgotados> {
  final Set<int> _salvando = {};

  Future<void> _mudar(int id, bool esgotado) async {
    setState(() => _salvando.add(id));
    await tentar(context, () => App.i.marcarEsgotado(id, esgotado), ok: esgotado ? 'Marcado como esgotado' : 'Disponível de novo');
    if (mounted) setState(() => _salvando.remove(id));
  }

  @override
  Widget build(BuildContext context) {
    return ListenableBuilder(
      listenable: App.i,
      builder: (context, _) {
        final cats = App.i.boot!.cardapio;
        return Scaffold(
          appBar: AppBar(title: const Text('Esgotados')),
          body: ListView(children: [
            const BarraStatus(),
            const Padding(
              padding: EdgeInsets.fromLTRB(16, 12, 16, 4),
              child: Text('Ligue a chave do que acabou. Some do cardápio dos clientes e os garçons não conseguem lançar. '
                  'Precisa de internet. Preços e produtos novos: painel do gerente no navegador.',
                  style: TextStyle(color: Colors.white70)),
            ),
            for (final c in cats) ...[
              Padding(
                padding: const EdgeInsets.fromLTRB(16, 18, 16, 4),
                child: Text(c.nome.toUpperCase(), style: const TextStyle(color: corAmbar, fontWeight: FontWeight.bold, letterSpacing: 1)),
              ),
              for (final p in c.produtos)
                SwitchListTile(
                  title: Text(p.nome, style: TextStyle(fontSize: 17, color: p.esgotado ? corVermelha : null)),
                  subtitle: Text(p.esgotado ? 'ESGOTADO' : 'disponível'),
                  value: p.esgotado,
                  onChanged: _salvando.contains(p.id) ? null : (v) => _mudar(p.id, v),
                ),
            ],
          ]),
        );
      },
    );
  }
}
