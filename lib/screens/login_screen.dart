import 'package:flutter/material.dart';
import 'package:pocketbase/pocketbase.dart';

import '../config.dart';
import '../pb.dart';

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
    return Scaffold(
      appBar: AppBar(title: const Text('ft-chat')),
      body: Center(
        child: SingleChildScrollView(
          padding: const EdgeInsets.all(24),
          child: AutofillGroup(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                TextField(
                  controller: _username,
                  decoration: const InputDecoration(labelText: 'Username'),
                  autofillHints: const [AutofillHints.username],
                  autocorrect: false,
                  textInputAction: TextInputAction.next,
                ),
                const SizedBox(height: 12),
                TextField(
                  controller: _password,
                  decoration: const InputDecoration(labelText: 'Password'),
                  autofillHints: const [AutofillHints.password],
                  obscureText: true,
                  onSubmitted: (_) => _login(),
                ),
                const SizedBox(height: 24),
                if (_error != null) ...[
                  Text(_error!, style: const TextStyle(color: Colors.red)),
                  const SizedBox(height: 12),
                ],
                FilledButton(
                  onPressed: _busy ? null : _login,
                  child: _busy
                      ? const SizedBox(
                          width: 18, height: 18, child: CircularProgressIndicator(strokeWidth: 2))
                      : const Text('Log in'),
                ),
                const SizedBox(height: 24),
                Text(kPocketBaseUrl, style: Theme.of(context).textTheme.bodySmall),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
