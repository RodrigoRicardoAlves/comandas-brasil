import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:battery_plus/battery_plus.dart';
import 'package:crypto/crypto.dart';
import 'package:device_info_plus/device_info_plus.dart';
import 'package:flutter/foundation.dart';
import 'package:network_info_plus/network_info_plus.dart';
import 'package:package_info_plus/package_info_plus.dart';
import 'package:uuid/uuid.dart';

import 'dados/api.dart';
import 'dados/banco.dart';
import 'dados/estado.dart';
import 'dados/modelos.dart';
import 'impressao/cupons.dart';
import 'impressao/impressora.dart';
import 'rede/rede_local.dart';
import 'sistema.dart';
import 'util.dart';

const servidorPadrao = String.fromEnvironment('SERVIDOR', defaultValue: 'https://bar.rodrigoricardo.eng.br');
const _uuid = Uuid();

/// Item no carrinho antes de enviar o pedido.
class ItemCarrinho {
  final Produto produto;
  final Variante variante;
  int qtd;
  String obs;
  ItemCarrinho(this.produto, this.variante, {this.qtd = 1, this.obs = ''});
  int get total => variante.preco * qtd;
}

class ErroApp implements Exception {
  final String msg;
  ErroApp(this.msg);
  @override
  String toString() => msg;
}

/// Controla tudo: sessão, eventos, envio para a VPS e impressão.
/// As telas só leem daqui e chamam os métodos de ação.
class App extends ChangeNotifier {
  static final App i = App._();
  App._();

  final banco = Banco();
  late final rede = RedeLocal(this);
  final _bateria = Battery();
  late Api api;

  // aparelho
  String deviceId = '';
  String modelo = 'Android';
  String versaoApp = '';

  // sessão
  String servidor = servidorPadrao;
  Bootstrap? boot;
  Usuario? usuario; // quem está usando o celular agora
  int loginEm = 0; // quando entrou (desempata se o mesmo garçom aparecer em dois celulares)
  String? avisoSessao; // por que a sessão foi encerrada (mostrado na tela de PIN)
  String? _pinPendente; // entrou sem internet: confirma no servidor quando conectar (só na memória)
  bool get logado => usuario != null && boot != null;
  bool get temSessaoServidor => api.token != null;

  // situação
  Estado estado = Estado();
  bool online = false;
  DateTime? ultimoContato;
  int naFila = 0;
  String? erroImpressora;
  List<Map<String, dynamic>> chamados = [];
  List<Map<String, dynamic>> aparelhos = [];
  int? bateria;
  bool carregando = false;
  String impressoraLocal = ''; // substitui a impressora do bar neste celular (testes)

  int _ultimoSeq = 0;
  Timer? _timer;
  bool _ciclando = false;
  final Map<String, (int, int)> _tentativasImpressao = {}; // ref -> (tentativas, últimaMs)
  final Set<int> _chamadosImpressos = {};

  // ------------------------------------------------------------------ início

  Future<void> iniciar() async {
    await banco.abrir();
    deviceId = await banco.ler('device_id') ?? '';
    if (deviceId.isEmpty) {
      deviceId = _uuid.v4();
      await banco.gravar('device_id', deviceId);
    }
    try {
      final info = await DeviceInfoPlugin().androidInfo;
      modelo = '${info.manufacturer} ${info.model}'.trim();
      versaoApp = (await PackageInfo.fromPlatform()).version;
    } catch (_) {}
    servidor = await banco.ler('servidor') ?? servidorPadrao;
    impressoraLocal = await banco.ler('impressora_local') ?? '';
    api = Api(servidor, token: await banco.ler('token'));
    _ultimoSeq = int.tryParse(await banco.ler('ultimo_seq') ?? '') ?? 0;
    final b = await banco.lerJson('bootstrap');
    if (b != null) boot = Bootstrap.json(b);
    final u = await banco.lerJson('usuario');
    if (u != null && boot != null) usuario = Usuario.json(u);
    loginEm = int.tryParse(await banco.ler('login_em') ?? '') ?? 0;
    if (usuario != null && loginEm == 0) await _marcarLogin();
    // ninguém logado mas com sessão guardada (versão antiga): libera o garçom no servidor
    if (usuario == null && api.token != null) await trocarUsuario();
    await _recalcular();
    Sistema.iniciar();
    if (logado) unawaited(rede.iniciar());
    _timer = Timer.periodic(const Duration(seconds: 4), (_) => ciclo());
    unawaited(ciclo());
  }

