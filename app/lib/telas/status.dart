import 'package:flutter/material.dart';

import '../app.dart';
import '../impressao/impressora.dart';
import '../sistema.dart';
import 'bateria.dart';
import 'comum.dart';

/// Situação do celular, da conexão e da impressora.
class TelaStatus extends StatefulWidget {
  const TelaStatus({super.key});
  @override
  State<TelaStatus> createState() => _TelaStatusState();
}

class _TelaStatusState extends State<TelaStatus> {
  late final _impressora = TextEditingController(text: App.i.impressoraLocal);
  bool _temInterna = false;

  @override
  void initState() {
    super.initState();
    Sistema.temImpressoraInterna().then((v) {
      if (mounted) setState(() => _temInterna = v);
    });
  }

  Future<void> _usar(String v) async {
    _impressora.text = v;
    await App.i.definirImpressoraLocal(v);
    if (mounted) aviso(context, v.isEmpty ? 'Voltou para a impressora do bar' : 'Esta maquininha vai imprimir');
  }

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
                  hintText: 'ex.: 192.168.1.50:9100 ou maquininha',
                  helperText: 'Vazio = usa a do bar',
                ),
                keyboardType: TextInputType.url,
                onSubmitted: a.definirImpressoraLocal,
              ),
            ),
            if (_temInterna)
              Padding(
                padding: const EdgeInsets.fromLTRB(16, 4, 16, 12),
                child: Impressora.ehInterna(a.impressoraLocal)
                    ? OutlinedButton.icon(
                        icon: const Icon(Icons.print_disabled),
                        onPressed: () => _usar(''),
                        label: const Text('Parar de usar a impressora da maquininha'),
                      )
                    : FilledButton.tonalIcon(
                        icon: const Icon(Icons.point_of_sale),
                        onPressed: () => _usar(Impressora.interna),
                        label: const Text('Usar a impressora desta maquininha'),
                      ),
              ),
            if (_temInterna && Impressora.ehInterna(a.impressoraLocal))
              const Padding(
                padding: EdgeInsets.fromLTRB(16, 0, 16, 8),
                child: Text(
                  'Os pedidos de todos os garçons saem aqui: esta maquininha vira o líder da rede '
                  '(deixe-a ligada, no Wi-Fi do bar e de preferência carregando).',
                  style: TextStyle(fontSize: 13, color: Colors.white70),
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
            const _Titulo('Rede local (Wi-Fi do bar)'),
            if (!a.rede.ativa) const ListTile(dense: true, title: Text('Desligada (entre com o PIN)')),
            if (a.rede.ativa) ...[
              linha('Líder', a.rede.nomeDe(a.rede.eleicao.lider),
                  cor: a.rede.souLider ? corAmbar : (a.rede.liderAlcancavel ? corVerde : corVermelha)),
              linha('Mandato', '${a.rede.eleicao.termo}'),
              linha('Nota deste celular', '${a.rede.nota}${a.rede.elegivel ? '' : ' (bateria baixa: não lidera)'}'),
              linha('IP deste celular', a.rede.meuIp ?? '?'),
              if (a.rede.servicoLigado) linha('Serviço do líder', 'ligado (notificação fixa)', cor: corAmbar),
              if (a.rede.sistema['economia'] == true) linha('Economia de bateria', 'ligada (−30 na nota)', cor: corAmbar),
              if (a.rede.erroServidor != null) ListTile(dense: true, title: Text(a.rede.erroServidor!, style: const TextStyle(color: corVermelha))),
              if (a.rede.isolamento)
                const ListTile(
                  dense: true,
                  leading: Icon(Icons.wifi_off, color: corVermelha),
                  title: Text('Esta rede não deixa os celulares conversarem (isolamento de clientes). Use a rede principal do bar.'),
                ),
              for (final p in a.rede.pares.values)
                ListTile(
                  dense: true,
                  leading: Icon(p.id == a.rede.eleicao.lider ? Icons.print : Icons.phone_android,
                      color: p.vivo(DateTime.now().millisecondsSinceEpoch) ? corVerde : corVermelha),
                  title: Text('${p.usuario.isEmpty ? '?' : p.usuario} · ${p.modelo.isEmpty ? p.id.substring(0, 6) : p.modelo}'),
                  subtitle: Text('${p.ip}:${p.porta} · nota ${p.nota} · mandato ${p.termo} · via ${p.origens.join(', ')}'
                      '${p.falhas > 0 ? ' · ${p.falhas} falha(s)' : ''}'),
                  trailing: Text('${p.bateria ?? '?'}%${p.carregando ? ' ⚡' : ''}'),
                ),
              if (a.rede.pares.isEmpty) const ListTile(dense: true, title: Text('Nenhum outro celular encontrado')),
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
                child: OutlinedButton.icon(
                  icon: Icon(a.rede.sistema['otimizado'] == true ? Icons.battery_alert : Icons.battery_charging_full,
                      color: a.rede.sistema['otimizado'] == true ? corAmbar : null),
                  onPressed: () => Navigator.push(context, MaterialPageRoute(builder: (_) => const TelaBateria())),
                  label: Text(a.rede.sistema['otimizado'] == true
                      ? 'App sujeito à economia de bateria: corrigir'
                      : 'Guia de bateria e segundo plano'),
                ),
              ),
              for (final l in a.rede.registro.take(6))
                Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 1),
                  child: Text(l, style: const TextStyle(fontSize: 12, color: Colors.white54)),
                ),
            ],
            const _Titulo('Celulares no servidor (internet)'),
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
