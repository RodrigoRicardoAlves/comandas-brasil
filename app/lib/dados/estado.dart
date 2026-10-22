/// Monta a situação atual do bar somando os eventos (mesmo contrato do servidor:
/// servidor/comandas/eventos.py). Nada aqui é gravado: é sempre recalculado.
library;

class ItemC {
  final String uuid, pedido, comanda, categoria, produto, variante, setor, obs, garcom;
  final int? varianteId;
  final int preco, qtd, hora;
  final bool imprime, offline;
  bool cancelado = false;
  String canceladoPor = '';

  ItemC({
    required this.uuid,
    required this.pedido,
    required this.comanda,
    required this.categoria,
    required this.produto,
    required this.variante,
    required this.setor,
    required this.obs,
    required this.garcom,
    required this.varianteId,
    required this.preco,
    required this.qtd,
    required this.hora,
    required this.imprime,
    required this.offline,
  });

  String get rotulo => '$produto $variante'.trim();
  int get total => preco * qtd;
}

class PedidoC {
  final String uuid, comanda, garcom, deviceId;
  final int hora;
  final bool offline;
  final List<ItemC> itens = [];
  PedidoC(this.uuid, this.comanda, this.garcom, this.deviceId, this.hora, this.offline);

  /// Setores que precisam de cupom neste pedido.
  Set<String> get setores => {for (final i in itens) if (i.imprime) i.setor};
}

class ComandaC {
  final String uuid;
  int numero;
  String nome;
  final int abertaEm;
  final String abertaPor, deviceId;
  int? fechadaEm;
  String fechadaPor = '';
  int? total;
  bool descartada = false;
  bool contaImpressa = false;
  final List<PedidoC> pedidos = [];

  ComandaC(this.uuid, this.numero, this.nome, this.abertaEm, this.abertaPor, this.deviceId);

  bool get aberta => fechadaEm == null && !descartada;
  Iterable<ItemC> get itens => pedidos.expand((p) => p.itens);
  Iterable<ItemC> get itensAtivos => itens.where((i) => !i.cancelado);
  int get subtotal => itensAtivos.fold(0, (s, i) => s + i.total);
  int get quantidade => itensAtivos.fold(0, (s, i) => s + i.qtd);
  int get ultimaAtividade => pedidos.isEmpty ? abertaEm : pedidos.last.hora;
}

/// Linha da conta: itens iguais (mesmo produto, variante e preço) somados.
class LinhaConta {
  final String rotulo;
  final int preco;
  int qtd = 0;
  LinhaConta(this.rotulo, this.preco);
  int get total => preco * qtd;
}

class Estado {
  final Map<String, ComandaC> comandas = {};
  final Map<String, PedidoC> pedidos = {};
  final Map<String, ItemC> itens = {};
  final Set<String> impressos = {}; // "pedido:setor"
  final Set<String> chamadosAtendidos = {};

  static Estado montar(List<Map<String, dynamic>> eventos) {
    final e = Estado();
    final esperando = <String, List<Map<String, dynamic>>>{}; // pedidos que chegaram antes da comanda
    for (final ev in eventos) {
      e._aplicar(ev, esperando);
    }
    return e;
  }

