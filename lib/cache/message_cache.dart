import 'dart:convert';

import 'package:path/path.dart' as p;
import 'package:pocketbase/pocketbase.dart';
import 'package:sqflite/sqflite.dart';

import '../config.dart';

/// Local SQLite mirror of the chat history, so the chat opens instantly and
/// works offline.
///
/// Invariant: for each user the cache holds one *contiguous* slice of the
/// server history, from the newest synced message down to the oldest one
/// fetched so far. That's what lets "load older" read from here first and
/// only hit the server when it runs past the oldest cached message.
class MessageCache {
  MessageCache._(this._db);

  static MessageCache? _instance;
  static MessageCache get instance => _instance!;

  final Database _db;

  static Future<void> open() async {
    if (_instance != null) return;
    final path = p.join(await getDatabasesPath(), 'ft_chat_cache.db');
    final db = await openDatabase(
      path,
      version: 1,
      onCreate: (db, _) async {
        await db.execute('''
          CREATE TABLE messages (
            id      TEXT PRIMARY KEY,
            user    TEXT NOT NULL,
            created TEXT NOT NULL,
            json    TEXT NOT NULL
          )''');
        await db.execute(
            'CREATE INDEX idx_messages_user_created ON messages (user, created DESC, id DESC)');
        await db.execute('CREATE TABLE meta (key TEXT PRIMARY KEY, value TEXT)');
        await db.execute('CREATE TABLE file_meta (key TEXT PRIMARY KEY, size INTEGER, type TEXT)');
      },
    );
    _instance = MessageCache._(db);
  }

  // ---------------------------------------------------------------------------
  // Messages
  // ---------------------------------------------------------------------------

  static const _order = 'created DESC, id DESC';

  List<RecordModel> _rows(List<Map<String, Object?>> rows) => [
        for (final r in rows)
          RecordModel.fromJson(jsonDecode(r['json']! as String) as Map<String, dynamic>),
      ];

  /// Newest [limit] messages.
  Future<List<RecordModel>> latest(String user, int limit) async => _rows(await _db.query(
        'messages',
        where: 'user = ?',
        whereArgs: [user],
        orderBy: _order,
        limit: limit,
      ));

  /// Up to [limit] messages strictly older than (created, id).
  Future<List<RecordModel>> olderThan(String user, String created, String id, int limit) async =>
      _rows(await _db.query(
        'messages',
        where: 'user = ? AND (created < ? OR (created = ? AND id < ?))',
        whereArgs: [user, created, created, id],
        orderBy: _order,
        limit: limit,
      ));

  Future<void> upsertAll(Iterable<RecordModel> records) async {
    final batch = _db.batch();
    for (final r in records) {
      batch.insert(
        'messages',
        {
          'id': r.id,
          'user': r.getStringValue('user'),
          'created': r.getStringValue('created'),
          'json': jsonEncode(r.toJson()),
        },
        conflictAlgorithm: ConflictAlgorithm.replace,
      );
    }
    await batch.commit(noResult: true);
  }

  /// Replace a message only if it's already cached. Used for realtime edits:
  /// inserting an old, uncached message would put an island in the cache and
  /// break its contiguity.
  Future<void> updateIfCached(RecordModel r) => _db.update(
        'messages',
        {'created': r.getStringValue('created'), 'json': jsonEncode(r.toJson())},
        where: 'id = ?',
        whereArgs: [r.id],
      );

  Future<void> delete(String id) => _db.delete('messages', where: 'id = ?', whereArgs: [id]);

