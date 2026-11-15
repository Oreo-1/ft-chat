import 'package:flutter/material.dart';
import 'package:pocketbase/pocketbase.dart';

import 'config.dart';
import 'pb.dart';
import 'screens/chat_screen.dart';
import 'screens/login_screen.dart';
import 'theme.dart';

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
      theme: buildDarkTheme(),
      darkTheme: buildDarkTheme(),
      themeMode: ThemeMode.dark,
      home: StreamBuilder<AuthStoreEvent>(
        stream: pb.authStore.onChange,
        builder: (context, _) {
          final loggedIn = pb.authStore.isValid;
          // Login <-> chat swap: fade + slight upward slide. Keys make the
          // switcher animate only when the screen actually changes (not on
          // token refreshes).
          return AnimatedSwitcher(
            duration: kAnimMedium,
            switchInCurve: Curves.easeOutCubic,
            switchOutCurve: Curves.easeInCubic,
            transitionBuilder: (child, animation) => FadeTransition(
              opacity: animation,
              child: SlideTransition(
                position: Tween(begin: const Offset(0, 0.03), end: Offset.zero)
                    .animate(animation),
                child: child,
              ),
            ),
            child: loggedIn
                ? const ChatScreen(key: ValueKey('chat'))
                : const LoginScreen(key: ValueKey('login')),
          );
        },
      ),
    );
  }
}
