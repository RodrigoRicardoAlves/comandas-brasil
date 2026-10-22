import 'dart:convert';

import 'package:http/http.dart' as http;

/// Conversa com o servidor (VPS).
class Api {
  String base; // ex.: https://bar.rodrigoricardo.eng.br
  String? token;
  Api(this.base, {this.token});

  Uri _u(String p) => Uri.parse('${base.replaceAll(RegExp(r'/+$'), '')}/api/v1$p');

  Map<String, String> get _h => {
        'Content-Type': 'application/json',
        if (token != null) 'Authorization': 'Bearer $token',
      };

  Future<Map<String, dynamic>> get(String p, {Duration tempo = const Duration(seconds: 10)}) async =>
      _tratar(await http.get(_u(p), headers: _h).timeout(tempo));

  Future<Map<String, dynamic>> post(String p, [Object? corpo, Duration tempo = const Duration(seconds: 10)]) async =>
      _tratar(await http.post(_u(p), headers: _h, body: jsonEncode(corpo ?? {})).timeout(tempo));

  Map<String, dynamic> _tratar(http.Response r) {
    Map<String, dynamic> j;
    try {
      j = jsonDecode(utf8.decode(r.bodyBytes)) as Map<String, dynamic>;
    } catch (_) {
      j = {};
    }
    if (r.statusCode >= 400) throw ErroApi(r.statusCode, (j['detail'] ?? 'Erro ${r.statusCode} no servidor').toString());
    return j;
  }
}

class ErroApi implements Exception {
  final int status;
  final String msg;
  ErroApi(this.status, this.msg);
  @override
  String toString() => msg;
}
