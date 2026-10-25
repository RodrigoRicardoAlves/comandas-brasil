import 'dart:convert';

import 'package:path/path.dart' as p;
import 'package:sqflite/sqflite.dart';

/// Banco local do celular: guarda os eventos (tudo que aconteceu no bar) e configurações.
/// Assim o app funciona sem internet e nada se perde se o celular reiniciar.
class Banco {
  late Database _db;

  Future<void> abrir() async {
    final dir = await getDatabasesPath();
    _db = await openDatabase(
      p.join(dir, 'comandas.db'),
      version: 2,
      onCreate: (db, v) async {
        await db.execute('''CREATE TABLE eventos(
          id INTEGER PRIMARY KEY AUTOINCREMENT,
          uuid TEXT NOT NULL UNIQUE,
          json TEXT NOT NULL,
          hora INTEGER NOT NULL,
          enviado INTEGER NOT NULL DEFAULT 0,
          no_lider INTEGER NOT NULL DEFAULT 0,
          origem TEXT)''');
        await db.execute('CREATE TABLE kv(chave TEXT PRIMARY KEY, valor TEXT)');
      },
      onUpgrade: (db, de, para) async {
        if (de < 2) {
          await db.execute('ALTER TABLE eventos ADD COLUMN no_lider INTEGER NOT NULL DEFAULT 0');
          await db.execute('ALTER TABLE eventos ADD COLUMN origem TEXT');
        }
      },
    );
  }

  /// Guarda o evento. Devolve false se ele já existia (reenvio).
  /// - `enviado`: já está na VPS (veio de lá, ou outro celular é o responsável por subir).
  /// - `origem`: device_id do celular da rede local que mandou (para não devolver a ele).
  /// - `confirmadoVps`: se já existia, marca como entregue à VPS.
  Future<bool> inserirEvento(Map<String, dynamic> ev,
      {bool enviado = false, String? origem, bool confirmadoVps = false}) async {
    final id = await _db.insert(
      'eventos',
      {'uuid': ev['uuid'], 'json': jsonEncode(ev), 'hora': ev['hora'], 'enviado': enviado ? 1 : 0, 'origem': origem},
      conflictAlgorithm: ConflictAlgorithm.ignore,
    );
    if (id == 0 && confirmadoVps) {
      await _db.update('eventos', {'enviado': 1}, where: 'uuid = ?', whereArgs: [ev['uuid']]);
    }
    return id != 0;
  }

  /// Eventos guardados depois do id local `desde` (rede local). Pula os que vieram de `exceto`.
  Future<List<(int, Map<String, dynamic>)>> eventosDesde(int desde, {String? exceto, int limite = 300}) async {
    final rows = await _db.query('eventos',
        columns: ['id', 'json'],
        where: exceto == null ? 'id > ?' : 'id > ? AND (origem IS NULL OR origem != ?)',
        whereArgs: exceto == null ? [desde] : [desde, exceto],
        orderBy: 'id',
        limit: limite);
    return [for (final r in rows) (r['id'] as int, jsonDecode(r['json'] as String) as Map<String, dynamic>)];
  }

  Future<int> ultimoId() async => Sqflite.firstIntValue(await _db.rawQuery('SELECT MAX(id) FROM eventos')) ?? 0;

  /// O líder da rede local confirmou que recebeu.
  Future<void> marcarNoLider(List<String> uuids) async {
    if (uuids.isEmpty) return;
    final b = _db.batch();
    for (final u in uuids) {
      b.update('eventos', {'no_lider': 1}, where: 'uuid = ?', whereArgs: [u]);
    }
    await b.commit(noResult: true);
  }

  /// Registros que ainda só existem neste celular (nem na VPS, nem no líder).
  Future<int> contarPendentes() async => Sqflite.firstIntValue(
          await _db.rawQuery('SELECT COUNT(*) FROM eventos WHERE enviado = 0 AND no_lider = 0')) ??
      0;

  Future<List<Map<String, dynamic>>> eventos() async {
    final rows = await _db.query('eventos', columns: ['json'], orderBy: 'id');
    return [for (final r in rows) jsonDecode(r['json'] as String) as Map<String, dynamic>];
  }

  Future<List<Map<String, dynamic>>> naoEnviados({int limite = 200}) async {
    final rows = await _db.query('eventos', columns: ['json'], where: 'enviado = 0', orderBy: 'id', limit: limite);
    return [for (final r in rows) jsonDecode(r['json'] as String) as Map<String, dynamic>];
  }

  Future<int> contarNaoEnviados() async =>
      Sqflite.firstIntValue(await _db.rawQuery('SELECT COUNT(*) FROM eventos WHERE enviado = 0')) ?? 0;

  Future<void> marcarEnviados(List<String> uuids) async {
    if (uuids.isEmpty) return;
    final b = _db.batch();
    for (final u in uuids) {
      b.update('eventos', {'enviado': 1}, where: 'uuid = ?', whereArgs: [u]);
    }
    await b.commit(noResult: true);
  }

  /// Apaga eventos antigos já enviados (o histórico fica na VPS).
  Future<void> limparAntigos(Set<String> manter) async {
    final corte = DateTime.now().subtract(const Duration(hours: 36)).millisecondsSinceEpoch;
    final rows = await _db.query('eventos', columns: ['uuid', 'json'], where: 'enviado = 1 AND hora < ?', whereArgs: [corte]);
    final apagar = <String>[];
    for (final r in rows) {
      final d = (jsonDecode(r['json'] as String)['dados'] as Map?) ?? {};
      if (!manter.contains(d['comanda'])) apagar.add(r['uuid'] as String);
    }
    final b = _db.batch();
    for (final u in apagar) {
      b.delete('eventos', where: 'uuid = ?', whereArgs: [u]);
    }
    await b.commit(noResult: true);
  }

  /// Apaga tudo deste celular: eventos e configurações. Usado pelo "Reset de fábrica".
  Future<void> apagarTudo() async {
    await _db.delete('eventos');
    await _db.delete('kv');
  }

  Future<String?> ler(String chave) async {
    final r = await _db.query('kv', where: 'chave = ?', whereArgs: [chave]);
    return r.isEmpty ? null : r.first['valor'] as String?;
  }

  Future<void> gravar(String chave, String? valor) async {
    if (valor == null) {
      await _db.delete('kv', where: 'chave = ?', whereArgs: [chave]);
    } else {
      await _db.insert('kv', {'chave': chave, 'valor': valor}, conflictAlgorithm: ConflictAlgorithm.replace);
    }
  }

  Future<Map<String, dynamic>?> lerJson(String chave) async {
    final v = await ler(chave);
    return v == null ? null : jsonDecode(v) as Map<String, dynamic>;
  }

  Future<void> gravarJson(String chave, Object? valor) => gravar(chave, valor == null ? null : jsonEncode(valor));
}