  Future<void> _recalcular() async {
    estado = Estado.montar(await banco.eventos());
    naFila = await banco.contarPendentes();
    notifyListeners();
  }

  /// Para a rede local avisar as telas.
  void avisar() => notifyListeners();

  /// Chegaram eventos de outro celular (rede local).
  Future<void> aoChegarEventos() async {
    await _recalcular();
    unawaited(imprimirPendentes());
  }

  // ------------------------------------------------------------------ login

  String hashPin(String pin) => sha256.convert(utf8.encode('${boot!.pinSalt}$pin')).toString();

  /// Primeiro acesso (ou troca de bar): precisa de internet.
  Future<void> entrarNoBar(String servidorUrl, String slug, String pin) async {
    servidor = servidorUrl.trim().replaceAll(RegExp(r'/+$'), '');
    final a = Api(servidor);
    final r = await a.post('/login', {
      'bar': slug.trim().toLowerCase(),
      'pin': pin,
      'device_id': deviceId,
      'modelo': modelo,
      'versao_app': versaoApp,
    });
    final mudouBar = boot != null && boot!.bar.slug != (r['bar'] as Map)['slug'];
    if (mudouBar && await banco.contarNaoEnviados() > 0) {
      throw ErroApp('Este celular ainda tem pedidos do outro bar para enviar. Conecte e aguarde antes de trocar.');
    }
    api = Api(servidor, token: r['token'] as String);
    await banco.gravar('servidor', servidor);
    await banco.gravar('token', api.token);
    final b = await api.get('/bootstrap');
    boot = Bootstrap.json(b);
    await banco.gravarJson('bootstrap', b);
    usuario = boot!.usuarios.firstWhere((u) => u.id == (r['usuario'] as Map)['id']);
    await banco.gravarJson('usuario', usuario!.json());
    await _marcarLogin();
    if (mudouBar) _ultimoSeq = 0;
    online = true;
    await _recalcular();
    if (mudouBar) await rede.parar();
    unawaited(rede.iniciar());
    unawaited(ciclo());
  }

  Future<void> _marcarLogin() async {
    loginEm = agoraMs();
    avisoSessao = null;
    await banco.gravar('login_em', '$loginEm');
  }

  /// Em qual outro celular este garçom está agora (rede local ou VPS). null = em nenhum.
  String? celularEmUso(Usuario u) {
    for (final p in rede.vivos()) {
      if (p.usuarioId == u.id) return p.modelo.isEmpty ? 'outro celular' : p.modelo;
    }
    final recente = ultimoContato != null && DateTime.now().difference(ultimoContato!).inSeconds < 60;
    for (final ap in recente ? aparelhos : const <Map<String, dynamic>>[]) {
      if (ap['usuario_id'] == u.id && ap['device_id'] != deviceId) return '${ap['modelo'] ?? 'outro celular'}';
    }
    return null;
  }

  Map<String, dynamic> _dadosLogin(String pin) =>
      {'bar': boot!.bar.slug, 'pin': pin, 'device_id': deviceId, 'modelo': modelo, 'versao_app': versaoApp};

  /// Troca de garçom no mesmo celular: funciona sem internet (confere o PIN guardado).
  /// O mesmo garçom não pode estar em dois celulares ao mesmo tempo.
  Future<void> entrarComPin(String pin) async {
    if (boot == null) throw ErroApp('Faça o primeiro acesso com internet');
    final h = hashPin(pin);
    final u = boot!.usuarios.where((u) => u.pinHash == h).firstOrNull;
    if (u == null) throw ErroApp('PIN incorreto');
    if (!rede.ativa) {
      // rede local desligada (encerrou o turno): liga e dá um tempo para achar os outros celulares
      await rede.iniciar();
      await Future.delayed(const Duration(seconds: 4));
    }
    final outro = celularEmUso(u);
    if (outro != null) {
      throw ErroApp('${u.nome} já está usando o celular $outro. Encerre o turno nele primeiro.');
    }
    // com internet, o servidor confirma (ele sabe de celulares que esta rede não enxerga)
    _pinPendente = null;
    try {
      final r = await api.post('/login', _dadosLogin(pin), const Duration(seconds: 4));
      api.token = r['token'] as String;
      await banco.gravar('token', api.token);
    } on ErroApi catch (e) {
      if (e.status == 409) throw ErroApp(e.msg);
      _pinPendente = pin;
    } catch (_) {
      _pinPendente = pin; // sem internet: confirma quando conectar
    }
    usuario = u;
    await banco.gravarJson('usuario', u.json());
    await _marcarLogin();
    notifyListeners();
    unawaited(rede.iniciar());
    unawaited(ciclo());
  }

