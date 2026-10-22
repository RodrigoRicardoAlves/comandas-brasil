import 'package:flutter/material.dart';

import '../app.dart';
import '../dados/estado.dart';
import '../util.dart';
import 'comanda.dart';
import 'comum.dart';
import 'fechadas.dart';
import 'status.dart';

class TelaInicio extends StatefulWidget {
  const TelaInicio({super.key});
  @override
  State<TelaInicio> createState() => _TelaInicioState();
}

class _TelaInicioState extends State<TelaInicio> {
  String _busca = '';

  Future<void> _abrir() async {
    final c = await dialogoComanda(context);
    if (c != null && mounted) {
      Navigator.push(context, MaterialPageRoute(builder: (_) => TelaComanda(c.uuid)));
    }
  }

  Future<void> _menu(String op) async {
    final a = App.i;
    switch (op) {
      case 'status':
        Navigator.push(context, MaterialPageRoute(builder: (_) => const TelaStatus()));
      case 'fechadas':
        Navigator.push(context, MaterialPageRoute(builder: (_) => const TelaFechadas()));
      case 'trocar':
        await a.trocarUsuario();
      case 'encerrar':
        if (await confirmar(context, 'Encerrar turno?', 'Use quando for embora. Tudo que está neste celular precisa ter chegado ao servidor.',
            sim: 'Encerrar')) {
          if (mounted) await tentar(context, a.encerrarTurno);
        }
    }
  }

  @override
  Widget build(BuildContext context) {
    return ListenableBuilder(
      listenable: App.i,
      builder: (context, _) {
        final a = App.i;
        final e = a.estado;
        var lista = e.abertas;
        if (_busca.isNotEmpty) {
          final b = _busca.toLowerCase();
          lista = lista.where((c) => '${c.numero}' == b || c.nome.toLowerCase().contains(b)).toList();
        }
        return Scaffold(
          appBar: AppBar(
            title: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Text(a.boot!.bar.nome, style: const TextStyle(fontSize: 18)),
              Text('${a.usuario!.nome} · ${e.abertas.length} comanda(s) aberta(s)',
                  style: const TextStyle(fontSize: 13, color: Colors.white60)),
            ]),
            actions: [
              if (a.rede.ativa && a.rede.vivos().isNotEmpty)
                Padding(
                  padding: const EdgeInsets.only(right: 8),
                  child: Icon(a.rede.souLider ? Icons.print : Icons.wifi,
                      color: a.rede.souLider ? corAmbar : (a.rede.liderAlcancavel ? corVerde : corVermelha)),
                ),
              Padding(
                padding: const EdgeInsets.only(right: 4),
                child: Icon(a.online ? Icons.cloud_done : Icons.cloud_off, color: a.online ? corVerde : corVermelha),
              ),
              PopupMenuButton<String>(
                onSelected: _menu,
                itemBuilder: (_) => [
                  const PopupMenuItem(value: 'status', child: ListTile(leading: Icon(Icons.settings), title: Text('Status e impressora'))),
                  const PopupMenuItem(value: 'fechadas', child: ListTile(leading: Icon(Icons.history), title: Text('Comandas fechadas'))),
                  const PopupMenuItem(value: 'trocar', child: ListTile(leading: Icon(Icons.switch_account), title: Text('Trocar garçom'))),
                  const PopupMenuItem(value: 'encerrar', child: ListTile(leading: Icon(Icons.logout), title: Text('Encerrar turno'))),
                ],
              ),
            ],
          ),
          floatingActionButton: FloatingActionButton.extended(
            onPressed: _abrir,
            icon: const Icon(Icons.add),
            label: const Text('Abrir comanda', style: TextStyle(fontSize: 16)),
          ),
          body: Column(children: [
            const BarraStatus(),
            for (final ch in a.chamados) _Chamado(ch),
            Padding(
              padding: const EdgeInsets.fromLTRB(12, 10, 12, 4),
              child: TextField(
                decoration: const InputDecoration(prefixIcon: Icon(Icons.search), hintText: 'Número ou nome', isDense: true),
                onChanged: (v) => setState(() => _busca = v.trim()),
              ),
            ),
            Expanded(
              child: lista.isEmpty
                  ? Center(
                      child: Text(_busca.isEmpty ? 'Nenhuma comanda aberta.\nToque em "Abrir comanda".' : 'Nada encontrado',
                          textAlign: TextAlign.center, style: const TextStyle(color: Colors.white54, fontSize: 16)))
                  : RefreshIndicator(
                      onRefresh: a.ciclo,
                      child: GridView.builder(
                        padding: const EdgeInsets.fromLTRB(12, 8, 12, 96),
                        gridDelegate: const SliverGridDelegateWithMaxCrossAxisExtent(
                            maxCrossAxisExtent: 200, mainAxisExtent: 128, crossAxisSpacing: 10, mainAxisSpacing: 10),
                        itemCount: lista.length,
                        itemBuilder: (_, i) => _CartaoComanda(lista[i]),
                      ),
                    ),
            ),
          ]),
        );
      },
    );
  }
}

