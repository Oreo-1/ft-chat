import 'package:http/http.dart' as http;

/// Size / type of a stored file. PocketBase only keeps filenames on the
/// record, so this is read from a HEAD request on the file URL and cached.
class FileMeta {
  const FileMeta({this.size, this.contentType});

  final int? size;
  final String? contentType;
}

final Map<String, Future<FileMeta>> _cache = {};

Future<FileMeta> fetchFileMeta(Uri url) {
  return _cache[url.toString()] ??= _head(url);
}

Future<FileMeta> _head(Uri url) async {
  try {
    final res = await http.head(url).timeout(const Duration(seconds: 10));
    if (res.statusCode != 200) return const FileMeta();
    return FileMeta(
      size: int.tryParse(res.headers['content-length'] ?? ''),
      contentType: res.headers['content-type']?.split(';').first.trim(),
    );
  } catch (_) {
    _cache.remove(url.toString()); // allow a retry on next build
    return const FileMeta();
  }
}

String formatBytes(int bytes) {
  if (bytes < 1024) return '$bytes B';
  if (bytes < 1024 * 1024) return '${(bytes / 1024).toStringAsFixed(1)} KB';
  if (bytes < 1024 * 1024 * 1024) return '${(bytes / (1024 * 1024)).toStringAsFixed(1)} MB';
  return '${(bytes / (1024 * 1024 * 1024)).toStringAsFixed(1)} GB';
}
