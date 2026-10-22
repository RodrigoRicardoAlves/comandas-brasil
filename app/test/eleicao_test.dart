import 'package:comandas/rede/assinatura.dart';
import 'package:comandas/rede/eleicao.dart';
import 'package:flutter_test/flutter_test.dart';

Candidato c(String id, int bateria, {bool carregando = false, int termo = 0, String? lider}) => Candidato(
      id: id,
      nota: calcularNota(bateria: bateria, carregando: carregando),
      elegivel: podeSerLider(bateria: bateria, carregando: carregando),
      termo: termo,
      lider: lider,
      bateria: bateria,
      carregando: carregando,
    );

void main() {
  const t0 = 1000000;
  const depois = t0 + Eleicao.graca + 1;

  test('nota: bateria + 40 carregando − 30 economia', () {
    expect(calcularNota(bateria: 60, carregando: true), 100);
    expect(calcularNota(bateria: 60, economia: true), 30);
    expect(podeSerLider(bateria: 15), isFalse);
    expect(podeSerLider(bateria: 15, carregando: true), isTrue);
  });

  test('celular sozinho espera a carência e depois assume', () {
    final e = Eleicao(t0);
    expect(e.passo(c('a', 50), [], t0 + 1000).acao, Acao.esperar);
    expect(e.passo(c('a', 50), [], depois).acao, Acao.assumiu);
    expect(e.lider, 'a');
    expect(e.termo, 1);
  });

  test('quem chega obedece o líder que já existe (mandato maior)', () {
    final e = Eleicao(t0);
    final d = e.passo(c('novo', 100, carregando: true), [c('velho', 40, termo: 3, lider: 'velho')], t0 + 500);
    expect(d.acao, Acao.nada);
    expect(e.lider, 'velho');
    expect(e.termo, 3);
  });

  test('cenário 6: líder em 30% e outro carregando em 60% -> troca', () {
    final e = Eleicao(t0)
      ..termo = 2
      ..lider = 'lider';
    final d = e.passo(c('lider', 30, termo: 2, lider: 'lider'), [c('outro', 60, carregando: true, termo: 2, lider: 'lider')], depois);
    expect(d.acao, Acao.passar);
    expect(d.para, 'outro');
    e.passarPara('outro');
    expect(e.termo, 3);
    // o outro lado adota o mandato novo e vira líder
    final o = Eleicao(t0)
      ..termo = 2
      ..lider = 'lider';
    o.passo(c('outro', 60, carregando: true, termo: 2, lider: 'lider'), [c('lider', 30, termo: 3, lider: 'outro')], depois);
    expect(o.lider, 'outro');
  });

  test('cenário 6: líder em 70% e outro em 75% -> não troca (histerese)', () {
    final e = Eleicao(t0)
      ..termo = 2
      ..lider = 'lider';
    final d = e.passo(c('lider', 70, termo: 2, lider: 'lider'), [c('outro', 75, termo: 2, lider: 'lider')], depois);
    expect(d.acao, Acao.nada);
  });

  test('líder com bateria crítica passa para quem tem nota maior', () {
    final e = Eleicao(t0)
      ..termo = 1
      ..lider = 'lider';
    final d = e.passo(c('lider', 22, termo: 1, lider: 'lider'), [c('outro', 35, termo: 1, lider: 'lider')], depois);
    expect(d.acao, Acao.passar);
  });

  test('líder sumiu: o melhor candidato assume com mandato novo; o outro espera', () {
    final a = Eleicao(t0)
      ..termo = 4
      ..lider = 'morto';
    final b = Eleicao(t0)
      ..termo = 4
      ..lider = 'morto';
    final ca = c('a', 80, termo: 4, lider: 'morto');
    final cb = c('b', 50, termo: 4, lider: 'morto');
    expect(a.passo(ca, [cb], depois).acao, Acao.assumiu);
    expect(a.termo, 5);
    expect(b.passo(cb, [ca], depois).acao, Acao.esperar);
    // na batida seguinte o b vê o mandato novo do a
    b.passo(cb, [c('a', 80, termo: 5, lider: 'a')], depois + 2000);
    expect(b.lider, 'a');
  });

  test('bateria abaixo de 20% nunca vira líder se houver outro', () {
    final e = Eleicao(t0);
    final d = e.passo(c('fraco', 15), [c('bom', 10, carregando: true)], depois);
    expect(d.acao, Acao.esperar);
  });

  test('dois líderes com o mesmo mandato (rede partida): fica o de menor id', () {
    final e = Eleicao(t0)
      ..termo = 3
      ..lider = 'zzz';
    e.passo(c('zzz', 90, termo: 3, lider: 'zzz'), [c('aaa', 50, termo: 3, lider: 'aaa')], depois);
    expect(e.lider, 'aaa');
  });

  test('assinatura da rede local: confere, rejeita chave/corpo errados', () {
    final a = Assinatura('chave-do-bar');
    final s = a.assinar('/oi', '{"x":1}');
    expect(a.confere(s, '/oi', '{"x":1}'), isTrue);
    expect(a.confere(s, '/oi', '{"x":2}'), isFalse);
    expect(a.confere(s, '/eventos/enviar', '{"x":1}'), isFalse);
    expect(Assinatura('outra').confere(s, '/oi', '{"x":1}'), isFalse);
    final velha = a.assinar('/oi', '{}', hora: DateTime.now().millisecondsSinceEpoch - 3600000);
    expect(a.confere(velha, '/oi', '{}'), isFalse);
  });
}
