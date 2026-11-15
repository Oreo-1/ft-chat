import 'package:flutter/material.dart';
import 'package:pocketbase/pocketbase.dart';

import '../config.dart';
import '../pb.dart';
import '../theme.dart';

class LoginScreen extends StatefulWidget {
  const LoginScreen({super.key});

  @override
  State<LoginScreen> createState() => _LoginScreenState();
}

class _LoginScreenState extends State<LoginScreen> {
  final _username = TextEditingController();
  final _password = TextEditingController();
  bool _busy = false;
  String? _error;

  @override
  void dispose() {
    _username.dispose();
    _password.dispose();
    super.dispose();
  }

  Future<void> _login() async {
    final username = _username.text.trim();
    final password = _password.text;
    if (username.isEmpty || password.isEmpty) return;

    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      await pb.collection(kUsersCollection).authWithPassword(username, password);
      // main.dart listens to authStore changes and swaps to the chat screen.
    } on ClientException catch (e) {
      setState(() => _error = e.statusCode == 400
          ? 'Invalid username or password.'
          : 'Login failed (${e.statusCode}): ${e.response['message'] ?? e.originalError}');
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return Scaffold(
      body: Center(
        child: SingleChildScrollView(
          padding: const EdgeInsets.all(24),
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 400),
            child: AutofillGroup(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Text('ft-chat', style: theme.textTheme.headlineMedium, textAlign: TextAlign.center),
                  const SizedBox(height: 32),
                  // Outlined borders come from inputDecorationTheme in theme.dart.
                  TextField(
                    controller: _username,
                    decoration: const InputDecoration(
                      labelText: 'Username',
                      prefixIcon: Icon(Icons.person_outline),
                    ),
                    autofillHints: const [AutofillHints.username],
                    autocorrect: false,
                    textInputAction: TextInputAction.next,
                  ),
                  const SizedBox(height: 12),
                  TextField(
                    controller: _password,
                    decoration: const InputDecoration(
                      labelText: 'Password',
                      prefixIcon: Icon(Icons.lock_outline),
                    ),
                    autofillHints: const [AutofillHints.password],
                    obscureText: true,
                    onSubmitted: (_) => _login(),
                  ),
                  // Error message slides open/closed.
                  AnimatedSize(
                    duration: kAnimFast,
                    curve: Curves.easeOutCubic,
                    child: _error == null
                        ? const SizedBox(height: 24, width: double.infinity)
                        : Padding(
                            padding: const EdgeInsets.symmetric(vertical: 12),
                            child: Text(_error!, style: TextStyle(color: theme.colorScheme.error)),
                          ),
                  ),
                  FilledButton(
                    onPressed: _busy ? null : _login,
                    child: AnimatedSwitcher(
                      duration: kAnimFast,
                      child: _busy
                          ? const SizedBox(
                              key: ValueKey('busy'),
                              width: 18,
                              height: 18,
                              child: CircularProgressIndicator(strokeWidth: 2))
                          : const Text('Log in', key: ValueKey('idle')),
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}
