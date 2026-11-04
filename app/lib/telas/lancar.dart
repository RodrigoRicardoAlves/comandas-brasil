import 'package:flutter/material.dart';

import '../app.dart';
import '../dados/modelos.dart';
import '../util.dart';
import 'comum.dart';

/// Escolher produtos do cardápio e enviar o pedido.
class TelaLancar extends StatefulWidget {
  final String comanda;
  const TelaLancar(this.comanda, {super.key});
  @override
  State<TelaLancar> createState() => _TelaLancarState();
}

class _TelaLancarState extends State<TelaLancar> {
  final List<ItemCarrinho> _carrinho = [];
  bool _enviando = false;

  int get _qtd => _carrinho.fold(0, (s, i) => s + i.qtd);
  int get _total => _carrinho.fold(0, (s, i) => s + i.total);

  void _adicionar(Produto p, Variante v) {
    setState(() {
      final igual = p.ehAvulso ? null : _carrinho.where((i) => i.variante.id == v.id && i.obs.isEmpty).firstOrNull;
      if (igual != null) {
        igual.qtd++;
      } else {
        _carrinho.add(ItemCarrinho(p, v));
      }
    });
    ScaffoldMessenger.of(context)
      ..hideCurrentSnackBar()
      ..showSnackBar(SnackBar(
          content: Text('+1 ${p.nome} ${v.nome}'.trim()), duration: const Duration(milliseconds: 700), behavior: SnackBarBehavior.floating));
  }

  void _tocarProduto(Produto p) {
    if (p.esgotado) {
      aviso(context, '${p.nome} está esgotado', erro: true);
      return;
    }
    if (p.variantes.length == 1) return _adicionar(p, p.variantes.first);
    showModalBottomSheet(
      context: context,
      builder: (c) => SafeArea(
        child: Column(mainAxisSize: MainAxisSize.min, children: [
          Padding(padding: const EdgeInsets.all(16), child: Text(p.nome, style: const TextStyle(fontSize: 20, fontWeight: FontWeight.bold))),
          for (final v in p.variantes)
            ListTile(
              title: Text(v.nome, style: const TextStyle(fontSize: 18)),
              trailing: Text(reais(v.preco), style: const TextStyle(fontSize: 17)),
              onTap: () {
                Navigator.pop(c);
                _adicionar(p, v);
              },
            ),
          const SizedBox(height: 8),
        ]),
      ),
    );
  }

  /// Produto fora do cardápio: o garçom digita nome e preço.
  Future<void> _avulso() async {
    final setores = App.i.boot!.setores.map((s) => s.nome).toList();
    final nomeCtl = TextEditingController();
    final precoCtl = TextEditingController();
    final chave = GlobalKey<FormState>();
    var setor = '';
    final p = await showDialog<Produto>(
      context: context,
      builder: (c) => StatefulBuilder(
        builder: (c, set) {
          void ok() {
            if (!chave.currentState!.validate()) return;
            Navigator.pop(c, Produto.avulso(limpo(nomeCtl.text, 60), lerCentavos(precoCtl.text)!, setor: setor));
          }

          return AlertDialog(
            title: const Text('Produto avulso'),
            content: Form(
              key: chave,
              child: Column(mainAxisSize: MainAxisSize.min, children: [
                TextFormField(
                  controller: nomeCtl,
                  autofocus: true,
                  maxLength: 60,
                  textCapitalization: TextCapitalization.sentences,
                  decoration: const InputDecoration(labelText: 'Nome do produto'),
                  validator: (v) => limpo(v, 60).isEmpty ? 'Digite o nome' : null,
                ),
                TextFormField(
                  controller: precoCtl,
                  keyboardType: const TextInputType.numberWithOptions(decimal: true),
                  decoration: const InputDecoration(labelText: 'Preço', prefixText: 'R\$ ', hintText: '0,00'),
                  validator: (v) {
                    final c = lerCentavos(v);
                    if (c == null || c <= 0) return 'Preço inválido';
                    if (c > 100000) return 'Máximo R\$ 1.000,00';
                    return null;
                  },
                  onFieldSubmitted: (_) => ok(),
                ),
                if (setores.isNotEmpty)
                  DropdownButtonFormField<String>(
                    initialValue: setor,
                    decoration: const InputDecoration(labelText: 'Imprimir cupom'),
                    items: [
                      const DropdownMenuItem(value: '', child: Text('Não imprime')),
                      for (final s in setores) DropdownMenuItem(value: s, child: Text(s)),
                    ],
                    onChanged: (v) => set(() => setor = v ?? ''),
                  ),
              ]),
            ),
            actions: [
              TextButton(onPressed: () => Navigator.pop(c), child: const Text('Voltar')),
              FilledButton(onPressed: ok, child: const Text('Adicionar')),
            ],
          );
        },
      ),
    );
    nomeCtl.dispose();
    precoCtl.dispose();
    if (p != null && mounted) _adicionar(p, p.variantes.first);
  }