class _CartaoComanda extends StatelessWidget {
  final ComandaC c;
  const _CartaoComanda(this.c);

  @override
  Widget build(BuildContext context) {
    final e = App.i.estado;
    final conflito = e.emConflito(c);
    final naoImpresso = c.pedidos.any((p) => !e.pedidoImpresso(p));
    return Card(
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(14),
        side: conflito ? const BorderSide(color: corVermelha, width: 2) : BorderSide.none,
      ),
      child: InkWell(
        borderRadius: BorderRadius.circular(14),
        onTap: () => Navigator.push(context, MaterialPageRoute(builder: (_) => TelaComanda(c.uuid))),
        child: Padding(
          padding: const EdgeInsets.all(12),
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Row(children: [
              Text('${c.numero}', style: const TextStyle(fontSize: 30, fontWeight: FontWeight.bold, color: corAmbar)),
              const Spacer(),
              if (c.contaImpressa) const Icon(Icons.receipt, size: 18, color: corAzul),
            ]),
            Text(c.nome, maxLines: 1, overflow: TextOverflow.ellipsis, style: const TextStyle(fontSize: 16)),
            const Spacer(),
            if (conflito)
              const Text('⚠ número repetido', style: TextStyle(color: corVermelha, fontWeight: FontWeight.w600))
            else if (naoImpresso)
              const Text('🖨 não impresso', style: TextStyle(color: corAmbar))
            else
              Text('${c.quantidade} itens · ${reais(c.subtotal)}', style: const TextStyle(color: Colors.white70)),
          ]),
        ),
      ),
    );
  }
}

class _Chamado extends StatelessWidget {
  final Map<String, dynamic> ch;
  const _Chamado(this.ch);

  @override
  Widget build(BuildContext context) {
    final quem = ch['numero'] != null ? 'Comanda ${ch['numero']}' : '${ch['quem']}';
    return Material(
      color: corAzul.withValues(alpha: .2),
      child: ListTile(
        leading: const Icon(Icons.notifications_active, color: corAzul),
        title: Text('$quem chamou', style: const TextStyle(fontWeight: FontWeight.bold)),
        subtitle: Text('${ch['motivo_texto']}'),
        trailing: FilledButton(onPressed: () => tentar(context, () => App.i.atenderChamado(ch['id'] as int)), child: const Text('Atendido')),
      ),
    );
  }
}

/// Abrir comanda nova (ou editar uma existente).
Future<ComandaC?> dialogoComanda(BuildContext context, {ComandaC? editar}) async {
  final numero = TextEditingController(text: editar != null ? '${editar.numero}' : '');
  final nome = TextEditingController(text: editar?.nome ?? '');
  return showDialog<ComandaC>(
    context: context,
    builder: (c) {
      Future<void> salvar() async {
        final n = int.tryParse(numero.text.trim()) ?? 0;
        await tentar(c, () async {
          if (editar != null) {
            await App.i.editarComanda(editar, n, nome.text);
            if (c.mounted) Navigator.pop(c, editar);
          } else {
            final nova = await App.i.abrirComanda(n, nome.text);
            if (c.mounted) Navigator.pop(c, nova);
          }
        });
      }

      return AlertDialog(
        title: Text(editar != null ? 'Editar comanda' : 'Abrir comanda'),
        content: Column(mainAxisSize: MainAxisSize.min, children: [
          TextField(
            controller: numero,
            autofocus: true,
            keyboardType: TextInputType.number,
            style: const TextStyle(fontSize: 22),
            decoration: const InputDecoration(labelText: 'Número'),
            textInputAction: TextInputAction.next,
          ),
          const SizedBox(height: 12),
          TextField(
            controller: nome,
            textCapitalization: TextCapitalization.words,
            style: const TextStyle(fontSize: 20),
            decoration: const InputDecoration(labelText: 'Nome do cliente'),
            onSubmitted: (_) => salvar(),
          ),
        ]),
        actions: [
          TextButton(onPressed: () => Navigator.pop(c), child: const Text('Cancelar')),
          FilledButton(onPressed: salvar, child: Text(editar != null ? 'Salvar' : 'Abrir')),
        ],
      );
    },
  );
}
