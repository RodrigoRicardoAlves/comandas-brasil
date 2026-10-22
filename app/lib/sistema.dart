import 'package:flutter/services.dart';

/// Ponte com o código Android (android/.../Sistema.kt).
class Sistema {
  static const _c = MethodChannel('comandas/sistema');

  /// Chamado quando o mDNS acha outro celular: (ip, porta, bar, id).
  static void Function(String ip, int porta, String bar, String id)? aoAcharNsd;

  static void iniciar() {
    _c.setMethodCallHandler((call) async {
      if (call.method == 'nsd') {
        final m = (call.arguments as Map).cast<String, dynamic>();
        if (m['ip'] != null && m['id'] != null) {
          aoAcharNsd?.call(m['ip'] as String, m['porta'] as int, (m['bar'] ?? '') as String, m['id'] as String);
        }
      }
      return null;
    });
  }

  static Future<T?> _chamar<T>(String metodo, [Map<String, dynamic>? args]) async {
    try {
      return await _c.invokeMethod<T>(metodo, args);
    } catch (_) {
      return null; // em teste ou fora do Android
    }
  }

  /// economia (bool), rssi (int?), otimizado (bool: sujeito à otimização de bateria), notificacao (bool)
  static Future<Map<String, dynamic>> estado() async =>
      (await _chamar<Map>('estado'))?.cast<String, dynamic>() ?? const {};

  static Future<void> multicast(bool ligar) => _chamar('multicast', {'ligar': ligar});
  static Future<bool> servico(bool ligar, [String texto = '']) async =>
      await _chamar<bool>('servico', {'ligar': ligar, 'texto': texto}) ?? false;
  static Future<void> pedirNotificacao() => _chamar('pedirNotificacao');
  static Future<void> nsdIniciar(int porta, String bar, String id) =>
      _chamar('nsdIniciar', {'porta': porta, 'bar': bar, 'id': id});
  static Future<void> nsdParar() => _chamar('nsdParar');
  static Future<void> abrirBateria() => _chamar('abrirBateria');
}
