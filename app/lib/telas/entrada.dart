import 'package:flutter/material.dart';

import '../app.dart';
import 'comum.dart';

/// Primeiro acesso do celular (precisa de internet): servidor, código do bar e PIN.
class TelaEntrada extends StatefulWidget {
  const TelaEntrada({super.key});
  @override
  State<TelaEntrada> createState() => _TelaEntradaState();
}

class _TelaEntradaState extends State<TelaEntrada> {
  final _servidor = TextEditingController(text: App.i.servidor);
  final _bar = TextEditingController();
  final _pin = TextEditingController();
  bool _enviando = false;
  bool _mostrarServidor = false;

  Future<void> _entrar() async {
    setState(() => _enviando = true);
    await tentar(context, () => App.i.entrarNoBar(_servidor.text, _bar.text, _pin.text));
    if (mounted) setState(() => _enviando = false);
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: SafeArea(
        child: Center(
          child: SingleChildScrollView(
            padding: const EdgeInsets.all(24),
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 420),
              child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
                Image.asset('assets/logo.png', height: 190, semanticLabel: 'Comandas Brasil'),
                const SizedBox(height: 10),
                const Text('Primeiro acesso deste celular. Precisa de internet só agora.',
                    textAlign: TextAlign.center, style: TextStyle(color: Colors.white70)),
                const SizedBox(height: 28),
                TextField(
                  controller: _bar,
                  decoration: const InputDecoration(labelText: 'Código do bar', hintText: 'ex.: zemaria'),
                  autocorrect: false,
                  textInputAction: TextInputAction.next,
                ),
                const SizedBox(height: 14),
                TextField(
                  controller: _pin,
                  decoration: const InputDecoration(labelText: 'Seu PIN'),
                  keyboardType: TextInputType.number,
                  obscureText: true,
                  onSubmitted: (_) => _entrar(),
                ),
                const SizedBox(height: 20),
                FilledButton(onPressed: _enviando ? null : _entrar, child: Text(_enviando ? 'Entrando...' : 'Entrar')),
                const SizedBox(height: 18),
                if (_mostrarServidor)
                  TextField(controller: _servidor, decoration: const InputDecoration(labelText: 'Endereço do servidor'), autocorrect: false)
                else
                  TextButton(
                    onPressed: () => setState(() => _mostrarServidor = true),
                    child: Text('Servidor: ${App.i.servidor}', style: const TextStyle(color: Colors.white54)),
                  ),
              ]),
            ),
          ),
        ),
      ),
    );
  }
}
