import 'package:flutter/widgets.dart';
import 'package:workmanager/workmanager.dart';

import 'app.dart' show servidorPadrao;
import 'dados/api.dart';
import 'dados/banco.dart';
import 'util.dart';

/// Com o app fechado, o Android roda isto mais ou menos a cada 15 minutos (quando há internet):
/// envia ao servidor o que ficou na fila deste celular. Com o app aberto, quem envia é o próprio app.
@pragma('vm:entry-point')
void tarefaSegundoPlano() {
  WidgetsFlutterBinding.ensureInitialized();
  Workmanager().executeTask((tarefa, dados) async {
    try {
      await subirFila();
    } catch (_) {}
    return true; // não pede nova tentativa imediata: a próxima rodada periódica tenta de novo
  });
}

Future<void> subirFila() async {
  final banco = Banco();
  await banco.abrir();
  final vivo = int.tryParse(await banco.ler('app_vivo_em') ?? '') ?? 0;
  if (agoraMs() - vivo < 60000) return; // o app está aberto e cuidando disso
  final token = await banco.ler('token');
  if (token == null) return;
  final api = Api(await banco.ler('servidor') ?? servidorPadrao, token: token);
  for (var volta = 0; volta < 10; volta++) {
    final evs = await banco.naoEnviados();
    if (evs.isEmpty) break;
    final r = await api.post('/eventos', {'eventos': evs}, const Duration(seconds: 30));
    await banco.marcarEnviados([
      for (final a in (r['aceitos'] as List)) a['uuid'] as String,
      for (final e in (r['erros'] as List)) e['uuid'] as String,
    ]);
  }
}

Future<void> agendarSegundoPlano() async {
  try {
    await Workmanager().initialize(tarefaSegundoPlano);
    await Workmanager().registerPeriodicTask(
      'subir-fila',
      'subir-fila',
      frequency: const Duration(minutes: 15),
      constraints: Constraints(networkType: NetworkType.connected),
      existingWorkPolicy: ExistingPeriodicWorkPolicy.keep,
    );
  } catch (e) {
    debugPrint('segundo plano: $e');
  }
}