  /// Sai do garçom atual sem apagar nada (os registros dele continuam na fila).
  Future<void> _encerrarSessao(String motivo) async {
    if (usuario == null) return;
    avisoSessao = motivo;
    _pinPendente = null;
    await trocarUsuario();
  }

  /// O mesmo garçom apareceu em outro celular da rede (entraram enquanto estavam separados):
  /// fica quem entrou primeiro.
  Future<void> verificarDuplicado() async {
    final u = usuario;
    if (u == null) return;
    for (final p in rede.vivos()) {
      if (p.usuarioId != u.id) continue;
      final elePrimeiro = p.loginEm < loginEm || (p.loginEm == loginEm && p.id.compareTo(deviceId) < 0);
      if (elePrimeiro) {
        await _encerrarSessao('${u.nome} já estava no celular ${p.modelo}. Este celular saiu; '
            'o que você lançou aqui foi guardado.');
        return;
      }
    }
  }

  /// Confere um PIN de gerente (autorizar cancelamento etc.). Devolve o gerente ou null.
  Usuario? gerenteDoPin(String pin) {
    final h = hashPin(pin);
    return boot?.usuarios.where((u) => u.pinHash == h && u.gerente).firstOrNull;
  }

  /// Volta para a tela de primeiro acesso (os dados guardados só somem quando entrar em outro bar).
  void esquecerBar() {
    boot = null;
    notifyListeners();
  }

  /// Tira o garçom do celular (volta para a tela de PIN). Avisa o servidor, para ele poder
  /// entrar em outro celular. Os registros já feitos continuam na fila.
  Future<void> trocarUsuario() async {
    usuario = null;
    _pinPendente = null;
    await banco.gravar('usuario', null);
    notifyListeners();
    final t = api.token;
    api.token = null;
    await banco.gravar('token', null);
    if (t != null) {
      unawaited(Api(servidor, token: t).post('/logout', null, const Duration(seconds: 5)).then((_) {}, onError: (_) {}));
    }
  }

  /// Ir embora: só com tudo enviado.
  Future<void> encerrarTurno() async {
    await rede.sincronizar();
    await ciclo();
    final n = await banco.contarPendentes();
    if (n > 0) {
      throw ErroApp('Ainda há $n registro(s) só neste celular (não chegaram ao líder nem ao servidor). '
          'Conecte à Wi-Fi do bar ou à internet e tente de novo.');
    }
    if (!await rede.passarAntesDeSair()) {
      throw ErroApp('Este celular é o líder e não conseguiu passar a vez para outro. Tente de novo.');
    }
    await rede.parar();
    await trocarUsuario();
  }

  // ------------------------------------------------------------------ eventos

  Future<Map<String, dynamic>> _registrar(String tipo, Map<String, dynamic> dados) async {
    final ev = {
      'uuid': _uuid.v4(),
      'tipo': tipo,
      'device_id': deviceId,
      'usuario': usuario?.nome ?? '',
      'hora': agoraMs(),
      'dados': dados,
    };
    await banco.inserirEvento(ev);
    await _recalcular();
    rede.sincronizarJa();
    unawaited(ciclo());
    return ev;
  }

  void _exigirLogin() {
    if (!logado) throw ErroApp('Entre com seu PIN');
  }

