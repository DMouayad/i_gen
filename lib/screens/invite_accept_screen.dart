import 'package:flutter/material.dart';
import 'package:i_gen/auth/auth_exceptions.dart';
import 'package:i_gen/auth/invite_service.dart';

/// Handles one invite/recovery link end to end: verifies it, collects the
/// password when the link established a fresh session, and reports the
/// outcome. Opened two ways: tapped deep links (Android intent) and the
/// paste-link button in Settings.
class InviteAcceptScreen extends StatefulWidget {
  final String link;

  const InviteAcceptScreen({super.key, required this.link});

  @override
  State<InviteAcceptScreen> createState() => _InviteAcceptScreenState();
}

class _InviteAcceptScreenState extends State<InviteAcceptScreen> {
  final _password = TextEditingController();
  bool _busy = false;
  bool _needsPassword = false;
  String? _message;
  bool _done = false;

  @override
  void initState() {
    super.initState();
    _accept();
  }

  @override
  void dispose() {
    _password.dispose();
    super.dispose();
  }

  Future<void> _accept() async {
    setState(() {
      _busy = true;
      _message = null;
    });
    try {
      final needsPassword = await InviteService().acceptLink(widget.link);
      if (!mounted) return;
      setState(() {
        _needsPassword = needsPassword;
        _message = needsPassword
            ? 'Link accepted — choose a password to finish.'
            : 'Link accepted — now sign in with your new password.';
      });
    } on AuthFailureException catch (e) {
      if (!mounted) return;
      setState(() => _message = e.message);
    } catch (_) {
      if (!mounted) return;
      setState(() => _message = 'Could not accept the link — try again.');
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _setPassword() async {
    setState(() {
      _busy = true;
      _message = null;
    });
    try {
      await InviteService().setPassword(_password.text);
      if (!mounted) return;
      setState(() {
        _needsPassword = false;
        _done = true;
        _message = 'Password set — sign in with your email and password.';
      });
    } on AuthFailureException catch (e) {
      if (!mounted) return;
      setState(() => _message = e.message);
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Accept invitation')),
      body: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            if (_busy && _message == null)
              const Center(child: CircularProgressIndicator()),
            if (_message != null) Text(_message!),
            if (_needsPassword && !_busy) ...[
              const SizedBox(height: 12),
              TextField(
                controller: _password,
                obscureText: true,
                decoration: const InputDecoration(labelText: 'Choose password'),
                enabled: !_busy,
              ),
              const SizedBox(height: 12),
              FilledButton.tonal(
                onPressed: _busy ? null : _setPassword,
                child: const Text('Set password'),
              ),
            ],
            if (!_busy && (_done || (_message != null && !_needsPassword))) ...[
              const SizedBox(height: 12),
              OutlinedButton(
                onPressed: () => Navigator.of(context).pop(),
                child: const Text('Done'),
              ),
            ],
          ],
        ),
      ),
    );
  }
}
