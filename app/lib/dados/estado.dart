/// Monta a situação atual do bar somando os eventos (mesmo contrato do servidor:
/// servidor/comandas/eventos.py). Nada aqui é gravado: é sempre recalculado.
library;

class ItemC {
  final String uuid, pedido, categoria, produto, variante, setor, obs, garcom;
  final int? varianteId;
  final int preco, qtd, hora;
  final bool imprime, offline;
  String comanda; // muda se o pedido for movido para outra comanda
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
  final String uuid, garcom, deviceId;
  String comanda;
  final int hora;
  final bool offline;
  final List<ItemC> itens = [];

  /// Chegou depois de a comanda ser fechada: espera o gerente decidir (mover, reabrir ou descartar).
  bool pendente = false;
  bool descartado = false;
  PedidoC(this.uuid, this.comanda, this.garcom, this.deviceId, this.hora, this.offline);

  /// Entra na conta da comanda.
  bool get conta => !pendente && !descartado;

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
  String? juntadaEm; // uuid da comanda que recebeu os pedidos desta
  Set<String>? noFechamento; // pedidos que quem fechou conhecia
  final List<PedidoC> pedidos = [];

  ComandaC(this.uuid, this.numero, this.nome, this.abertaEm, this.abertaPor, this.deviceId);

  bool get aberta => fechadaEm == null && !descartada;
  Iterable<ItemC> get itens => pedidos.where((p) => p.conta).expand((p) => p.itens);
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
  final Map<String, Map<String, dynamic>> _resolucoes = {}; // pedido -> {acao, para}

  /// Os eventos vêm de vários celulares e podem chegar fora de ordem: são aplicados pela hora
  /// em que aconteceram, e um evento que cita uma comanda/item ainda desconhecido espera por ele.
  static Estado montar(List<Map<String, dynamic>> eventos) {
    final e = Estado();
    final ordem = [for (var i = 0; i < eventos.length; i++) (i, eventos[i])]
      ..sort((a, b) {
        final c = ((a.$2['hora'] ?? 0) as int).compareTo((b.$2['hora'] ?? 0) as int);
        return c != 0 ? c : a.$1.compareTo(b.$1);
      });
    final esperando = <String, List<Map<String, dynamic>>>{}; // uuid que falta -> eventos
    for (final (_, ev) in ordem) {
      e._aplicar(ev, esperando);
    }
    e._finalizar();
    return e;
  }

  void _mover(PedidoC p, ComandaC para) {
    if (p.comanda == para.uuid) return;
    comandas[p.comanda]?.pedidos.remove(p);
    p.comanda = para.uuid;
    for (final i in p.itens) {
      i.comanda = para.uuid;
    }
    para.pedidos
      ..add(p)
      ..sort((a, b) => a.hora.compareTo(b.hora));
  }

  /// Depois de todos os eventos: decisões do gerente e pedidos que chegaram atrasados.
  void _finalizar() {
    for (final MapEntry(key: id, value: r) in _resolucoes.entries) {
      final p = pedidos[id];
      if (p == null) continue;
      if (r['acao'] == 'descartar') {
        p.descartado = true;
      } else if (r['acao'] == 'mover') {
        final para = comandas[r['para']];
        if (para != null) _mover(p, para);
      }
    }
    for (final c in comandas.values) {
      final conhecidos = c.noFechamento;
      if (c.fechadaEm == null || c.descartada || conhecidos == null) continue;
      for (final p in c.pedidos) {
        if (!conhecidos.contains(p.uuid) && !_resolucoes.containsKey(p.uuid)) p.pendente = true;
      }
    }
  }

  /// Pedidos atrasados esperando o gerente.
  List<PedidoC> get pendencias => pedidos.values.where((p) => p.pendente).toList()..sort((a, b) => a.hora.compareTo(b.hora));

  void _esperar(Map<String, List<Map<String, dynamic>>> esperando, String uuid, Map<String, dynamic> ev) =>
      esperando.putIfAbsent(uuid, () => []).add(ev);

  void _liberar(Map<String, List<Map<String, dynamic>>> esperando, String uuid) {
    for (final ev in esperando.remove(uuid) ?? const <Map<String, dynamic>>[]) {
      _aplicar(ev, esperando);
    }
  }