  Future<ComandaC> abrirComanda(int numero, String nome) async {
    _exigirLogin();
    final max = boot!.bar.maxComanda;
    nome = limpo(nome, 40);
    if (numero < 1 || numero > max) throw ErroApp('O número da comanda vai de 1 a $max');
    if (nome.isEmpty) throw ErroApp('Informe o nome do cliente');
    final outra = estado.abertaComNumero(numero);
    if (outra != null) throw ErroApp('A comanda $numero já está aberta (${outra.nome})');
    final uuid = _uuid.v4();
    await _registrar('comanda_aberta', {'comanda': uuid, 'numero': numero, 'nome': nome});
    return estado.comandas[uuid]!;
  }

  Future<void> editarComanda(ComandaC c, int numero, String nome) async {
    _exigirLogin();
    nome = limpo(nome, 40);
    if (nome.isEmpty || numero < 1 || numero > boot!.bar.maxComanda) {
      throw ErroApp('Informe nome e número de 1 a ${boot!.bar.maxComanda}');
    }
    final outra = estado.abertaComNumero(numero, exceto: c.uuid);
    if (outra != null) throw ErroApp('A comanda $numero já está aberta (${outra.nome})');
    await _registrar('comanda_editada', {'comanda': c.uuid, 'numero': numero, 'nome': nome});
  }

  Future<void> lancarPedido(ComandaC c, List<ItemCarrinho> carrinho) async {
    _exigirLogin();
    final atual = estado.comandas[c.uuid];
    if (atual == null || !atual.aberta) throw ErroApp('Esta comanda não está mais aberta');
    if (estado.emConflito(atual)) {
      throw ErroApp('Existem duas comandas ${atual.numero} abertas. Feche uma delas antes de lançar.');
    }
    if (carrinho.isEmpty) throw ErroApp('Pedido vazio');
    await _registrar('pedido_lancado', {
      'pedido': _uuid.v4(),
      'comanda': c.uuid,
      // "feito sem conexão": o líder (quem imprime) não estava ao alcance, ou o celular está sem Wi-Fi
      'offline': !rede.liderAlcancavel || (rede.meuIp == null && !online),
      'itens': [
        for (final it in carrinho)
          {
            'item': _uuid.v4(),
            'variante_id': it.variante.id,
            'categoria': it.produto.categoria,
            'produto': it.produto.nome,
            'variante': it.variante.nome,
            'preco': it.variante.preco,
            'qtd': it.qtd,
            'obs': limpo(it.obs, 80),
            'setor': it.produto.setor,
            'imprime': it.produto.imprime,
          }
      ],
    });
    unawaited(imprimirPendentes());
  }

  Future<void> cancelarItem(ItemC item, {String? autorizadoPor}) async {
    _exigirLogin();
    await _registrar('item_cancelado', {'item': item.uuid, 'autorizado_por': ?autorizadoPor});
    final c = estado.comandas[item.comanda];
    final foiImpresso = estado.impressos.contains('${item.pedido}:${item.setor}');
    if (c != null && item.imprime && foiImpresso) {
      try {
        await _imprimir(_alvo(item.setor), cupomCancelamento(boot!.bar, c, item, usuario!.nome));
      } catch (e) {
        _erroImpressao(e);
      }
    }
  }

  int totalComServico(ComandaC c, bool servico) =>
      c.subtotal + (servico ? (c.subtotal * boot!.bar.taxaServico / 100).round() : 0);

  Future<void> imprimirConta(ComandaC c, {required bool servico, required int pessoas}) async {
    _exigirLogin();
    await _imprimir(_alvo(''), cupomConta(boot!.bar, c, servico: servico, pessoas: pessoas));
    erroImpressora = null;
    await _registrar('conta_impressa', {'comanda': c.uuid, 'servico': servico, 'pessoas': pessoas});
  }

