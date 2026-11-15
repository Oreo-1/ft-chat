import 'package:flutter_cache_manager/flutter_cache_manager.dart';

import '../config.dart';

/// Disk cache for images, thumbnails and videos. Limits come from config.dart
/// (null = unlimited). Files live in the app's cache directory, so Android
/// "Clear cache" (or the OS under low storage) can wipe them; they're simply
/// re-downloaded when needed.
final CacheManager mediaCache = CacheManager(
  Config(
    'ftMediaCache',
    maxNrOfCacheObjects: kMediaCacheMaxFiles ?? 0x7FFFFFFF,
    stalePeriod: kMediaCacheMaxAge ?? const Duration(days: 365 * 100),
  ),
);

/// Stable cache key for a record file (independent of the URL, so it keeps
/// working if you later switch to protected files with token URLs).
String mediaCacheKey(String recordId, String filename, {String? thumb}) =>
    thumb == null ? '$recordId/$filename' : '$recordId/$filename@$thumb';
