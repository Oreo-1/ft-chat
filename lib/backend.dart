import 'dart:async';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;
import 'package:path_provider/path_provider.dart';
import 'package:pocketbase/pocketbase.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// Turns any exception into something short you can show in a SnackBar.
String describeError(Object e) {
  if (e is ClientException) {
    if (e.statusCode == 0) return 'can’t reach the server';
    final m = e.response['message'];
    return (m is String && m.isNotEmpty) ? m : 'HTTP ${e.statusCode}';
  }
  return e.toString();
}

/// Owns the PocketBase client + persisted session.
/// Extends ChangeNotifier so the UI can swap Login <-> Chat on auth changes.
class Backend extends ChangeNotifier {
  Backend._(this._prefs, this.pb);

  static const collection = 'ftchat_messages';

  /// Written into every message so each client can tell "mine" from "theirs".
  /// Use 'desktop' in your Tauri/Electron client.
  static const deviceName = 'mobile';

  static const _kUrl = 'server_url';
  static const _kAuth = 'pb_auth';

  final SharedPreferences _prefs;
  PocketBase pb;

  static Future<Backend> init() async {
    final prefs = await SharedPreferences.getInstance();
    return Backend._(prefs, _build(prefs, prefs.getString(_kUrl) ?? ''));
  }

  static PocketBase _build(SharedPreferences prefs, String url) {
    final store = AsyncAuthStore(
      save: (String data) async => prefs.setString(_kAuth, data),
      initial: prefs.getString(_kAuth),
      clear: () async => prefs.remove(_kAuth),
    );
    return PocketBase(url.isEmpty ? 'http://localhost' : url, authStore: store);
  }

  String get serverUrl => _prefs.getString(_kUrl) ?? '';
  bool get isLoggedIn => serverUrl.isNotEmpty && pb.authStore.isValid;

  // ---------------------------------------------------------------- auth

  Future<void> login(String url, String email, String password) async {
    url = url.trim().replaceAll(RegExp(r'/+$'), '');
    if (url.isEmpty) throw 'Server URL is required';
    if (!url.startsWith('http://') && !url.startsWith('https://')) {
      url = 'https://$url';
    }
    await _prefs.remove(_kAuth); // never reuse a token from another server
    final client = _build(_prefs, url);
    await client.collection('users').authWithPassword(email.trim(), password);
    await _prefs.setString(_kUrl, url);
    pb = client;
    notifyListeners();
  }

  void logout() {
    pb.authStore.clear();
    notifyListeners();
  }

  /// Extends the session on app start. Only logs out if the server explicitly
  /// rejects the token; being offline keeps the cached session.
  Future<void> refreshAuth() async {
    if (!isLoggedIn) return;
    try {
      await pb.collection('users').authRefresh();
    } on ClientException catch (e) {
      if (e.statusCode == 401 || e.statusCode == 403 || e.statusCode == 404) {
        logout();
      }
    } catch (_) {}
  }

  // --------------------------------------------------------------- files

  /// PocketBase appends "_<10 random chars>" to stored file names
  /// ("photo.jpg" -> "photo_a8Kd02xPq1.jpg"). Strip it for display.
  static String displayName(String stored) {
    final m = RegExp(r'^(.+)_[A-Za-z0-9]{10}(\.[^.]+)?$').firstMatch(stored);
    return m == null ? stored : '${m.group(1)}${m.group(2) ?? ''}';
  }

  Uri fileUrl(RecordModel r, String name, {String? token, String? thumb}) =>
      pb.files.getURL(r, name, token: token, thumb: thumb);

  /// Downloads a (protected) file into the cache dir and returns it.
  /// Already-downloaded files are reused.
  Future<File> downloadFile(
    RecordModel r,
    String storedName, {
    void Function(double progress)? onProgress,
  }) async {
    final dir = await getTemporaryDirectory();
    final folder = Directory('${dir.path}/downloads/${r.id}');
    await folder.create(recursive: true);
    final target = File('${folder.path}/${displayName(storedName)}');
    if (await target.exists()) return target;

    final token = await pb.files.getToken();
    final url = fileUrl(r, storedName, token: token);

    final part = File('${target.path}.part');
    final client = http.Client();
    try {
      final res = await client.send(http.Request('GET', url));
      if (res.statusCode != 200) throw 'HTTP ${res.statusCode}';
      final total = res.contentLength ?? 0;
      var received = 0;
      final sink = part.openWrite();
      try {
        await for (final chunk in res.stream) {
          sink.add(chunk);
          received += chunk.length;
          if (total > 0) onProgress?.call(received / total);
        }
      } finally {
        await sink.close();
      }
      return await part.rename(target.path);
    } catch (_) {
      if (await part.exists()) await part.delete();
      rethrow;
    } finally {
      client.close();
    }
  }
}
