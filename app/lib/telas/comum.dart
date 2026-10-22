import 'package:flutter/material.dart';

import '../app.dart';

const corVerde = Color(0xFF3DDC84);
const corVermelha = Color(0xFFFF5A5F);
const corAmbar = Color(0xFFFFB020);
const corAzul = Color(0xFF5AB0FF);

void aviso(BuildContext context, String msg, {bool erro = false, int segundos = 3}) {
  ScaffoldMessenger.of(context)
    ..hideCurrentSnackBar()
    ..showSnackBar(SnackBar(
      content: Text(msg, style: const TextStyle(fontSize: 16, color: Colors.white)),
      backgroundColor: erro ? const Color(0xFF8B1E24) : const Color(0xFF2E3A2E),
      duration: Duration(seconds: segundos),
      behavior: SnackBarBehavior.floating,
    ));
}

/// Executa uma ação mostrando o erro de forma amigável. Devolve true se deu certo.
Future<bool> tentar(BuildContext context, Future<void> Function() f, {String? ok}) async {
  try {
    await f();
    if (ok != null && context.mounted) aviso(context, ok);
    return true;
  } catch (e) {
    if (context.mounted) aviso(context, e.toString().replaceFirst('Exception: ', ''), erro: true, segundos: 5);
    return false;
  }
}

Future<bool> confirmar(BuildContext context, String titulo, String texto, {String sim = 'Confirmar', bool perigo = false}) async {
  final r = await showDialog<bool>(
    context: context,
    builder: (c) => AlertDialog(
      title: Text(titulo),
      content: Text(texto, style: const TextStyle(fontSize: 16)),
      actions: [
        TextButton(onPressed: () => Navigator.pop(c, false), child: const Text('Voltar')),
        FilledButton(
          style: perigo ? FilledButton.styleFrom(backgroundColor: corVermelha) : null,
          onPressed: () => Navigator.pop(c, true),
          child: Text(sim),
        ),
      ],
    ),
  );
  return r == true;
}

/// Teclado numérico grande para PIN e números.
class TecladoNumerico extends StatelessWidget {
  final void Function(String) aoDigitar;
  final VoidCallback aoApagar;
  final VoidCallback? aoConfirmar;
  const TecladoNumerico({super.key, required this.aoDigitar, required this.aoApagar, this.aoConfirmar});

  @override
  Widget build(BuildContext context) {
    Widget tecla(Widget filho, VoidCallback? f, {Color? cor}) => Padding(
          padding: const EdgeInsets.all(5),
          child: SizedBox(
            height: 64,
            child: FilledButton.tonal(
              style: FilledButton.styleFrom(backgroundColor: cor, shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14))),
              onPressed: f,
              child: filho,
            ),
          ),
        );
    Widget n(String d) => tecla(Text(d, style: const TextStyle(fontSize: 28)), () => aoDigitar(d));
    return Column(mainAxisSize: MainAxisSize.min, children: [
      for (final linha in [['1', '2', '3'], ['4', '5', '6'], ['7', '8', '9']])
        Row(children: [for (final d in linha) Expanded(child: n(d))]),
      Row(children: [
        Expanded(child: tecla(const Icon(Icons.backspace_outlined, size: 26), aoApagar)),
        Expanded(child: n('0')),
        Expanded(
          child: tecla(const Icon(Icons.check, size: 30), aoConfirmar,
              cor: aoConfirmar == null ? null : Theme.of(context).colorScheme.primary.withValues(alpha: .35)),
        ),
      ]),
    ]);
  }
}

/// Pede o PIN de um gerente. Devolve o nome do gerente ou null.
Future<String?> pedirPinGerente(BuildContext context, String motivo) async {
  var pin = '';
  String? erro;
  return showDialog<String>(
    context: context,
    builder: (c) => StatefulBuilder(
      builder: (c, set) => AlertDialog(
        title: const Text('PIN do gerente'),
        content: SizedBox(
          width: 320,
          child: Column(mainAxisSize: MainAxisSize.min, children: [
            Text(motivo, textAlign: TextAlign.center),
            const SizedBox(height: 12),
            Text(pin.isEmpty ? '• • • •' : '●' * pin.length, style: const TextStyle(fontSize: 28, letterSpacing: 6)),
            if (erro != null) Text(erro!, style: const TextStyle(color: corVermelha)),
            const SizedBox(height: 8),
            TecladoNumerico(
              aoDigitar: (d) => set(() {
                if (pin.length < 8) pin += d;
                erro = null;
              }),
              aoApagar: () => set(() => pin = pin.isEmpty ? '' : pin.substring(0, pin.length - 1)),
              aoConfirmar: () {
                final g = App.i.gerenteDoPin(pin);
                if (g == null) {
                  set(() {
                    erro = 'PIN de gerente incorreto';
                    pin = '';
                  });
                } else {
                  Navigator.pop(c, g.nome);
                }
              },
            ),
          ]),
        ),
        actions: [TextButton(onPressed: () => Navigator.pop(c), child: const Text('Cancelar'))],
      ),
    ),
  );
}

/// Faixa no topo: conexão, fila e impressora.
class BarraStatus extends StatelessWidget {
  const BarraStatus({super.key});

  @override
  Widget build(BuildContext context) {
    return ListenableBuilder(
      listenable: App.i,
      builder: (context, _) {
        final a = App.i;
        final avisos = <(Color, IconData, String)>[];
        final r = a.rede;
        final temRede = r.ativa && r.vivos().isNotEmpty;
        if (r.isolamento) {
          avisos.add((corVermelha, Icons.wifi_off,
              'Esta rede não deixa os celulares conversarem (isolamento de clientes). Use a rede principal do bar.'));
        } else if (r.ativa && r.eleicao.lider == null) {
          avisos.add((corAmbar, Icons.wifi_find, 'Procurando o celular líder...'));
        } else if (temRede && !r.liderAlcancavel) {
          avisos.add((corVermelha, Icons.wifi_off, 'Sem contato com o celular líder'));
        }
        if (!a.temSessaoServidor) {
          avisos.add((corAmbar, Icons.link_off, 'Sessão encerrada no servidor: entre de novo com internet'));
        } else if (!a.online && temRede && r.liderAlcancavel) {
          avisos.add((corAmbar, Icons.cloud_off, 'Sem internet · rede local funcionando'));
        } else if (!a.online) {
          avisos.add((corVermelha, Icons.cloud_off, 'Sem conexão${a.naFila > 0 ? ' · ${a.naFila} na fila' : ''}'));
        } else if (a.naFila > 0) {
          avisos.add((corAmbar, Icons.cloud_upload_outlined, 'Enviando ${a.naFila}...'));
        }
        if (a.erroImpressora != null) avisos.add((corVermelha, Icons.print_disabled, a.erroImpressora!));
        if (avisos.isEmpty) return const SizedBox.shrink();
        return Column(children: [
          for (final (cor, ic, txt) in avisos)
            Material(
              color: cor.withValues(alpha: .18),
              child: InkWell(
                onTap: ic == Icons.print_disabled ? () => App.i.imprimirPendentes(forcar: true) : null,
                child: Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
                  child: Row(children: [
                    Icon(ic, color: cor, size: 20),
                    const SizedBox(width: 10),
                    Expanded(child: Text(txt, style: TextStyle(color: cor, fontWeight: FontWeight.w600))),
                    if (ic == Icons.print_disabled) Text('Tentar de novo', style: TextStyle(color: cor, decoration: TextDecoration.underline)),
                  ]),
                ),
              ),
            ),
        ]);
      },
    );
  }
}
