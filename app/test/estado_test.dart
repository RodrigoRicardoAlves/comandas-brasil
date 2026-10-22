import 'package:comandas/dados/estado.dart';
import 'package:comandas/dados/modelos.dart';
import 'package:comandas/impressao/cupons.dart';
import 'package:flutter_test/flutter_test.dart';

var _n = 0;
Map<String, dynamic> ev(String tipo, Map<String, dynamic> dados, {String dev = 'cel1', int? hora}) => {
      'uuid': 'ev-${_n++}',
      'tipo': tipo,
      'device_id': dev,
      'usuario': 'João',
      'hora': hora ?? DateTime.now().millisecondsSinceEpoch,
      'dados': dados,
    };

Map<String, dynamic> item(String id, String produto, int preco, {int qtd = 1, String setor = '', bool imprime = false}) =>
    {'item': id, 'produto': produto, 'variante': '', 'preco': preco, 'qtd': qtd, 'setor': setor, 'imprime': imprime};

void main() {
  test('pedido chega antes da abertura da comanda e é encaixado', () {
    final e = Estado.montar([
      ev('pedido_lancado', {'pedido': 'p1', 'comanda': 'c1', 'itens': [item('i1', 'Batata', 2200, qtd: 2)]}),
      ev('comanda_aberta', {'comanda': 'c1', 'numero': 15, 'nome': 'Ana'}),
    ]);
    expect(e.comandas['c1']!.subtotal, 4400);
  });

  test('cancelamento que chega antes do pedido (outro celular) espera o item aparecer', () {
    final e = Estado.montar([
      ev('comanda_aberta', {'comanda': 'c1', 'numero': 3, 'nome': 'Ana'}, hora: 1000),
      ev('item_cancelado', {'item': 'i1'}, hora: 3000),
      ev('comanda_editada', {'comanda': 'c9', 'numero': 4, 'nome': 'Zé'}, hora: 1500),
      ev('pedido_lancado', {'pedido': 'p1', 'comanda': 'c1', 'itens': [item('i1', 'Batata', 2200), item('i2', 'Coca', 600)]},
          hora: 2000),
      ev('comanda_aberta', {'comanda': 'c9', 'numero': 9, 'nome': 'Teo'}, hora: 1200),
    ]);
    expect(e.comandas['c1']!.subtotal, 600);
    expect(e.comandas['c9']!.numero, 4);
    expect(e.comandas['c9']!.nome, 'Zé');
  });

  group('pedido atrasado (chegou depois do fechamento)', () {
    List<Map<String, dynamic>> base() => [
          ev('comanda_aberta', {'comanda': 'c1', 'numero': 7, 'nome': 'Ana'}, hora: 1000),
          ev('pedido_lancado', {'pedido': 'p1', 'comanda': 'c1', 'itens': [item('i1', 'Coca', 600)]}, hora: 2000),
          // feito offline às 2500, mas quem fechou às 3000 não conhecia
          ev('pedido_lancado', {'pedido': 'p2', 'comanda': 'c1', 'itens': [item('i2', 'Batata', 3500, setor: 'Cozinha', imprime: true)]},
              hora: 2500, dev: 'cel2'),
          ev('comanda_fechada', {'comanda': 'c1', 'total': 600, 'pedidos': ['p1']}, hora: 3000),
          ev('comanda_aberta', {'comanda': 'c2', 'numero': 8, 'nome': 'Bia'}, hora: 3100),
        ];

    test('vira pendência, fica fora da conta e não imprime', () {
      final e = Estado.montar(base());
      expect(e.pendencias.map((p) => p.uuid), ['p2']);
      expect(e.comandas['c1']!.subtotal, 600);
      expect(e.cuponsPendentes(meu: (_) => true, horas: 1000000), isEmpty);
    });

    test('gerente lança em outra comanda: entra na conta dela e imprime', () {
      final e = Estado.montar([...base(), ev('pendencia_resolvida', {'pedido': 'p2', 'acao': 'mover', 'para': 'c2'}, hora: 4000)]);
      expect(e.pendencias, isEmpty);
      expect(e.comandas['c2']!.subtotal, 3500);
      expect(e.cuponsPendentes(meu: (_) => true, horas: 1000000).single.$2, 'Cozinha');
    });

    test('gerente descarta', () {
      final e = Estado.montar([...base(), ev('pendencia_resolvida', {'pedido': 'p2', 'acao': 'descartar'}, hora: 4000)]);
      expect(e.pendencias, isEmpty);
      expect(e.comandas['c1']!.subtotal, 600);
      expect(e.cuponsPendentes(meu: (_) => true, horas: 1000000), isEmpty);
    });

    test('reabrir a comanda devolve o pedido para a conta', () {
      final e = Estado.montar([...base(), ev('comanda_reaberta', {'comanda': 'c1'}, hora: 4000)]);
      expect(e.pendencias, isEmpty);
      expect(e.comandas['c1']!.subtotal, 4100);
    });
  });

  test('juntar comandas em conflito: pedidos passam para a outra, inclusive os que chegam depois', () {
    final e = Estado.montar([
      ev('comanda_aberta', {'comanda': 'a', 'numero': 15, 'nome': 'Ana'}, hora: 1000),
      ev('comanda_aberta', {'comanda': 'b', 'numero': 15, 'nome': 'Bia'}, hora: 1100, dev: 'cel2'),
      ev('pedido_lancado', {'pedido': 'p1', 'comanda': 'b', 'itens': [item('i1', 'Coca', 600)]}, hora: 1200, dev: 'cel2'),
      ev('comanda_juntada', {'comanda': 'b', 'para': 'a'}, hora: 2000),
      ev('pedido_lancado', {'pedido': 'p2', 'comanda': 'b', 'itens': [item('i2', 'Suco', 800)]}, hora: 2100, dev: 'cel2'),
    ]);
    expect(e.abertas.map((c) => c.uuid), ['a']);
    expect(e.emConflito(e.comandas['a']!), isFalse);
    expect(e.comandas['a']!.subtotal, 1400);
  });

  test('duas comandas com o mesmo número ficam em conflito até uma fechar', () {
    final evs = [
      ev('comanda_aberta', {'comanda': 'a', 'numero': 15, 'nome': 'Ana'}, dev: 'cel1'),
      ev('comanda_aberta', {'comanda': 'b', 'numero': 15, 'nome': 'Bia'}, dev: 'cel2'),
    ];
    var e = Estado.montar(evs);
    expect(e.emConflito(e.comandas['a']!), isTrue);
    expect(e.emConflito(e.comandas['b']!), isTrue);
    evs.add(ev('comanda_fechada', {'comanda': 'a', 'total': 0}));
    e = Estado.montar(evs);
    expect(e.emConflito(e.comandas['b']!), isFalse);
  });

  test('itens que não imprimem não geram cupom; cada setor gera o seu', () {
    final e = Estado.montar([
      ev('comanda_aberta', {'comanda': 'c1', 'numero': 1, 'nome': 'X'}),
      ev('pedido_lancado', {
        'pedido': 'p1',
        'comanda': 'c1',
        'itens': [
          item('i1', 'Brahma', 1000),
          item('i2', 'Batata', 3500, setor: 'Cozinha', imprime: true),
          item('i3', 'Espetinho', 1000, qtd: 3, setor: 'Churrasqueira', imprime: true),
        ],
      }),
    ]);
    final pend = e.cuponsPendentes(meu: (_) => true);
    expect(pend.map((x) => x.$2).toSet(), {'Cozinha', 'Churrasqueira'});

    final bar = BarCfg.json({'id': 1, 'nome': 'Bar', 'slug': 'b'});
    final c = e.comandas['c1']!;
    final cozinha = String.fromCharCodes(cupomPedido(bar, c, e.pedidos['p1']!, 'Cozinha'));
    expect(cozinha, contains('Batata'));
    expect(cozinha, isNot(contains('Espetinho')));
    expect(cozinha, isNot(contains('Brahma')));
  });

  test('impresso some da lista de pendentes; cancelado sai da conta', () {
    final e = Estado.montar([
      ev('comanda_aberta', {'comanda': 'c1', 'numero': 1, 'nome': 'X'}),
      ev('pedido_lancado', {
        'pedido': 'p1',
        'comanda': 'c1',
        'itens': [item('i1', 'Batata', 3500, setor: 'Cozinha', imprime: true), item('i2', 'Brahma', 1000, qtd: 2)],
      }),
      ev('impresso', {'ref': 'p1:Cozinha', 'setor': 'Cozinha'}),
      ev('item_cancelado', {'item': 'i2', 'autorizado_por': 'Zé'}),
    ]);
    expect(e.cuponsPendentes(meu: (_) => true, horas: 1000000), isEmpty);
    expect(e.comandas['c1']!.subtotal, 3500);
  });
}
