import 'package:comandas/util.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('lerCentavos aceita os jeitos comuns de digitar preço', () {
    expect(lerCentavos('12'), 1200);
    expect(lerCentavos('12,5'), 1250);
    expect(lerCentavos('12,50'), 1250);
    expect(lerCentavos('12.50'), 1250);
    expect(lerCentavos('R\$ 1.234,50'), 123450);
    expect(lerCentavos('1.000'), 100000);
    expect(lerCentavos(''), null);
    expect(lerCentavos('abc'), null);
  });
}