  /// Delete cached messages from [oldest] (inclusive) up to, but not
  /// including, [newest]'s millisecond that aren't in [keep]: they were
  /// deleted on the server. The newest millisecond is skipped on purpose: a
  /// message created right after the fetch in that same ms would otherwise
  /// look deleted. Anything newer (e.g. a realtime message that arrived
  /// during the sync) is never touched.
  Future<void> deleteMissingBetween(
    String user, {
    required RecordModel oldest,
    required RecordModel newest,
    required Set<String> keep,
  }) async {
    final oc = oldest.getStringValue('created'), nc = newest.getStringValue('created');
    final rows = await _db.query(
      'messages',
      columns: ['id'],
      where: 'user = ? '
          'AND (created > ? OR (created = ? AND id >= ?)) '
          'AND created < ?',
      whereArgs: [user, oc, oc, oldest.id, nc],
    );
    final gone = rows.map((r) => r['id']! as String).where((id) => !keep.contains(id)).toList();
    if (gone.isEmpty) return;
    final batch = _db.batch();
    for (final id in gone) {
      batch.delete('messages', where: 'id = ?', whereArgs: [id]);
    }
    await batch.commit(noResult: true);
  }

  /// Delete this user's messages that aren't in [keep], except those created
  /// at or after [keepFrom] (same reason as [deleteMissingBetween]).
  Future<void> deleteAllExcept(String user, Set<String> keep, {String? keepFrom}) async {
    final rows = await _db.query(
      'messages',
      columns: ['id'],
      where: keepFrom == null ? 'user = ?' : 'user = ? AND created < ?',
      whereArgs: keepFrom == null ? [user] : [user, keepFrom],
    );
    final batch = _db.batch();
    for (final r in rows) {
      final id = r['id']! as String;
      if (!keep.contains(id)) batch.delete('messages', where: 'id = ?', whereArgs: [id]);
    }
    await batch.commit(noResult: true);
  }

  /// Enforce [kMessageCacheLimit] (null = unlimited) by dropping the oldest.
  /// The slice stays contiguous; it just no longer reaches the start.
  Future<void> prune(String user) async {
    const limit = kMessageCacheLimit;
    if (limit == null) return;
    final removed = await _db.rawDelete('''
      DELETE FROM messages WHERE user = ? AND id NOT IN (
        SELECT id FROM messages WHERE user = ? ORDER BY $_order LIMIT ?
      )''', [user, user, limit]);
    if (removed > 0) await setReachedStart(user, false);
  }

  // ---------------------------------------------------------------------------
  // Sync bookkeeping
  // ---------------------------------------------------------------------------

  Future<String?> _getMeta(String key) async {
    final rows = await _db.query('meta', where: 'key = ?', whereArgs: [key]);
    return rows.isEmpty ? null : rows.first['value'] as String?;
  }

  Future<void> _setMeta(String key, String? value) => _db.insert(
        'meta',
        {'key': key, 'value': value},
        conflictAlgorithm: ConflictAlgorithm.replace,
      );

  /// `created` of the newest message as of the last successful sync. The next
  /// sync makes sure everything from here up is cached (fills gaps).
  Future<String?> watermark(String user) => _getMeta('watermark:$user');
  Future<void> setWatermark(String user, String created) => _setMeta('watermark:$user', created);

  /// True once the oldest message on the server is in the cache.
  Future<bool> reachedStart(String user) async => await _getMeta('reachedStart:$user') == '1';
  Future<void> setReachedStart(String user, bool v) => _setMeta('reachedStart:$user', v ? '1' : '0');

  // ---------------------------------------------------------------------------
  // File metadata (size/type from HEAD requests)
  // ---------------------------------------------------------------------------

  Future<(int?, String?)?> fileMeta(String key) async {
    final rows = await _db.query('file_meta', where: 'key = ?', whereArgs: [key]);
    if (rows.isEmpty) return null;
    return (rows.first['size'] as int?, rows.first['type'] as String?);
  }

  Future<void> putFileMeta(String key, int? size, String? type) => _db.insert(
        'file_meta',
        {'key': key, 'size': size, 'type': type},
        conflictAlgorithm: ConflictAlgorithm.replace,
      );

  // ---------------------------------------------------------------------------

  /// Wipe everything (on logout).
  Future<void> clear() async {
    await _db.delete('messages');
    await _db.delete('meta');
    await _db.delete('file_meta');
  }
}
