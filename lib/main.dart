import 'package:flutter/material.dart';
import 'package:pocketbase/pocketbase.dart';

import 'config.dart';
import 'pb.dart';
import 'screens/chat_screen.dart';
import 'screens/login_screen.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  await initPocketBase();

  // Refresh a stored session in the background so the token's lifetime is
  // extended. If the token is expired/revoked, the SDK clears the auth store
  // on the 401 and the app falls back to the login screen.
  if (pb.authStore.isValid) {
    pb.collection(kUsersCollection).authRefresh().then((_) {}, onError: (_) {});
  }

  runApp(const FtChatApp());
}

class FtChatApp extends StatelessWidget {
  const FtChatApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'ft-chat',
      debugShowCheckedModeBanner: false,
      home: StreamBuilder<AuthStoreEvent>(
        stream: pb.authStore.onChange,
        builder: (context, _) {
          return pb.authStore.isValid
              ? const ChatScreen()
              : const LoginScreen();
        },
      ),
    );
  }
}
