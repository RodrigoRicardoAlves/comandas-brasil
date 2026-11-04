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

/// "12,50", "12.50", "R$ 1.234,50" ou "12" -> centavos. Null se não for um valor.
int? lerCentavos(String? s) {
  var t = (s ?? '').replaceAll(RegExp(r'[R$\s]'), '');
  if (t.isEmpty) return null;
  final virgula = t.lastIndexOf(','), ponto = t.lastIndexOf('.');
  final sep = virgula > ponto ? virgula : ponto;
  // separador de centavos só se tiver 1 ou 2 dígitos depois dele; o resto é milhar
  if (sep >= 0 && t.length - sep - 1 <= 2) {
    t = '${t.substring(0, sep).replaceAll(RegExp(r'[.,]'), '')}.${t.substring(sep + 1)}';
  } else {
    t = t.replaceAll(RegExp(r'[.,]'), '');
  }
  final v = double.tryParse(t);
  return v == null ? null : (v * 100).round();
}

/// Remove espaços sobrando e corta no tamanho máximo.
String limpo(String? s, int max) {
  final t = (s ?? '').trim().split(RegExp(r'\s+')).where((x) => x.isNotEmpty).join(' ');
  return t.length > max ? t.substring(0, max) : t;
}