  void _aplicar(Map<String, dynamic> ev, Map<String, List<Map<String, dynamic>>> esperando) {
    final d = (ev['dados'] as Map).cast<String, dynamic>();
    final quem = (ev['usuario'] ?? '') as String;
    final hora = (ev['hora'] ?? 0) as int;
    switch (ev['tipo']) {
      case 'comanda_aberta':
        final uuid = d['comanda'] as String;
        comandas.putIfAbsent(
            uuid, () => ComandaC(uuid, d['numero'] as int, d['nome'] as String, hora, quem, (ev['device_id'] ?? '') as String));
        for (final p in esperando.remove(uuid) ?? const []) {
          _aplicar(p, esperando);
        }
      case 'comanda_editada':
        final c = comandas[d['comanda']];
        if (c != null) {
          c.numero = d['numero'] as int;
          c.nome = d['nome'] as String;
        }
      case 'pedido_lancado':
        final c = comandas[d['comanda']];
        if (c == null) {
          esperando.putIfAbsent(d['comanda'] as String, () => []).add(ev);
          return;
        }
        if (pedidos.containsKey(d['pedido'])) return;
        final p = PedidoC(d['pedido'], c.uuid, quem, (ev['device_id'] ?? '') as String, hora, d['offline'] == true);
        for (final it in (d['itens'] as List).cast<Map>()) {
          final i = ItemC(
            uuid: it['item'],
            pedido: p.uuid,
            comanda: c.uuid,
            categoria: it['categoria'] ?? '',
            produto: it['produto'] ?? '',
            variante: it['variante'] ?? '',
            setor: it['setor'] ?? '',
            obs: it['obs'] ?? '',
            garcom: quem,
            varianteId: it['variante_id'],
            preco: it['preco'] ?? 0,
            qtd: it['qtd'] ?? 1,
            hora: hora,
            imprime: it['imprime'] == true,
            offline: p.offline,
          );
          p.itens.add(i);
          itens[i.uuid] = i;
        }
        pedidos[p.uuid] = p;
        c.pedidos.add(p);
      case 'item_cancelado':
        final i = itens[d['item']];
        if (i != null) {
          i.cancelado = true;
          i.canceladoPor = d['autorizado_por'] != null ? '$quem (autorizado por ${d['autorizado_por']})' : quem;
        }
      case 'conta_impressa':
        comandas[d['comanda']]?.contaImpressa = true;
      case 'comanda_fechada':
        final c = comandas[d['comanda']];
        if (c != null) {
          c.fechadaEm = hora;
          c.fechadaPor = d['forcado'] == true ? '$quem (forçado)' : quem;
          c.total = d['total'] as int?;
        }
      case 'comanda_reaberta':
        final c = comandas[d['comanda']];
        if (c != null) {
          c.fechadaEm = null;
          c.total = null;
          c.contaImpressa = false;
        }
      case 'comanda_descartada':
        comandas[d['comanda']]?.descartada = true;
      case 'impresso':
        impressos.add(d['ref'] as String);
      case 'chamado_atendido':
        chamadosAtendidos.add('${d['chamado']}');
    }
  }

  List<ComandaC> get abertas => comandas.values.where((c) => c.aberta).toList()
    ..sort((a, b) => a.numero != b.numero ? a.numero.compareTo(b.numero) : a.abertaEm.compareTo(b.abertaEm));

  List<ComandaC> get fechadas => comandas.values.where((c) => c.fechadaEm != null && !c.descartada).toList()
    ..sort((a, b) => b.fechadaEm!.compareTo(a.fechadaEm!));

  ComandaC? abertaComNumero(int numero, {String? exceto}) {
    for (final c in comandas.values) {
      if (c.aberta && c.numero == numero && c.uuid != exceto) return c;
    }
    return null;
  }

  /// Duas comandas abertas com o mesmo número (abertas em celulares que estavam sem se ver).
  /// As duas ficam bloqueadas para novos pedidos até uma delas ser fechada.
  bool emConflito(ComandaC c) => c.aberta && abertaComNumero(c.numero, exceto: c.uuid) != null;

  /// Cupons de pedido ainda não impressos: (pedido, setor).
  List<(PedidoC, String)> cuponsPendentes({required bool Function(PedidoC) meu, int horas = 6}) {
    final corte = DateTime.now().subtract(Duration(hours: horas)).millisecondsSinceEpoch;
    final out = <(PedidoC, String)>[];
    for (final p in pedidos.values) {
      if (p.hora < corte || !meu(p)) continue;
      for (final s in p.setores) {
        if (!impressos.contains('${p.uuid}:$s')) out.add((p, s));
      }
    }
    out.sort((a, b) => a.$1.hora.compareTo(b.$1.hora));
    return out;
  }

  bool pedidoImpresso(PedidoC p) => p.setores.every((s) => impressos.contains('${p.uuid}:$s'));

  static List<LinhaConta> linhasConta(ComandaC c) {
    final m = <String, LinhaConta>{};
    for (final i in c.itensAtivos) {
      m.putIfAbsent('${i.rotulo}|${i.preco}', () => LinhaConta(i.rotulo, i.preco)).qtd += i.qtd;
    }
    return m.values.toList();
  }
}
