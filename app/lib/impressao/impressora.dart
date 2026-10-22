import 'dart:async';
import 'dart:io';

/// Envia bytes para a impressora térmica de rede (porta 9100).
/// Um cupom por vez: a impressora aceita uma conexão de cada vez.
class Impressora {
  static Future<void> _fila = Future.value();

  static Future<void> enviar(String alvo, List<int> bytes) {
    final c = Completer<void>();
    _fila = _fila.then((_) async {
      try {
        await _enviar(alvo, bytes);
        c.complete();
      } catch (e) {
        c.completeError(e);
      }
    });
    return c.future;
  }

  static Future<void> _enviar(String alvo, List<int> bytes) async {
    final a = alvo.trim().replaceFirst(RegExp(r'^tcp://'), '');
    if (a.isEmpty) throw ErroImpressora('Impressora não configurada');
    final partes = a.split(':');
    final host = partes[0];
    final porta = partes.length > 1 ? int.tryParse(partes[1]) ?? 9100 : 9100;
    Socket s;
    try {
      s = await Socket.connect(host, porta, timeout: const Duration(seconds: 5));
    } on SocketException catch (e) {
      final m = (e.osError?.message ?? e.message).toLowerCase();
      if (m.contains('refused')) throw ErroImpressora('A impressora $a recusou a conexão');
      throw ErroImpressora('Impressora $a não respondeu (desligada ou fora da rede?)');
    }
    try {
      s.add(bytes);
      await s.flush().timeout(const Duration(seconds: 10));
    } on TimeoutException {
      throw ErroImpressora('Impressora $a travou no meio do envio (sem papel?)');
    } finally {
      await s.close().timeout(const Duration(seconds: 3), onTimeout: () => s.destroy());
    }
  }
}

class ErroImpressora implements Exception {
  final String msg;
  ErroImpressora(this.msg);
  @override
  String toString() => msg;
}
