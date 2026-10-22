import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter/foundation.dart';

import '../app.dart';
import '../impressao/impressora.dart';
import '../sistema.dart';
import '../util.dart';
import 'assinatura.dart';
import 'eleicao.dart';

const portaLan = 8787; // HTTP entre os celulares
const portaUdp = 8788; // anúncio por broadcast
const _vivoMs = 9000; // sem resposta por mais que isso = sumiu

/// Outro celular do mesmo bar visto na rede local.
class Par {
  final String id;
  String ip;
  int porta;
  String usuario = '', modelo = '';
  int nota = 0, termo = 0;
  String? lider;
  bool elegivel = true;
  int? bateria;
  bool carregando = false;
  int vistoMs = 0; // última conversa que deu certo
  int conhecidoMs = 0; // última vez que alguém falou dele (UDP, mDNS, VPS)
  int falhas = 0;
  final Set<String> origens = {};
  int cursorBaixar = 0; // último id do banco DELE que eu já tenho
  int cursorEnviar = 0; // último id do MEU banco que ele já tem

  Par(this.id, this.ip, this.porta);

  bool vivo(int agora) => agora - vistoMs < _vivoMs;

  Candidato get candidato => Candidato(
      id: id, nota: nota, elegivel: elegivel, termo: termo, lider: lider, bateria: bateria, carregando: carregando);
}

/// Rede local entre os celulares do bar: descoberta, eleição do líder e cópia dos eventos.
///
/// - Cada celular abre um servidor HTTP (porta 8787). Toda mensagem é assinada com a lan_key.
/// - Descoberta por broadcast UDP, mDNS e pela lista da VPS.
/// - A cada 2 s conversa com os outros ("/oi"), roda a eleição e sincroniza com o líder.
/// - Seguidores mandam seus eventos ao líder e baixam dele os eventos dos outros.
/// - Só o líder imprime; os outros pedem a ele (conta, cancelamento, teste).
class RedeLocal {
  final App app;
  RedeLocal(this.app);

  HttpServer? _srv;
  RawDatagramSocket? _udp;
  Timer? _timer;
  final _cli = HttpClient()
    ..connectionTimeout = const Duration(seconds: 2)
    ..idleTimeout = const Duration(seconds: 5);
  Assinatura? _ass;
  String _bar = '';

  Eleicao eleicao = Eleicao(0);
  final Map<String, Par> pares = {};
  bool ativa = false;
  String? meuIp;
  bool isolamento = false; // os celulares estão na mesma Wi-Fi mas não se alcançam
  String? erroServidor; // não conseguiu abrir a porta local
  Map<String, dynamic> sistema = {};
  bool servicoLigado = false;
  bool _rodando = false, _sincronizando = false, _pedirSync = false, _passando = false;
  bool _pediuNotificacao = false;
  int _tick = 0;
  final List<String> registro = []; // últimas mudanças de líder (tela de status)

  String get eu => app.deviceId;
  bool get souLider => ativa && eleicao.lider == eu;
  Par? get parLider => eleicao.lider == null ? null : pares[eleicao.lider];
  List<Par> vivos() {
    final a = agoraMs();
    return pares.values.where((p) => p.vivo(a)).toList();
  }

  /// Dá para falar com o líder agora (ou sou eu).
  bool get liderAlcancavel => souLider || (parLider?.vivo(agoraMs()) ?? false);

  int get nota => calcularNota(
      bateria: app.bateria, carregando: app.carregando, economia: sistema['economia'] == true, rssi: sistema['rssi'] as int?);
  bool get elegivel => podeSerLider(bateria: app.bateria, carregando: app.carregando);

  void _log(String s) {
    registro.insert(0, '${hhmm(agoraMs())} $s');
    if (registro.length > 20) registro.removeLast();
    debugPrint('[rede] $s');
  }

  // ------------------------------------------------------------------ ligar / desligar