  Future<void> _revisar() async {
    await showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      builder: (c) => StatefulBuilder(builder: (c, set) {
        void mudar(VoidCallback f) {
          setState(f);
          set(() {});
        }

        return SafeArea(
          child: Padding(
            padding: EdgeInsets.only(bottom: MediaQuery.of(c).viewInsets.bottom),
            child: ConstrainedBox(
              constraints: BoxConstraints(maxHeight: MediaQuery.of(c).size.height * .85),
              child: Column(mainAxisSize: MainAxisSize.min, children: [
                const Padding(padding: EdgeInsets.all(14), child: Text('Pedido', style: TextStyle(fontSize: 20, fontWeight: FontWeight.bold))),
                Flexible(
                  child: ListView(shrinkWrap: true, children: [
                    for (final it in _carrinho)
                      Padding(
                        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
                        child: Column(children: [
                          Row(children: [
                            Expanded(
                              child: Text('${it.produto.nome} ${it.variante.nome}'.trim(), style: const TextStyle(fontSize: 17)),
                            ),
                            IconButton(
                                icon: const Icon(Icons.remove_circle_outline),
                                onPressed: () => mudar(() {
                                      it.qtd--;
                                      if (it.qtd <= 0) _carrinho.remove(it);
                                    })),
                            Text('${it.qtd}', style: const TextStyle(fontSize: 20, fontWeight: FontWeight.bold)),
                            IconButton(icon: const Icon(Icons.add_circle_outline), onPressed: () => mudar(() => it.qtd = (it.qtd + 1).clamp(1, 99))),
                          ]),
                          TextFormField(
                            initialValue: it.obs,
                            decoration: const InputDecoration(hintText: 'Observação (ex.: sem cebola)', isDense: true),
                            onChanged: (v) => it.obs = v,
                          ),
                        ]),
                      ),
                  ]),
                ),
                Padding(
                  padding: const EdgeInsets.all(12),
                  child: SizedBox(
                    width: double.infinity,
                    child: FilledButton(
                      onPressed: _carrinho.isEmpty
                          ? null
                          : () {
                              Navigator.pop(c);
                              _enviar();
                            },
                      child: Text('Enviar $_qtd item(ns) · ${reais(_total)}'),
                    ),
                  ),
                ),
              ]),
            ),
          ),
        );
      }),
    );
  }

  Future<void> _enviar() async {
    final c = App.i.estado.comandas[widget.comanda]!;
    setState(() => _enviando = true);
    final ok = await tentar(context, () => App.i.lancarPedido(c, List.of(_carrinho)), ok: 'Pedido lançado na comanda ${c.numero}');
    if (!mounted) return;
    setState(() => _enviando = false);
    if (ok) Navigator.pop(context);
  }

  @override
  Widget build(BuildContext context) {
    final a = App.i;
    final c = a.estado.comandas[widget.comanda]!;
    final cats = a.boot!.cardapio;
    return DefaultTabController(
      length: cats.length,
      child: Scaffold(
        appBar: AppBar(
          title: Text('Pedido · ${c.numero} ${c.nome}'),
          actions: [
            TextButton.icon(onPressed: _avulso, icon: const Icon(Icons.edit_note), label: const Text('Avulso')),
          ],
          bottom: TabBar(isScrollable: true, tabAlignment: TabAlignment.start, tabs: [for (final k in cats) Tab(text: k.nome)]),
        ),
        body: TabBarView(children: [
          for (final k in cats)
            ListView.separated(
              padding: const EdgeInsets.only(bottom: 100),
              itemCount: k.produtos.length,
              separatorBuilder: (_, _) => const Divider(height: 1),
              itemBuilder: (_, i) {
                final p = k.produtos[i];
                final qtd = _carrinho.where((x) => x.produto.id == p.id).fold(0, (s, x) => s + x.qtd);
                return ListTile(
                  minVerticalPadding: 14,
                  title: Text(p.nome, style: TextStyle(fontSize: 18, color: p.esgotado ? Colors.white38 : null)),
                  subtitle: Text(
                    p.esgotado
                        ? 'esgotado'
                        : p.variantes.map((v) => v.nome.isEmpty ? reais(v.preco) : '${v.nome} ${dinheiro(v.preco)}').join('  ·  '),
                  ),
                  trailing: qtd > 0
                      ? CircleAvatar(backgroundColor: corAmbar, child: Text('$qtd', style: const TextStyle(color: Colors.black, fontWeight: FontWeight.bold)))
                      : (p.imprime ? const Icon(Icons.print_outlined, size: 18, color: Colors.white24) : null),
                  onTap: () => _tocarProduto(p),
                );
              },
            ),
        ]),
        bottomNavigationBar: _carrinho.isEmpty
            ? null
            : SafeArea(
                child: Padding(
                  padding: const EdgeInsets.all(12),
                  child: Row(children: [
                    Expanded(
                      child: OutlinedButton(onPressed: _revisar, child: Text('Ver pedido ($_qtd)')),
                    ),
                    const SizedBox(width: 10),
                    Expanded(
                      child: FilledButton(
                        onPressed: _enviando ? null : _enviar,
                        child: Text(_enviando ? 'Enviando...' : 'Enviar · ${dinheiro(_total)}'),
                      ),
                    ),
                  ]),
                ),
              ),
      ),
    );
  }
}
