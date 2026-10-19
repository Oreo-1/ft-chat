import 'dart:async';

import 'package:flutter/material.dart';

import 'backend.dart';
import 'chat_page.dart';
import 'login_page.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  final backend = await Backend.init();
  runApp(FtChat(backend: backend));
  unawaited(backend.refreshAuth()); // don't block startup (may be offline)
}

class FtChat extends StatelessWidget {
  const FtChat({super.key, required this.backend});
  final Backend backend;

  ThemeData _theme(Brightness b) => ThemeData(
        useMaterial3: true,
        colorScheme: ColorScheme.fromSeed(seedColor: Colors.teal, brightness: b),
      );

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      debugShowCheckedModeBanner: false,
      theme: _theme(Brightness.light),
      darkTheme: _theme(Brightness.dark),
      themeMode: ThemeMode.system,
      home: ListenableBuilder(
        listenable: backend,
        builder: (context, _) => backend.isLoggedIn
            ? ChatPage(key: ValueKey(backend.serverUrl), backend: backend)
            : LoginPage(backend: backend),
      ),
    );
  }
}