  Future<void> iniciar() async {
    final b = app.boot;
    if (ativa || b == null || b.lanKey.isEmpty) return;
    _ass = Assinatura(b.lanKey);
    _bar = b.bar.slug;
    eleicao = Eleicao(agoraMs());
    pares.clear();
    erroServidor = null;
    try {
      _srv = await HttpServer.bind(InternetAddress.anyIPv4, portaLan, shared: true);
      _srv!.listen(_atender, onError: (_) {});
    } catch (e) {
      erroServidor = 'Não abriu a porta $portaLan: $e';
    }
    try {
      _udp = await RawDatagramSocket.bind(InternetAddress.anyIPv4, portaUdp, reuseAddress: true);
      _udp!.broadcastEnabled = true;
      _udp!.listen(_aoUdp, onError: (_) {});
    } catch (_) {}
    Sistema.aoAcharNsd = (ip, porta, bar, id) {
      if (bar == _bar) conhecer(id, ip, porta, 'mDNS');
    };
    await Sistema.multicast(true);
    await Sistema.nsdIniciar(portaLan, _bar, eu);
    ativa = true;
    _log('rede local ligada');
    _timer = Timer.periodic(const Duration(seconds: 2), (_) => _batida());
    unawaited(_batida());
  }

  Future<void> parar() async {
    if (!ativa) return;
    ativa = false;
    _timer?.cancel();
    await _srv?.close(force: true);
    _udp?.close();
    _srv = null;
    _udp = null;
    await Sistema.nsdParar();
    await Sistema.multicast(false);
    if (servicoLigado) await Sistema.servico(false);
    servicoLigado = false;
    pares.clear();
    eleicao = Eleicao(0);
    app.avisar();
  }

  /// Alguém (UDP, mDNS, VPS) contou que existe esse celular nesse endereço.
  void conhecer(String id, String ip, int porta, String origem) {
    if (!ativa || id == eu || ip.isEmpty) return;
    final p = pares.putIfAbsent(id, () => Par(id, ip, porta));
    if (p.ip != ip || p.porta != porta) {
      p.ip = ip;
      p.porta = porta;
      p.falhas = 0;
    }
    p.conhecidoMs = agoraMs();
    p.origens.add(origem);
  }

  // ------------------------------------------------------------------ servidor HTTP local

  Map<String, dynamic> _minhaInfo() => {
        'id': eu,
        'bar': _bar,
        'usuario': app.usuario?.nome ?? '',
        'modelo': app.modelo,
        'porta': portaLan,
        'nota': nota,
        'elegivel': elegivel,
        'termo': eleicao.termo,
        'lider': eleicao.lider,
        'bateria': app.bateria,
        'carregando': app.carregando,
      };

  void _atualizarPar(Map<String, dynamic> j, String? ip) {
    final id = j['id'] as String?;
    if (id == null || id == eu || j['bar'] != _bar) return;
    final p = pares.putIfAbsent(id, () => Par(id, ip ?? '', (j['porta'] ?? portaLan) as int));
    if (ip != null && ip.isNotEmpty) p.ip = ip;
    p.porta = (j['porta'] ?? p.porta) as int;
    p.usuario = (j['usuario'] ?? '') as String;
    p.modelo = (j['modelo'] ?? '') as String;
    p.nota = (j['nota'] ?? 0) as int;
    p.elegivel = j['elegivel'] != false;
    p.termo = (j['termo'] ?? 0) as int;
    p.lider = j['lider'] as String?;
    p.bateria = j['bateria'] as int?;
    p.carregando = j['carregando'] == true;
    p.vistoMs = agoraMs();
    p.falhas = 0;
    p.origens.add('rede');
  }