  void _aplicar(Map<String, dynamic> ev, Map<String, List<Map<String, dynamic>>> esperando) {
    final d = (ev['dados'] as Map).cast<String, dynamic>();
    // eventos que dependem de uma comanda que ainda não apareceu
    const deComanda = {
      'comanda_editada', 'pedido_lancado', 'conta_impressa', 'comanda_fechada', 'comanda_reaberta', 'comanda_descartada',
      'comanda_juntada',
    };
    if (deComanda.contains(ev['tipo']) && !comandas.containsKey(d['comanda'])) {
      _esperar(esperando, d['comanda'] as String, ev);
      return;
    }
    if (ev['tipo'] == 'comanda_juntada' && !comandas.containsKey(d['para'])) {
      _esperar(esperando, d['para'] as String, ev);
      return;
    }
    if (ev['tipo'] == 'item_cancelado' && !itens.containsKey(d['item'])) {
      _esperar(esperando, d['item'] as String, ev);
      return;
    }
    final quem = (ev['usuario'] ?? '') as String;
    final hora = (ev['hora'] ?? 0) as int;
    switch (ev['tipo']) {
      case 'comanda_aberta':
        final uuid = d['comanda'] as String;
        comandas.putIfAbsent(
            uuid, () => ComandaC(uuid, d['numero'] as int, d['nome'] as String, hora, quem, (ev['device_id'] ?? '') as String));
        _liberar(esperando, uuid);
      case 'comanda_editada':
        final c = comandas[d['comanda']];
        if (c != null) {
          c.numero = d['numero'] as int;
          c.nome = d['nome'] as String;
        }
      case 'pedido_lancado':
        var c = comandas[d['comanda']]!;
        // comanda juntada a outra: o pedido vai para a que ficou
        for (var n = 0; c.juntadaEm != null && comandas[c.juntadaEm] != null && n < 10; n++) {
          c = comandas[c.juntadaEm]!;
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
        for (final i in p.itens) {
          _liberar(esperando, i.uuid);
        }
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
          c.fechadaPor = d['forcado'] == true
              ? '$quem (forçado${d['autorizado_por'] != null ? ' por ${d['autorizado_por']}' : ''})'
              : quem;
          c.total = d['total'] as int?;
          final ps = d['pedidos'];
          c.noFechamento = ps is List ? {for (final x in ps) x as String} : null;
        }
      case 'comanda_reaberta':
        final c = comandas[d['comanda']];
        if (c != null) {
          c.fechadaEm = null;
          c.total = null;
          c.contaImpressa = false;
          c.noFechamento = null;
        }
      case 'comanda_descartada':
        comandas[d['comanda']]?.descartada = true;
      case 'comanda_juntada':
        // conflito resolvido juntando: os pedidos desta vão para a outra, e esta some
        final de = comandas[d['comanda']]!;
        final para = comandas[d['para']]!;
        if (de == para) return;
        for (final p in [...de.pedidos]) {
          _mover(p, para);
        }
        de.descartada = true;
        de.juntadaEm = para.uuid;
      case 'pendencia_resolvida':
        _resolucoes[d['pedido'] as String] = d;
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
  List<(PedidoC, String)> cuponsPendentes({required bool Function(PedidoC, String) meu, int horas = 6}) {
    final corte = DateTime.now().subtract(Duration(hours: horas)).millisecondsSinceEpoch;
    final out = <(PedidoC, String)>[];
    for (final p in pedidos.values) {
      // pedido atrasado só imprime depois que o gerente decidir
      if (p.hora < corte || !p.conta) continue;
      for (final s in p.setores) {
        if (!impressos.contains('${p.uuid}:$s') && meu(p, s)) out.add((p, s));
      }
    }
    out.sort((a, b) => a.$1.hora.compareTo(b.$1.hora));
    return out;
  }

  bool pedidoImpresso(PedidoC p) => !p.conta || p.setores.every((s) => impressos.contains('${p.uuid}:$s'));

  static List<LinhaConta> linhasConta(ComandaC c) {
    final m = <String, LinhaConta>{};
    for (final i in c.itensAtivos) {
      m.putIfAbsent('${i.rotulo}|${i.preco}', () => LinhaConta(i.rotulo, i.preco)).qtd += i.qtd;
    }
    return m.values.toList();
  }
}