  /// Motivos para NÃO fechar agora (pode haver pedido desta comanda ainda não chegado).
  /// Vazio = pode fechar. O gerente pode forçar mesmo assim.
  Future<List<String>> riscosFechamento() async {
    final r = <String>[];
    if (rede.ativa && !rede.liderAlcancavel) {
      r.add('Este celular está sem contato com o celular líder. Conecte à Wi-Fi do bar.');
    }
    // quem está conectado normalmente entrega a fila em segundos: espera um pouco antes de reclamar
    for (var i = 0; i < 4; i++) {
      if (rede.vivos().every((p) => p.pendentes == 0)) break;
      await Future.delayed(const Duration(milliseconds: 1500));
    }
    for (final p in rede.vivos().where((p) => p.pendentes > 0)) {
      r.add('${rede.nomeDe(p.id)} ainda tem ${p.pendentes} registro(s) para entregar.');
    }
    final agora = agoraMs();
    for (final p in rede.pares.values) {
      if (!p.vivo(agora) && p.pendentes > 0) {
        r.add('${rede.nomeDe(p.id)} saiu da rede às ${hhmm(p.vistoMs)} com ${p.pendentes} registro(s) guardado(s).');
      }
    }
    final naRede = {for (final p in rede.vivos()) p.id};
    for (final ap in aparelhos) {
      final n = (ap['pendentes'] ?? 0) as int;
      if (ap['device_id'] != deviceId && !naRede.contains(ap['device_id']) && n > 0) {
        r.add('${ap['usuario']} (${ap['modelo']}) tem $n registro(s) que não chegaram a este celular.');
      }
    }
    return r;
  }

  Future<void> fecharComanda(ComandaC c, {required bool servico, bool forcado = false, String? autorizadoPor}) async {
    _exigirLogin();
    final atual = estado.comandas[c.uuid];
    if (atual == null || !atual.aberta) throw ErroApp('Comanda já estava fechada');
    await _registrar('comanda_fechada', {
      'comanda': c.uuid,
      'taxa_servico': servico ? boot!.bar.taxaServico : 0,
      'total': totalComServico(atual, servico),
      'forcado': forcado,
      'autorizado_por': ?autorizadoPor,
      // pedidos que este celular conhecia: um pedido desta comanda que chegar depois vira pendência
      'pedidos': [for (final p in atual.pedidos) p.uuid],
    });
  }

  /// Conflito de número: passa todos os pedidos desta comanda para a outra e esta some.
  Future<void> juntarComanda(ComandaC de, ComandaC para) async {
    _exigirLogin();
    if (!de.aberta || !para.aberta) throw ErroApp('As duas comandas precisam estar abertas');
    await _registrar('comanda_juntada', {'comanda': de.uuid, 'para': para.uuid});
  }

  /// Gerente decide o que fazer com um pedido que chegou depois do fechamento.
  /// acao: 'mover' (para outra comanda aberta) ou 'descartar'. Para reabrir, use reabrirComanda.
  Future<void> resolverPendencia(PedidoC p, String acao, {ComandaC? para, required String gerente}) async {
    _exigirLogin();
    if (acao == 'mover' && (para == null || !para.aberta)) throw ErroApp('Escolha uma comanda aberta');
    await _registrar('pendencia_resolvida', {
      'pedido': p.uuid,
      'acao': acao,
      'para': ?para?.uuid,
      'autorizado_por': gerente,
    });
    unawaited(imprimirPendentes());
  }

  Future<void> reabrirComanda(ComandaC c, {String? autorizadoPor}) async {
    _exigirLogin();
    final outra = estado.abertaComNumero(c.numero);
    if (outra != null) throw ErroApp('Já existe outra comanda ${c.numero} aberta. Feche-a ou troque o número antes.');
    await _registrar('comanda_reaberta', {'comanda': c.uuid, 'autorizado_por': ?autorizadoPor});
    unawaited(imprimirPendentes()); // pedidos atrasados desta comanda voltam a valer
  }

  Future<void> descartarComanda(ComandaC c) async {
    _exigirLogin();
    if (c.itensAtivos.isNotEmpty) throw ErroApp('Só dá para descartar comanda sem itens');
    await _registrar('comanda_descartada', {'comanda': c.uuid});
  }

  // ------------------------------------------------------------------ impressão

  String _alvo(String setor) {
    if (impressoraLocal.isNotEmpty) return impressoraLocal;
    return boot!.impressoraDoSetor(setor);
  }

  void _erroImpressao(Object e) {
    erroImpressora = e is ErroImpressora ? e.msg : 'Falha na impressora: $e';
    notifyListeners();
  }

