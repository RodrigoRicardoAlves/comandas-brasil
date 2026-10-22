/// Escolha automática do celular líder (o que imprime e organiza a rede local).
///
/// Regras (PROJETO.md, seção 7.2):
/// - nota = bateria + 40 se carregando − 30 se economia de bateria + até 5 pelo sinal do Wi-Fi;
/// - abaixo de 20% de bateria (sem carregar) não vira líder;
/// - mandato numerado (termo): quem tem termo maior manda;
/// - histerese: só troca se o outro tiver 25 pontos a mais, ou se o líder cair abaixo de 25%;
/// - líder sumido (sem resposta por ~9 s): o melhor candidato assume.
library;

int calcularNota({int? bateria, bool carregando = false, bool economia = false, int? rssi}) {
  var n = (bateria ?? 50) + (carregando ? 40 : 0) - (economia ? 30 : 0);
  if (rssi != null && rssi < 0) n += ((rssi + 90) / 8).clamp(0, 5).round();
  return n;
}

bool podeSerLider({int? bateria, bool carregando = false}) => carregando || (bateria ?? 100) >= 20;

class Candidato {
  final String id;
  final int nota;
  final bool elegivel;
  final int termo;
  final String? lider;
  final int? bateria;
  final bool carregando;

  const Candidato({
    required this.id,
    required this.nota,
    this.elegivel = true,
    this.termo = 0,
    this.lider,
    this.bateria,
    this.carregando = false,
  });
}

enum Acao { nada, esperar, assumiu, passar }

class Decisao {
  final Acao acao;
  final String? para; // em "passar": quem deve assumir
  const Decisao(this.acao, [this.para]);
  @override
  String toString() => para == null ? acao.name : '${acao.name} → $para';
}

int _melhorPrimeiro(Candidato a, Candidato b) => a.nota != b.nota ? b.nota.compareTo(a.nota) : a.id.compareTo(b.id);

class Eleicao {
  static const graca = 6000; // ao abrir o app, espera achar os outros antes de se declarar líder
  static const paciencia = 12000; // se o melhor candidato não assumir nesse tempo, qualquer um assume
  static const diferencaTroca = 25;
  static const bateriaCritica = 25;

  int termo = 0;
  String? lider;
  final int inicio;
  int? _semLiderDesde;

  Eleicao(this.inicio);

  /// Um passo da eleição. `vivos` = celulares do mesmo bar que responderam nos últimos segundos.
  Decisao passo(Candidato eu, List<Candidato> vivos, int agora) {
    // 1) alguém com mandato mais novo: obedece
    Candidato? alto;
    for (final p in vivos) {
      if (alto == null || p.termo > alto.termo) alto = p;
    }
    if (alto != null && alto.termo > termo) {
      termo = alto.termo;
      lider = alto.lider;
    }

    // 2) dois líderes com o mesmo mandato (rede estava partida): fica o de menor id
    for (final p in vivos) {
      if (p.termo == termo && p.lider != null && lider != null && p.lider != lider) {
        lider = p.lider!.compareTo(lider!) < 0 ? p.lider : lider;
      }
    }

    // 3) o líder está vivo?
    final ids = {for (final p in vivos) p.id};
    final liderVivo = lider != null && (lider == eu.id || ids.contains(lider));
    if (!liderVivo) {
      lider = null;
      _semLiderDesde ??= agora;
      if (agora - inicio < graca) return const Decisao(Acao.esperar);
      var cands = [eu, ...vivos].where((c) => c.elegivel).toList();
      if (cands.isEmpty) cands = [eu, ...vivos];
      cands.sort(_melhorPrimeiro);
      if (cands.first.id == eu.id || agora - _semLiderDesde! > paciencia) {
        termo = [termo, for (final p in vivos) p.termo].reduce((a, b) => a > b ? a : b) + 1;
        lider = eu.id;
        _semLiderDesde = null;
        return const Decisao(Acao.assumiu);
      }
      return const Decisao(Acao.esperar);
    }
    _semLiderDesde = null;

    // 4) sou o líder: vale a pena passar para outro?
    if (lider == eu.id && vivos.isNotEmpty) {
      final outros = vivos.where((c) => c.elegivel).toList()..sort(_melhorPrimeiro);
      if (outros.isNotEmpty) {
        final b = outros.first;
        final critico = !eu.carregando && (eu.bateria ?? 100) < bateriaCritica && b.nota > eu.nota;
        if (b.nota >= eu.nota + diferencaTroca || critico) return Decisao(Acao.passar, b.id);
      }
    }
    return const Decisao(Acao.nada);
  }

  /// Confirma a troca combinada (depois de o novo líder receber todos os eventos).
  void passarPara(String id) {
    termo += 1;
    lider = id;
  }
}