  Future<void> _atender(HttpRequest req) async {
    final res = req.response;
    try {
      final corpo = await utf8.decoder.bind(req).join();
      final caminho = req.uri.path;
      if (req.method != 'POST' || _ass == null || !_ass!.confere(req.headers.value('x-assinatura'), caminho, corpo)) {
        res.statusCode = HttpStatus.forbidden;
        return;
      }
      final j = jsonDecode(corpo) as Map<String, dynamic>;
      final ip = req.connectionInfo?.remoteAddress.address;
      Map<String, dynamic> r;
      switch (caminho) {
        case '/oi':
          _atualizarPar(j, ip);
          r = _minhaInfo();
        case '/eventos/enviar':
          r = await _receberEventos(j);
        case '/eventos/baixar':
          r = await _entregarEventos(j);
        case '/imprimir':
          r = await _imprimirParaOutro(j);
        default:
          res.statusCode = HttpStatus.notFound;
          return;
      }
      final saida = jsonEncode(r);
      res.headers.contentType = ContentType.json;
      res.headers.set('x-assinatura', _ass!.assinar('resp$caminho', saida));
      res.write(saida);
    } catch (e) {
      res.statusCode = HttpStatus.internalServerError;
    } finally {
      await res.close().catchError((_) {});
    }
  }

  Future<Map<String, dynamic>> _receberEventos(Map<String, dynamic> j) async {
    final de = j['de'] as String?;
    var novos = 0;
    for (final ev in (j['eventos'] as List).cast<Map<String, dynamic>>()) {
      // quem recebe por aqui é (ou foi) o líder: ele também fica responsável por subir à VPS
      if (await app.banco.inserirEvento(ev, origem: de)) novos++;
    }
    if (novos > 0) await app.aoChegarEventos();
    return {'ok': true, 'novos': novos};
  }

  Future<Map<String, dynamic>> _entregarEventos(Map<String, dynamic> j) async {
    final ultimo = await app.banco.ultimoId(); // lido ANTES, para não pular evento gravado no meio
    const limite = 300;
    final lista = await app.banco.eventosDesde((j['desde'] ?? 0) as int, exceto: j['de'] as String?, limite: limite);
    return {
      'eventos': [for (final (_, ev) in lista) ev],
      'ultimo': lista.length == limite ? lista.last.$1 : ultimo,
      'mais': lista.length == limite,
    };
  }

  Future<Map<String, dynamic>> _imprimirParaOutro(Map<String, dynamic> j) async {
    try {
      await Impressora.enviar(j['alvo'] as String, base64Decode(j['dados'] as String));
      return {'ok': true};
    } catch (e) {
      return {'ok': false, 'erro': e.toString()};
    }
  }

  // ------------------------------------------------------------------ cliente

  Future<Map<String, dynamic>> _post(Par p, String caminho, Map<String, dynamic> corpo,
      {Duration tempo = const Duration(seconds: 3)}) async {
    final ass = _ass!;
    final txt = jsonEncode(corpo);
    final req = await _cli.postUrl(Uri(scheme: 'http', host: p.ip, port: p.porta, path: caminho)).timeout(tempo);
    req.headers.contentType = ContentType.json;
    req.headers.set('x-assinatura', ass.assinar(caminho, txt));
    req.add(utf8.encode(txt));
    final res = await req.close().timeout(tempo);
    final saida = await utf8.decoder.bind(res).join().timeout(tempo);
    if (res.statusCode != 200) throw HttpException('HTTP ${res.statusCode}');
    if (!ass.confere(res.headers.value('x-assinatura'), 'resp$caminho', saida)) {
      throw const HttpException('resposta sem assinatura válida');
    }
    return jsonDecode(saida) as Map<String, dynamic>;
  }

  Future<void> _oi(Par p, Map<String, dynamic> info) async {
    try {
      _atualizarPar(await _post(p, '/oi', info, tempo: const Duration(seconds: 2)), p.ip);
    } catch (_) {
      p.falhas++;
    }
  }

  // ------------------------------------------------------------------ descoberta UDP

  void _anunciar() {
    final u = _udp;
    final ass = _ass;
    if (u == null || ass == null) return;
    final txt = '$_bar|$eu|$portaLan';
    final msg = utf8.encode(jsonEncode({'t': 'comandas', 'bar': _bar, 'id': eu, 'porta': portaLan, 's': ass.assinar('udp', txt)}));
    final destinos = {'255.255.255.255'};
    final ip = meuIp;
    if (ip != null && ip.split('.').length == 4) destinos.add('${ip.substring(0, ip.lastIndexOf('.'))}.255');
    for (final d in destinos) {
      try {
        u.send(msg, InternetAddress(d), portaUdp);
      } catch (_) {}
    }
  }

