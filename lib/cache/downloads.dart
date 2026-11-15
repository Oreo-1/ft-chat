import 'dart:async';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;
import 'package:open_filex/open_filex.dart';
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';

import '../models/message.dart';
import 'media_cache.dart';

/// State of one file's in-app download.
sealed class DownloadState {
  const DownloadState();
}

class DownloadIdle extends DownloadState {
  const DownloadIdle();
}

class DownloadRunning extends DownloadState {
  const DownloadRunning(this.received, this.total);
  final int received;
  final int? total; // null when the server doesn't send Content-Length

  double? get progress => total == null || total == 0 ? null : received / total!;
}

class DownloadDone extends DownloadState {
  const DownloadDone(this.path);
  final String path;
}

class DownloadFailed extends DownloadState {
  const DownloadFailed(this.error);
  final Object error;
}

class _Cancelled implements Exception {}

/// Downloads message files into the app's cache folder
/// (`<cache>/ft_downloads/<recordId>/<name>`) and opens them with whatever app
/// handles the type (via open_filex). Downloads keep going if the popup is
/// closed; widgets listen to [state] for progress.
///
/// Like the media cache, there's no size limit, and Android "Clear cache" or
/// low storage can remove the files. They're also deleted on logout.
class Downloads {
  Downloads._();
  static final Downloads instance = Downloads._();

  final Map<String, ValueNotifier<DownloadState>> _states = {};
  final Map<String, void Function()> _cancels = {};

  Future<Directory> _root() async =>
      Directory(p.join((await getTemporaryDirectory()).path, 'ft_downloads'));

  Future<String> _pathFor(Message m, String filename) async =>
      p.join((await _root()).path, m.id, displayFileName(filename));

  /// Listenable state for this file. The first call checks whether it was
  /// already downloaded earlier.
  ValueNotifier<DownloadState> state(Message m, String filename) {
    final key = mediaCacheKey(m.id, filename);
    return _states.putIfAbsent(key, () {
      final n = ValueNotifier<DownloadState>(const DownloadIdle());
      _pathFor(m, filename).then((path) async {
        if (n.value is DownloadIdle && await File(path).exists()) n.value = DownloadDone(path);
      });
      return n;
    });
  }

  /// Start downloading (no-op if it's already running or done).
  Future<void> start(Message m, String filename) async {
    final key = mediaCacheKey(m.id, filename);
    final n = state(m, filename);
    if (n.value is DownloadRunning || n.value is DownloadDone) return;
    n.value = const DownloadRunning(0, null);

    final path = await _pathFor(m, filename);
    final part = File('$path.part');
    final client = http.Client();
    IOSink? sink;
    try {
      await part.parent.create(recursive: true);
      final res = await client.send(http.Request('GET', m.fileUrl(filename)));
      if (res.statusCode != 200) throw HttpException('HTTP ${res.statusCode}');
      final total = res.contentLength;
      sink = part.openWrite();

      var received = 0;
      var lastEmit = DateTime.now();
      final finished = Completer<void>();
      final sub = res.stream.listen(
        (chunk) {
          sink!.add(chunk);
          received += chunk.length;
          // Throttle UI updates to ~10/s.
          final now = DateTime.now();
          if (now.difference(lastEmit) > const Duration(milliseconds: 100)) {
            lastEmit = now;
            n.value = DownloadRunning(received, total);
          }
        },
        onDone: () => finished.isCompleted ? null : finished.complete(),
        onError: (Object e) => finished.isCompleted ? null : finished.completeError(e),
        cancelOnError: true,
      );
      _cancels[key] = () {
        sub.cancel();
        if (!finished.isCompleted) finished.completeError(_Cancelled());
      };

      await finished.future;
      await sink.close();
      sink = null;
      await part.rename(path);
      n.value = DownloadDone(path);
    } on _Cancelled {
      n.value = const DownloadIdle();
    } catch (e) {
      n.value = DownloadFailed(e);
    } finally {
      _cancels.remove(key);
      client.close();
      await sink?.close();
      if (await part.exists()) await part.delete();
    }
  }

  void cancel(Message m, String filename) => _cancels[mediaCacheKey(m.id, filename)]?.call();

  /// Open a downloaded file with the system's handler for its type.
  /// Returns null on success, or a message to show.
  Future<String?> open(String path) async {
    final r = await OpenFilex.open(path);
    return switch (r.type) {
      ResultType.done => null,
      ResultType.noAppToOpen => 'No app on this device can open this file type.',
      ResultType.fileNotFound => 'The downloaded file is gone. Download it again.',
      ResultType.permissionDenied => 'Permission denied: ${r.message}',
      ResultType.error => 'Could not open the file: ${r.message}',
    };
  }

  /// Delete this file's local copy.
  Future<void> remove(Message m, String filename) async {
    final file = File(await _pathFor(m, filename));
    if (await file.exists()) await file.delete();
    state(m, filename).value = const DownloadIdle();
  }

  /// Delete every download (on logout).
  Future<void> clearAll() async {
    for (final cancel in List.of(_cancels.values)) {
      cancel();
    }
    final root = await _root();
    if (await root.exists()) await root.delete(recursive: true);
    for (final n in _states.values) {
      n.value = const DownloadIdle();
    }
  }
}
