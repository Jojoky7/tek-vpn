import 'package:flutter/material.dart';

import 'app_scope.dart';
import 'strings.dart';

/// Sign in to tekvpn.com with email and password; the subscription of the
/// account is added by itself.
class LoginScreen extends StatefulWidget {
  const LoginScreen({super.key});

  @override
  State<LoginScreen> createState() => _LoginScreenState();
}

class _LoginScreenState extends State<LoginScreen> {
  final _email = TextEditingController();
  final _password = TextEditingController();
  bool _register = false;
  bool _hide = true;

  @override
  void dispose() {
    _email.dispose();
    _password.dispose();
    super.dispose();
  }

  Future<void> _submit() async {
    final app = AppScope.read(context);
    final ok = await app.signIn(_email.text, _password.text, register: _register);
    if (!mounted) return;
    if (ok) {
      Navigator.of(context).popUntil((r) => r.isFirst);
      return;
    }
    final e = app.error;
    if (e != null) {
      app.clearError();
      if (e.key == 'emailTaken') setState(() => _register = false);
      final detail = e.key == 'signInFailed' && (e.detail?.isNotEmpty ?? false) ? e.detail! : null;
      ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text(detail ?? S.current.error(e.key))));
    }
  }

  @override
  Widget build(BuildContext context) {
    final app = AppScope.of(context);
    final s = S.current;
    final busy = app.refreshing;
    return Scaffold(
      appBar: AppBar(title: Text(_register ? s.register : s.signIn)),
      body: SafeArea(
        child: Center(
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 480),
            child: AutofillGroup(
              child: ListView(
                padding: const EdgeInsets.all(20),
                children: [
                  const SizedBox(height: 8),
                  Text('tekvpn.com',
                      style: TextStyle(color: Theme.of(context).colorScheme.onSurfaceVariant)),
                  const SizedBox(height: 16),
                  TextField(
                    controller: _email,
                    enabled: !busy,
                    keyboardType: TextInputType.emailAddress,
                    autocorrect: false,
                    autofillHints: const [AutofillHints.email],
                    textInputAction: TextInputAction.next,
                    decoration: InputDecoration(
                      labelText: s.email,
                      hintText: _register ? 'name@gmail.com' : null,
                    ),
                  ),
                  const SizedBox(height: 12),
                  TextField(
                    controller: _password,
                    enabled: !busy,
                    obscureText: _hide,
                    autocorrect: false,
                    enableSuggestions: false,
                    autofillHints: [
                      _register ? AutofillHints.newPassword : AutofillHints.password
                    ],
                    textInputAction: TextInputAction.done,
                    onSubmitted: (_) => _submit(),
                    decoration: InputDecoration(
                      labelText: s.password,
                      suffixIcon: IconButton(
                        icon: Icon(_hide ? Icons.visibility_rounded : Icons.visibility_off_rounded),
                        onPressed: () => setState(() => _hide = !_hide),
                      ),
                    ),
                  ),
                  const SizedBox(height: 20),
                  FilledButton(
                    onPressed: busy ? null : _submit,
                    child: busy
                        ? const SizedBox(
                            width: 22,
                            height: 22,
                            child: CircularProgressIndicator(strokeWidth: 2.5, color: Colors.white))
                        : Text(_register ? s.register : s.signIn),
                  ),
                  const SizedBox(height: 8),
                  TextButton(
                    onPressed: busy ? null : () => setState(() => _register = !_register),
                    child: Text(_register ? s.haveAccount : s.noAccount),
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