  void _aoUdp(RawSocketEvent e) {
    if (e != RawSocketEvent.read) return;
    final dg = _udp?.receive();
    if (dg == null) return;
    try {
      final j = jsonDecode(utf8.decode(dg.data)) as Map<String, dynamic>;
      if (j['t'] != 'comandas' || j['bar'] != _bar || j['id'] == eu) return;
      if (!_ass!.confere(j['s'] as String?, 'udp', '${j['bar']}|${j['id']}|${j['porta']}')) return;
      conhecer(j['id'] as String, dg.address.address, j['porta'] as int, 'UDP');
    } catch (_) {}
  }

  // ------------------------------------------------------------------ batida (a cada 2 s)

  Future<void> _batida() async {
    if (_rodando || !ativa) return;
    _rodando = true;
    try {
      _tick++;
      if (_tick % 5 == 1) {
        meuIp = await app.ipLocal();
        sistema = await Sistema.estado();
        await app.lerBateria();
      }
      if (_tick % 2 == 1) _anunciar();

      final agora = agoraMs();
      pares.removeWhere((_, p) => agora - (p.vistoMs > p.conhecidoMs ? p.vistoMs : p.conhecidoMs) > 300000);
      final info = _minhaInfo();
      await Future.wait([
        for (final p in pares.values)
          if (agora - (p.vistoMs > p.conhecidoMs ? p.vistoMs : p.conhecidoMs) < 60000) _oi(p, info)
      ]);

      final antes = (eleicao.termo, eleicao.lider);
      final d = eleicao.passo(_euCandidato(), [for (final p in vivos()) p.candidato], agoraMs());
      if (d.acao == Acao.passar) await _passar(d.para!, 'nota maior');
      if (antes != (eleicao.termo, eleicao.lider)) _mudouLider(antes.$2);

      _verIsolamento();
      await _servico();
      await sincronizar();
    } catch (e) {
      debugPrint('[rede] erro na batida: $e');
    } finally {
      _rodando = false;
      app.avisar();
    }
  }

  Candidato _euCandidato() => Candidato(
      id: eu, nota: nota, elegivel: elegivel, termo: eleicao.termo, lider: eleicao.lider,
      bateria: app.bateria, carregando: app.carregando);

  String nomeDe(String? id) {
    if (id == null) return 'ninguém';
    if (id == eu) return 'este celular';
    final p = pares[id];
    return p == null ? id.substring(0, 6) : (p.usuario.isNotEmpty ? '${p.usuario} (${p.modelo})' : p.modelo);
  }

  void _mudouLider(String? antigo) {
    _log('líder: ${nomeDe(eleicao.lider)} (mandato ${eleicao.termo})');
    if (souLider) {
      // quem assume imprime o que ficou sem imprimir
      unawaited(app.imprimirPendentes(forcar: true));
    }
  }

  /// Troca combinada: só em momento calmo, e só depois de o novo líder ter tudo.
  Future<bool> _passar(String para, String motivo) async {
    final p = pares[para];
    if (p == null || _passando || app.imprimindo) return false;
    _passando = true;
    try {
      await _enviarTudo(p, marcar: true);
      eleicao.passarPara(para);
      _log('passou a liderança para ${nomeDe(para)} ($motivo)');
      await _oi(p, _minhaInfo());
      return true;
    } catch (e) {
      _log('não conseguiu passar a liderança: $e');
      return false;
    } finally {
      _passando = false;
    }
  }

  /// Ao encerrar o turno: se este celular é o líder, entrega para o melhor dos outros.
  Future<bool> passarAntesDeSair() async {
    if (!souLider) return true;
    final outros = vivos()..sort((a, b) => b.nota.compareTo(a.nota));
    if (outros.isEmpty) return true;
    for (final p in outros) {
      if (await _passar(p.id, 'encerrou o turno')) return true;
    }
    return false;
  }

