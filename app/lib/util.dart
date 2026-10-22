import 'package:intl/intl.dart';

/// 1234 -> "12,34"
String dinheiro(int centavos) {
  final s = NumberFormat('#,##0.00', 'pt_BR').format(centavos.abs() / 100);
  return (centavos < 0 ? '-' : '') + s;
}

String reais(int centavos) => 'R\$ ${dinheiro(centavos)}';

String hhmm(int ms) => DateFormat('HH:mm').format(DateTime.fromMillisecondsSinceEpoch(ms));

String ddmmHhmm(int ms) => DateFormat('dd/MM HH:mm').format(DateTime.fromMillisecondsSinceEpoch(ms));

int agoraMs() => DateTime.now().millisecondsSinceEpoch;

/// Remove espaços sobrando e corta no tamanho máximo.
String limpo(String? s, int max) {
  final t = (s ?? '').trim().split(RegExp(r'\s+')).where((x) => x.isNotEmpty).join(' ');
  return t.length > max ? t.substring(0, max) : t;
}