  /// Só o líder imprime os pedidos (de todos os celulares). Enquanto a eleição não termina
  /// (primeiros segundos), ninguém imprime.
  bool _imprimoEste(PedidoC p) => rede.souLider;

  /// Envia para a impressora: direto se for o líder, senão pede ao líder.
  Future<void> _imprimir(String alvo, List<int> bytes) => rede.imprimir(alvo, bytes);

  bool _imprimindo = false;
  bool get imprimindo => _imprimindo;

  Future<void> imprimirPendentes({bool forcar = false}) async {
    if (_imprimindo || boot == null) return;
    _imprimindo = true;
    try {
      for (final (p, setor) in estado.cuponsPendentes(meu: _imprimoEste)) {
        final ref = '${p.uuid}:$setor';
        final (n, ultima) = _tentativasImpressao[ref] ?? (0, 0);
        // nova tentativa com espera crescente (até 1 min); nunca desiste
        if (!forcar && agoraMs() - ultima < (15000 * n).clamp(0, 60000)) continue;
        final c = estado.comandas[p.comanda];
        if (c == null) continue;
        try {
          await _imprimir(_alvo(setor), cupomPedido(boot!.bar, c, p, setor));
          _tentativasImpressao.remove(ref);
          erroImpressora = null;
          await _registrar('impresso', {'ref': ref, 'setor': setor});
        } catch (e) {
          _tentativasImpressao[ref] = (n + 1, agoraMs());
          _erroImpressao(e);
          break; // impressora fora: não adianta tentar os outros agora
        }
      }
    } finally {
      _imprimindo = false;
    }
  }

  int get cuponsNaoImpressos => estado.cuponsPendentes(meu: _imprimoEste).length;

  Future<void> reimprimirPedido(PedidoC p) async {
    final c = estado.comandas[p.comanda]!;
    for (final s in p.setores) {
      await _imprimir(_alvo(s), cupomPedido(boot!.bar, c, p, s, reimpressao: estado.impressos.contains('${p.uuid}:$s')));
      if (!estado.impressos.contains('${p.uuid}:$s')) await _registrar('impresso', {'ref': '${p.uuid}:$s', 'setor': s});
    }
    erroImpressora = null;
    notifyListeners();
  }

  Future<void> imprimirTeste([String? alvo]) async {
    final a = alvo ?? _alvo('');
    await _imprimir(a, cupomTeste(boot!.bar, a, '$modelo (${usuario?.nome ?? '-'})'));
    erroImpressora = null;
    notifyListeners();
  }

  Future<void> definirImpressoraLocal(String v) async {
    impressoraLocal = v.trim();
    await banco.gravar('impressora_local', impressoraLocal.isEmpty ? null : impressoraLocal);
    notifyListeners();
  }

  // ------------------------------------------------------------------ chamados (QR)

  Future<void> atenderChamado(int id) async {
    chamados.removeWhere((c) => c['id'] == id);
    notifyListeners();
    await api.post('/chamados/$id/atendido');
  }

  /// O líder imprime os chamados (evita cupom repetido).
  bool get _souQuemImprimeChamados => rede.souLider;

  Future<void> _imprimirChamados() async {
    if (!_souQuemImprimeChamados) return;
    for (final ch in chamados) {
      final id = ch['id'] as int;
      if (ch['impresso'] == true || _chamadosImpressos.contains(id)) continue;
      try {
        await _imprimir(_alvo(''), cupomChamado(boot!.bar, ch));
        _chamadosImpressos.add(id);
        await api.post('/chamados/$id/impresso');
      } catch (e) {
        _erroImpressao(e);
        return;
      }
    }
  }

  // ------------------------------------------------------------------ sincronização com a VPS