  void _verIsolamento() {
    final ip = meuIp;
    if (ip == null || vivos().isNotEmpty) {
      isolamento = false;
      return;
    }
    String rede(String x) => x.contains('.') ? x.substring(0, x.lastIndexOf('.')) : x;
    // a VPS diz que há outro celular do bar na mesma Wi-Fi, mas ele não responde
    isolamento = pares.values.any((p) => p.origens.contains('vps') && p.vistoMs == 0 && p.falhas >= 5 && rede(p.ip) == rede(ip));
  }

  Future<void> _servico() async {
    // com um celular só não precisa de serviço; com 2+ o líder fica acordado
    final deve = souLider && vivos().isNotEmpty;
    if (deve && !_pediuNotificacao) {
      _pediuNotificacao = true;
      await Sistema.pedirNotificacao();
    }
    if (deve && !servicoLigado) {
      servicoLigado = await Sistema.servico(true, 'Este celular está cuidando da impressora do bar');
      if (servicoLigado) _log('serviço do líder ligado');
    } else if (!deve && servicoLigado) {
      await Sistema.servico(false);
      servicoLigado = false;
      _log('serviço do líder desligado');
    }
  }

  // ------------------------------------------------------------------ cópia dos eventos

  /// Manda ao par tudo que ele ainda não tem (menos o que veio dele).
  Future<void> _enviarTudo(Par p, {bool marcar = false}) async {
    for (var volta = 0; volta < 50; volta++) {
      final lista = await app.banco.eventosDesde(p.cursorEnviar, exceto: p.id, limite: 200);
      if (lista.isEmpty) return;
      await _post(p, '/eventos/enviar', {'de': eu, 'eventos': [for (final (_, ev) in lista) ev]},
          tempo: const Duration(seconds: 8));
      p.cursorEnviar = lista.last.$1;
      if (marcar) await app.banco.marcarNoLider([for (final (_, ev) in lista) ev['uuid'] as String]);
    }
  }

  /// Seguidor: manda o que é novo ao líder e baixa o que os outros fizeram.
  Future<void> sincronizar() async {
    if (!ativa) return;
    if (_sincronizando) {
      _pedirSync = true;
      return;
    }
    _sincronizando = true;
    try {
      do {
        _pedirSync = false;
        final l = parLider;
        if (souLider || l == null || !l.vivo(agoraMs())) break;
        await _enviarTudo(l, marcar: true);
        var mudou = false;
        for (var volta = 0; volta < 50; volta++) {
          final r = await _post(l, '/eventos/baixar', {'de': eu, 'desde': l.cursorBaixar},
              tempo: const Duration(seconds: 8));
          for (final ev in (r['eventos'] as List).cast<Map<String, dynamic>>()) {
            // o líder é quem sobe para a VPS; aqui fica só a cópia
            mudou |= await app.banco.inserirEvento(ev, enviado: true, origem: l.id);
          }
          l.cursorBaixar = r['ultimo'] as int;
          if (r['mais'] != true) break;
        }
        if (mudou) await app.aoChegarEventos();
      } while (_pedirSync);
    } catch (e) {
      debugPrint('[rede] sincronizar: $e');
    } finally {
      _sincronizando = false;
    }
  }

  /// Chamado logo depois de registrar um evento neste celular.
  void sincronizarJa() => unawaited(sincronizar());

  // ------------------------------------------------------------------ impressão via líder

  /// Só o líder fala com a impressora. Se o líder não estiver alcançável, imprime direto.
  Future<void> imprimir(String alvo, List<int> bytes) async {
    final l = parLider;
    if (souLider || l == null || !l.vivo(agoraMs())) {
      await Impressora.enviar(alvo, bytes);
      return;
    }
    Map<String, dynamic> r;
    try {
      r = await _post(l, '/imprimir', {'alvo': alvo, 'dados': base64Encode(bytes)}, tempo: const Duration(seconds: 25));
    } catch (_) {
      await Impressora.enviar(alvo, bytes); // líder não respondeu: tenta direto
      return;
    }
    if (r['ok'] != true) throw ErroImpressora('${r['erro'] ?? 'A impressora não respondeu'}');
  }
}
