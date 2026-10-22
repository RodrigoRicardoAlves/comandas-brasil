import 'package:flutter/material.dart';

import '../app.dart';
import 'comum.dart';

/// Tela de PIN do dia a dia (funciona sem internet).
class TelaPin extends StatefulWidget {
  const TelaPin({super.key});
  @override
  State<TelaPin> createState() => _TelaPinState();
}

class _TelaPinState extends State<TelaPin> {
  String _pin = '';
  String? _erro;

  Future<void> _ok() async {
    try {
      await App.i.entrarComPin(_pin);
    } catch (e) {
      setState(() {
        _erro = e.toString();
        _pin = '';
      });
    }
  }

  Future<void> _outroBar() async {
    if (await confirmar(context, 'Entrar em outro bar?', 'Você vai precisar do código do bar e de internet.')) {
      App.i.esquecerBar();
    }
  }

  @override
  Widget build(BuildContext context) {
    final a = App.i;
    return Scaffold(
      body: SafeArea(
        child: Column(children: [
          const BarraStatus(),
          Expanded(
            child: Center(
              child: SingleChildScrollView(
                padding: const EdgeInsets.all(20),
                child: ConstrainedBox(
                  constraints: const BoxConstraints(maxWidth: 380),
                  child: Column(children: [
                    Text(a.boot!.bar.nome, style: const TextStyle(fontSize: 24, fontWeight: FontWeight.bold)),
                    const SizedBox(height: 6),
                    const Text('Digite seu PIN', style: TextStyle(color: Colors.white70, fontSize: 16)),
                    const SizedBox(height: 18),
                    Text(_pin.isEmpty ? '• • • •' : '●' * _pin.length, style: const TextStyle(fontSize: 34, letterSpacing: 8)),
                    SizedBox(height: 28, child: _erro == null ? null : Text(_erro!, style: const TextStyle(color: corVermelha, fontSize: 16))),
                    TecladoNumerico(
                      aoDigitar: (d) => setState(() {
                        if (_pin.length < 8) _pin += d;
                        _erro = null;
                      }),
                      aoApagar: () => setState(() => _pin = _pin.isEmpty ? '' : _pin.substring(0, _pin.length - 1)),
                      aoConfirmar: _pin.length >= 4 ? _ok : null,
                    ),
                    const SizedBox(height: 16),
                    TextButton(onPressed: _outroBar, child: const Text('Outro bar / primeiro acesso')),
                  ]),
                ),
              ),
            ),
          ),
        ]),
      ),
    );
  }
}
