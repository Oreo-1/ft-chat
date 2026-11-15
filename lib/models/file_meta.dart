import 'package:http/http.dart' as http;

import '../cache/message_cache.dart';

/// Size / type of a stored file. PocketBase only keeps filenames on the
/// record, so this is read once with a HEAD request on the file URL and then
/// kept in memory and in the local cache DB (so it shows offline too).
class FileMeta {
  const FileMeta({this.size, this.contentType});

  final int? size;
  final String? contentType;
}

final Map<String, Future<FileMeta>> _memory = {};

/// [key] identifies the file (record id + filename), [url] is where to HEAD it.
Future<FileMeta> fetchFileMeta(String key, Uri url) {
  return _memory[key] ??= _load(key, url);
}

Future<FileMeta> _load(String key, Uri url) async {
  final stored = await MessageCache.instance.fileMeta(key);
  if (stored != null) return FileMeta(size: stored.$1, contentType: stored.$2);

  try {
    final res = await http.head(url).timeout(const Duration(seconds: 10));
    if (res.statusCode != 200) throw StateError('HEAD ${res.statusCode}');
    final meta = FileMeta(
      size: int.tryParse(res.headers['content-length'] ?? ''),
      contentType: res.headers['content-type']?.split(';').first.trim(),
    );
    await MessageCache.instance.putFileMeta(key, meta.size, meta.contentType);
    return meta;
  } catch (_) {
    _memory.remove(key); // offline / failed: allow a retry on next build
    return const FileMeta();
  }
}

String formatBytes(int bytes) {
  if (bytes < 1024) return '$bytes B';
  if (bytes < 1024 * 1024) return '${(bytes / 1024).toStringAsFixed(1)} KB';
  if (bytes < 1024 * 1024 * 1024) return '${(bytes / (1024 * 1024)).toStringAsFixed(1)} MB';
  return '${(bytes / (1024 * 1024 * 1024)).toStringAsFixed(1)} GB';
}
