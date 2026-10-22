import 'dart:convert';

import 'package:crypto/crypto.dart';

/// Assinatura das mensagens da rede local com a chave do bar (lan_key).
/// Impede que um celular qualquer na mesma Wi-Fi mande pedidos falsos ou se passe por líder.
class Assinatura {
  static const validade = Duration(minutes: 10); // tolera relógios um pouco diferentes
  final List<int> _chave;
  Assinatura(String lanKey) : _chave = utf8.encode(lanKey);

  String _hmac(String texto) => Hmac(sha256, _chave).convert(utf8.encode(texto)).toString();

  /// Valor do cabeçalho: `hora_ms.hmac`
  String assinar(String contexto, String corpo, {int? hora}) {
    final h = hora ?? DateTime.now().millisecondsSinceEpoch;
    return '$h.${_hmac('$h\n$contexto\n$corpo')}';
  }

  bool confere(String? cabecalho, String contexto, String corpo) {
    if (cabecalho == null) return false;
    final i = cabecalho.indexOf('.');
    if (i <= 0) return false;
    final h = int.tryParse(cabecalho.substring(0, i));
    if (h == null) return false;
    if ((DateTime.now().millisecondsSinceEpoch - h).abs() > validade.inMilliseconds) return false;
    return _iguais(cabecalho.substring(i + 1), _hmac('$h\n$contexto\n$corpo'));
  }

  static bool _iguais(String a, String b) {
    if (a.length != b.length) return false;
    var d = 0;
    for (var i = 0; i < a.length; i++) {
      d |= a.codeUnitAt(i) ^ b.codeUnitAt(i);
    }
    return d == 0;
  }
}
