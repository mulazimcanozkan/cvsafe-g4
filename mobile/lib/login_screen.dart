import 'package:flutter/material.dart';

import 'api.dart';
import 'theme.dart';
import 'widgets.dart';

/// Shared login screen for the mobile app and the web panel.
class LoginScreen extends StatefulWidget {
  const LoginScreen({super.key, this.subtitle = 'Field Safety App', this.wide = false});
  final String subtitle;
  final bool wide;

  @override
  State<LoginScreen> createState() => _LoginScreenState();
}

class _LoginScreenState extends State<LoginScreen> {
  final _url = TextEditingController();
  final _user = TextEditingController();
  final _pass = TextEditingController();
  bool _busy = false;
  bool _hide = true;
  String? _error;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (_url.text.isEmpty) _url.text = AppScope.read(context).serverUrl;
  }

  @override
  void dispose() {
    _url.dispose();
    _user.dispose();
    _pass.dispose();
    super.dispose();
  }

  Future<void> _submit() async {
    if (_user.text.trim().isEmpty || _pass.text.isEmpty) {
      setState(() => _error = 'Enter your username and password.');
      return;
    }
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      await AppScope.read(context).login(_url.text, _user.text, _pass.text);
    } on ApiException catch (e) {
      if (mounted) setState(() => _error = e.message);
    } catch (e) {
      if (mounted) {
        setState(() => _error = 'Could not reach the server at ${_url.text.trim()}. '
            'Check that it is running and the address is correct.');
      }
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  InputDecoration _dec(String label, IconData icon, {Widget? suffix}) => InputDecoration(
        labelText: label,
        labelStyle: sans(size: 13, color: C.muted),
        prefixIcon: Icon(icon, color: C.muted, size: 20),
        suffixIcon: suffix,
        filled: true,
        fillColor: C.panel2,
        border: OutlineInputBorder(borderRadius: BorderRadius.circular(10), borderSide: BorderSide.none),
      );

  @override
  Widget build(BuildContext context) {
    final st = AppScope.of(context);
    return Scaffold(
      body: SafeArea(
        child: Center(
          child: SingleChildScrollView(
            padding: const EdgeInsets.all(20),
            child: ConstrainedBox(
              constraints: BoxConstraints(maxWidth: widget.wide ? 440 : 400),
              child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
                Center(
                  child: Container(
                    width: 64,
                    height: 64,
                    decoration: BoxDecoration(shape: BoxShape.circle, border: Border.all(color: C.orange, width: 2.5)),
                    child: const Icon(Icons.shield_outlined, color: C.orange, size: 34),
                  ),
                ),
                const SizedBox(height: 14),
                Text('CVSAFE', textAlign: TextAlign.center, style: mono(size: 26, weight: FontWeight.w800, color: C.orange)),
                Text(widget.subtitle, textAlign: TextAlign.center, style: sans(size: 14, color: C.muted)),
                const SizedBox(height: 26),
                Panel(
                  padding: const EdgeInsets.all(18),
                  child: AutofillGroup(
                    child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
                      Text('Sign in', style: sans(size: 18, weight: FontWeight.w700)),
                      const SizedBox(height: 14),
                      TextField(
                        controller: _url,
                        keyboardType: TextInputType.url,
                        style: mono(size: 13.5),
                        decoration: _dec('Server address', Icons.dns_outlined),
                      ),
                      const SizedBox(height: 10),
                      TextField(
                        controller: _user,
                        autofillHints: const [AutofillHints.username],
                        style: sans(size: 14),
                        decoration: _dec('Username', Icons.person_outline),
                        textInputAction: TextInputAction.next,
                      ),
                      const SizedBox(height: 10),
                      TextField(
                        controller: _pass,
                        obscureText: _hide,
                        autofillHints: const [AutofillHints.password],
                        style: sans(size: 14),
                        onSubmitted: (_) => _busy ? null : _submit(),
                        decoration: _dec('Password', Icons.lock_outline,
                            suffix: IconButton(
                              icon: Icon(_hide ? Icons.visibility_outlined : Icons.visibility_off_outlined, color: C.muted),
                              onPressed: () => setState(() => _hide = !_hide),
                            )),
                      ),
                      if (_error != null) ...[
                        const SizedBox(height: 12),
                        Text(_error!, style: sans(size: 12.5, color: C.pink)),
                      ],
                      const SizedBox(height: 16),
                      BigButton(label: 'Sign In', icon: Icons.login, busy: _busy, onPressed: _submit),
                    ]),
                  ),
                ),
                const SizedBox(height: 14),
                Text(
                  st.online
                      ? 'Server reachable · ask your administrator for an account.'
                      : 'Server not reachable yet. Start the CVSAFE server and check the address.',
                  textAlign: TextAlign.center,
                  style: sans(size: 12, color: st.online ? C.green : C.yellow),
                ),
                const SizedBox(height: 6),
                Text('First run: admin / cvsafe123 (change it after signing in)',
                    textAlign: TextAlign.center, style: mono(size: 10.5, color: C.dim)),
              ]),
            ),
          ),
        ),
      ),
    );
  }
}