  Future<void> ciclo() async {
    if (_ciclando || boot == null) return;
    if (api.token == null && _pinPendente == null) return;
    _ciclando = true;
    try {
      await lerBateria();
      // entrou sem internet: confirma agora no servidor
      final pin = _pinPendente;
      if (pin != null && usuario != null) {
        try {
          final r = await api.post('/login', _dadosLogin(pin));
          api.token = r['token'] as String;
          await banco.gravar('token', api.token);
          _pinPendente = null;
        } on ErroApi catch (e) {
          if (e.status == 409) {
            await _encerrarSessao(e.msg);
            return;
          }
          if (e.status == 401) _pinPendente = null; // PIN mudou no painel
        }
      }
      if (api.token == null) return;
      // 1) envia o que está na fila
      for (var volta = 0; volta < 10; volta++) {
        final evs = await banco.naoEnviados();
        if (evs.isEmpty) break;
        final r = await api.post('/eventos', {'eventos': evs}, const Duration(seconds: 20));
        await banco.marcarEnviados([
          for (final a in (r['aceitos'] as List)) a['uuid'] as String,
          // evento recusado pelo servidor não deve travar a fila
          for (final e in (r['erros'] as List)) e['uuid'] as String,
        ]);
      }
      // 2) recebe o que os outros celulares fizeram
      final r = await api.get('/eventos?desde=$_ultimoSeq');
      var mudou = false;
      for (final ev in (r['eventos'] as List).cast<Map<String, dynamic>>()) {
        _ultimoSeq = ev['seq'] as int;
        ev.remove('seq');
        ev['hora'] = DateTime.parse(ev['hora'] as String).millisecondsSinceEpoch;
        mudou |= await banco.inserirEvento(ev, enviado: true, confirmadoVps: true);
      }
      await banco.gravar('ultimo_seq', '$_ultimoSeq');
      // 3) presença: avisa que está vivo e recebe aparelhos/chamados
      final ip = await ipLocal();
      final p = await api.post('/presenca', {
        'ip': ip ?? '',
        'porta': rede.ativa ? portaLan : null,
        'bateria': bateria,
        'carregando': carregando,
        'lider': rede.souLider,
        'pendentes': await banco.contarPendentes(),
      });
      aparelhos = (p['aparelhos'] as List).cast<Map<String, dynamic>>();
      for (final ap in aparelhos) {
        // a VPS também conta onde estão os outros celulares do bar
        if (ap['ip'] is String && ap['porta'] is int) {
          rede.conhecer(ap['device_id'] as String, ap['ip'] as String, ap['porta'] as int, 'vps');
        }
      }
      chamados = (p['chamados'] as List).cast<Map<String, dynamic>>();
      if ((p['versao_cardapio'] as int) != boot?.bar.versaoCardapio) await atualizarCardapio();
      online = true;
      ultimoContato = DateTime.now();
      if (mudou) {
        await _recalcular();
      } else {
        naFila = await banco.contarPendentes();
      }
      unawaited(_imprimirChamados());
    } on ErroApi catch (e) {
      if (e.status == 401) {
        // sessão encerrada no servidor: gerente desconectou o celular ou o garçom entrou em outro
        api.token = null;
        await banco.gravar('token', null);
        await _encerrarSessao('Sua sessão foi encerrada: você entrou em outro celular ou o gerente '
            'desconectou este. Digite o PIN para entrar de novo.');
      }
      online = e.status < 500;
    } catch (_) {
      online = false;
    } finally {
      _ciclando = false;
      notifyListeners();
    }
    unawaited(imprimirPendentes());
  }

  Future<void> atualizarCardapio() async {
    final b = await api.get('/bootstrap');
    boot = Bootstrap.json(b);
    await banco.gravarJson('bootstrap', b);
    if (usuario != null) {
      usuario = boot!.usuarios.where((u) => u.id == usuario!.id).firstOrNull;
      await banco.gravarJson('usuario', usuario?.json());
    }
    notifyListeners();
  }

  Future<void> lerBateria() async {
    try {
      bateria = await _bateria.batteryLevel;
      final s = await _bateria.batteryState;
      // na tomada conta como carregando, mesmo com a bateria cheia
      carregando = s == BatteryState.charging || s == BatteryState.full || s == BatteryState.connectedNotCharging;
    } catch (_) {}
  }

  Future<String?> ipLocal() async {
    try {
      final ip = await NetworkInfo().getWifiIP();
      if (ip != null) return ip;
      for (final n in await NetworkInterface.list(type: InternetAddressType.IPv4)) {
        if (n.name.startsWith('wlan')) return n.addresses.first.address;
      }
    } catch (_) {}
    return null;
  }

  @override
  void dispose() {
    _timer?.cancel();
    super.dispose();
  }
}
