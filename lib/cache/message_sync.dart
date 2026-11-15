import 'package:pocketbase/pocketbase.dart';

import '../config.dart';
import '../pb.dart';
import 'message_cache.dart';

/// Moves messages from PocketBase into [MessageCache]. The chat screen reads
/// the cache; this keeps it correct.
class MessageSync {
  MessageSync(this.user);

  final String user;

  MessageCache get _cache => MessageCache.instance;
  RecordService get _col => pb.collection(kMessagesCollection);

  /// Biggest page PocketBase allows.
  static const _maxPerPage = 500;

  /// Bring the newest [window] messages up to date (new, edited, deleted
  /// elsewhere) and fill any gap since the last sync. Throws on network errors;
  /// the cache is left consistent either way.
  Future<void> syncLatest(int window) async {
    final want = window.clamp(kPageSize, _maxPerPage);
    final res = await _col.getList(page: 1, perPage: want, sort: '-created,-id', skipTotal: true);
    final fresh = res.items;
    final ids = {for (final r in fresh) r.id};
    final newestCreated = fresh.isEmpty ? null : fresh.first.getStringValue('created');
    final wm = await _cache.watermark(user);

    if (fresh.length < want) {
      // That's the server's entire history.
      await _cache.upsertAll(fresh);
      await _cache.deleteAllExcept(user, ids, keepFrom: newestCreated);
      await _cache.setReachedStart(user, true);
    } else {
      final boundary = fresh.last.getStringValue('created');

      if (wm == null) {
        // Never synced (fresh install / after logout): anything cached
        // would be of unknown continuity, so start from this page.
        await _cache.deleteAllExcept(user, ids, keepFrom: newestCreated);
        await _cache.setReachedStart(user, false);
      } else if (boundary.compareTo(wm) >= 0) {
        // More arrived since the last sync than this page covers: fill the
        // gap [watermark .. boundary] so the cache stays contiguous.
        // (>= rather than >: messages in the watermark's own millisecond may
        // sit just below this page and still be missing.)
        await _fillForward(from: wm, upTo: boundary);
      }

      await _cache.upsertAll(fresh);
      // Within the fetched range, anything cached but not returned was
      // deleted on the server. (Newer-than-fresh items, e.g. a realtime
      // message that just arrived, are left alone.)
      await _cache.deleteMissingBetween(user, oldest: fresh.last, newest: fresh.first, keep: ids);
    }

    if (newestCreated != null) await _cache.setWatermark(user, newestCreated);
  }

  /// Apply kMessageCacheLimit. Only call this when just the newest page is on
  /// screen (app start): pruning while scrolled far back would drop rows the
  /// list still shows and break the cache's contiguity.
  Future<void> prune() => _cache.prune(user);

  /// Fetch everything with from <= created <= upTo, oldest first, using a
  /// cursor so new arrivals can't shift pages.
  Future<void> _fillForward({required String from, required String upTo}) async {
    String? lastCreated;
    String? lastId;
    while (true) {
      final cursor = lastCreated == null
          ? pb.filter('created >= {:from} && created <= {:to}', {'from': from, 'to': upTo})
          : pb.filter(
              'created <= {:to} && (created > {:c} || (created = {:c} && id > {:id}))',
              {'to': upTo, 'c': lastCreated, 'id': lastId},
            );
      final res = await _col.getList(
        page: 1,
        perPage: _maxPerPage,
        sort: 'created,id',
        skipTotal: true,
        filter: cursor,
      );
      await _cache.upsertAll(res.items);
      if (res.items.length < _maxPerPage) return;
      lastCreated = res.items.last.getStringValue('created');
      lastId = res.items.last.id;
    }
  }

  /// Up to [limit] messages older than [oldest], from the cache, topped up
  /// from the server when the cache runs out. Returns the rows and whether
  /// there may be more. If the server can't be reached it returns what the
  /// cache had plus the error.
  Future<({List<RecordModel> rows, bool hasMore, Object? error})> older(
    RecordModel oldest,
    int limit,
  ) async {
    final c = oldest.getStringValue('created');
    var rows = await _cache.olderThan(user, c, oldest.id, limit);
    Object? error;

    if (rows.length < limit && !await _cache.reachedStart(user)) {
      // Continue from the oldest cached message. The cache is contiguous and
      // covers everything on screen, so that's rows.last, or [oldest] itself
      // when the cache has nothing older.
      final from = rows.isNotEmpty ? rows.last : oldest;
      final fc = from.getStringValue('created');
      try {
        final res = await _col.getList(
          page: 1,
          perPage: kPageSize,
          sort: '-created,-id',
          skipTotal: true,
          filter: pb.filter(
            'created < {:c} || (created = {:c} && id < {:id})',
            {'c': fc, 'id': from.id},
          ),
        );
        await _cache.upsertAll(res.items);
        if (res.items.length < kPageSize) await _cache.setReachedStart(user, true);
        rows = await _cache.olderThan(user, c, oldest.id, limit);
      } catch (e) {
        error = e;
      }
    }

    final hasMore = rows.length >= limit || !await _cache.reachedStart(user);
    return (rows: rows, hasMore: error != null || hasMore, error: error);
  }
}
