import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import 'app_scope.dart';
import 'login_screen.dart';
import 'qr_screen.dart';
import 'strings.dart';

class AddSubscriptionScreen extends StatefulWidget {
  const AddSubscriptionScreen({super.key, this.initial});

  /// A link that came from an "open in app" button.
  final String? initial;

  @override
  State<AddSubscriptionScreen> createState() => _AddSubscriptionScreenState();
}

class _AddSubscriptionScreenState extends State<AddSubscriptionScreen> {
  late final _controller = TextEditingController(text: widget.initial ?? '');

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  Future<void> _paste() async {
    final data = await Clipboard.getData(Clipboard.kTextPlain);
    final text = data?.text?.trim();
    if (text == null || text.isEmpty) return;
    _controller.text = text;
    await _submit();
  }

  Future<void> _scan() async {
    final code = await Navigator.of(context)
        .push<String>(MaterialPageRoute(builder: (_) => const QrScreen()));
    if (code == null || !mounted) return;
    _controller.text = code;
    await _submit();
  }

  Future<void> _submit() async {
    final app = AppScope.read(context);
    final ok = await app.addSubscription(_controller.text);
    if (!mounted) return;
    if (ok) {
      Navigator.of(context).popUntil((r) => r.isFirst);
    } else if (app.error != null) {
      final key = app.error!.key;
      app.clearError();
      ScaffoldMessenger.of(context)
          .showSnackBar(SnackBar(content: Text(S.current.error(key))));
    }
  }

  @override
  Widget build(BuildContext context) {
    final app = AppScope.of(context);
    final s = S.current;
    final theme = Theme.of(context);
    final busy = app.refreshing;
    final canScan = Platform.isAndroid || Platform.isIOS;
    return Scaffold(
      appBar: AppBar(title: Text(s.addSubscription)),
      body: SafeArea(
        child: Center(
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 480),
            child: ListView(
              padding: const EdgeInsets.all(20),
              children: [
                Text(s.addHint,
                    style: TextStyle(color: theme.colorScheme.onSurfaceVariant, height: 1.4)),
                const SizedBox(height: 20),
                TextField(
                  controller: _controller,
                  enabled: !busy,
                  autocorrect: false,
                  keyboardType: TextInputType.url,
                  textInputAction: TextInputAction.done,
                  onSubmitted: (_) => _submit(),
                  decoration: InputDecoration(
                    hintText: 'https://tekvpn.com/sub/…',
                    labelText: s.subscriptionLink,
                    suffixIcon: IconButton(
                      tooltip: s.paste,
                      icon: const Icon(Icons.content_paste_rounded),
                      onPressed: busy ? null : _paste,
                    ),
                  ),
                ),
                const SizedBox(height: 12),
                FilledButton(
                  onPressed: busy ? null : _submit,
                  child: busy
                      ? const SizedBox(
                          width: 22,
                          height: 22,
                          child: CircularProgressIndicator(strokeWidth: 2.5, color: Colors.white))
                      : Text(s.add),
                ),
                const SizedBox(height: 24),
                Row(children: [
                  const Expanded(child: Divider()),
                  Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 12),
                    child: Text(s.or, style: TextStyle(color: theme.colorScheme.onSurfaceVariant)),
                  ),
                  const Expanded(child: Divider()),
                ]),
                const SizedBox(height: 24),
                if (canScan) ...[
                  OutlinedButton.icon(
                    icon: const Icon(Icons.qr_code_scanner_rounded),
                    label: Text(s.scanQr),
                    onPressed: busy ? null : _scan,
                  ),
                  const SizedBox(height: 12),
                ],
                OutlinedButton.icon(
                  icon: const Icon(Icons.alternate_email_rounded),
                  label: Text(s.signInWithEmail),
                  onPressed: busy
                      ? null
                      : () => Navigator.of(context).push(
                          MaterialPageRoute<void>(builder: (_) => const LoginScreen())),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
