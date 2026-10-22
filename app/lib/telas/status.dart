import 'package:flutter/material.dart';

import '../app.dart';
import 'comum.dart';

/// Situação do celular, da conexão e da impressora.
class TelaStatus extends StatefulWidget {
  const TelaStatus({super.key});
  @override
  State<TelaStatus> createState() => _TelaStatusState();
}

class _TelaStatusState extends State<TelaStatus> {
  late final _impressora = TextEditingController(text: App.i.impressoraLocal);

  @override
  Widget build(BuildContext context) {
    return ListenableBuilder(
      listenable: App.i,
      builder: (context, _) {
        final a = App.i;
        final b = a.boot!.bar;
        Widget linha(String t, String v, {Color? cor}) => ListTile(
              dense: true,
              title: Text(t),
              trailing: Text(v, style: TextStyle(fontSize: 15, color: cor)),
            );
        return Scaffold(
          appBar: AppBar(title: const Text('Status e impressora')),
          body: ListView(padding: const EdgeInsets.all(8), children: [
            const BarraStatus(),
            const _Titulo('Conexão'),
            linha('Servidor', a.online ? 'conectado' : 'sem conexão', cor: a.online ? corVerde : corVermelha),
            linha('Na fila para enviar', '${a.naFila}', cor: a.naFila > 0 ? corAmbar : null),
            linha('Endereço', a.servidor),
            const _Titulo('Impressora'),
            linha('Do bar (configurada no painel)', b.impressora.isEmpty ? 'não configurada' : b.impressora),
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
              child: TextField(
                controller: _impressora,
                decoration: const InputDecoration(
                  labelText: 'Usar outra neste celular (opcional)',
                  hintText: 'ex.: 192.168.1.50:9100',
                  helperText: 'Vazio = usa a do bar',
                ),
                keyboardType: TextInputType.url,
                onSubmitted: a.definirImpressoraLocal,
              ),
            ),
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 16),
              child: Row(children: [
                Expanded(
                  child: OutlinedButton(
                    onPressed: () async {
                      await a.definirImpressoraLocal(_impressora.text);
                      if (context.mounted) aviso(context, 'Salvo');
                    },
                    child: const Text('Salvar'),
                  ),
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: FilledButton(
                    onPressed: () async {
                      await a.definirImpressoraLocal(_impressora.text);
                      if (context.mounted) await tentar(context, a.imprimirTeste, ok: 'Teste enviado');
                    },
                    child: const Text('Imprimir teste'),
                  ),
                ),
              ]),
            ),
            if (a.cuponsNaoImpressos > 0)
              Padding(
                padding: const EdgeInsets.all(16),
                child: FilledButton.tonal(
                  onPressed: () => a.imprimirPendentes(forcar: true),
                  child: Text('Imprimir ${a.cuponsNaoImpressos} cupom(ns) pendente(s)'),
                ),
              ),
            const _Titulo('Setores de impressão'),
            for (final s in a.boot!.setores) linha(s.nome, s.impressora.isEmpty ? 'impressora do bar' : s.impressora),
            const _Titulo('Celulares conectados'),
            if (a.aparelhos.isEmpty) const ListTile(dense: true, title: Text('—')),
            for (final ap in a.aparelhos)
              ListTile(
                dense: true,
                leading: Icon(ap['device_id'] == a.deviceId ? Icons.smartphone : Icons.phone_android),
                title: Text('${ap['usuario']} · ${ap['modelo']}'),
                subtitle: Text('IP ${ap['ip'] ?? '-'}${ap['pendentes'] != null && ap['pendentes'] > 0 ? ' · ${ap['pendentes']} na fila' : ''}'),
                trailing: Text('${ap['bateria'] ?? '?'}%${ap['carregando'] == true ? ' ⚡' : ''}'),
              ),
            const _Titulo('Este celular'),
            linha('Aparelho', a.modelo),
            linha('Bateria', '${a.bateria ?? '?'}%${a.carregando ? ' (carregando)' : ''}'),
            linha('Versão do app', a.versaoApp),
            linha('Cardápio', 'versão ${b.versaoCardapio}'),
            Padding(
              padding: const EdgeInsets.all(16),
              child: OutlinedButton(
                onPressed: () => tentar(context, a.atualizarCardapio, ok: 'Cardápio atualizado'),
                child: const Text('Atualizar cardápio agora'),
              ),
            ),
          ]),
        );
      },
    );
  }
}

class _Titulo extends StatelessWidget {
  final String t;
  const _Titulo(this.t);
  @override
  Widget build(BuildContext context) => Padding(
        padding: const EdgeInsets.fromLTRB(16, 20, 16, 4),
        child: Text(t.toUpperCase(), style: const TextStyle(color: corAmbar, fontWeight: FontWeight.bold, letterSpacing: 1)),
      );
}
