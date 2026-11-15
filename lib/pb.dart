import 'package:pocketbase/pocketbase.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'config.dart';

/// Single PocketBase client for the whole app. Initialised in main().
late final PocketBase pb;

const _authKey = 'pb_auth';

Future<void> initPocketBase() async {
  final prefs = await SharedPreferences.getInstance();

  // Persists the auth token + user record across app restarts.
  final store = AsyncAuthStore(
    save: (data) async => prefs.setString(_authKey, data),
    initial: prefs.getString(_authKey),
    clear: () async => prefs.remove(_authKey),
  );

  pb = PocketBase(kPocketBaseUrl, authStore: store);
}
