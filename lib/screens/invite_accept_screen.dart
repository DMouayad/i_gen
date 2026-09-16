import 'package:flutter/material.dart';
import 'package:i_gen/auth/auth_exceptions.dart';
import 'package:i_gen/auth/invite_service.dart';
import 'package:i_gen/utils/context_extensions.dart';

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
  // _accept() runs from initState where AppLocalizations isn't ready, so
  // localizable outcomes are stored as keys and resolved in build();
  // _rawError carries server/exception text shown as-is.
  String? _messageKey;
  String? _rawError;
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
      _messageKey = null;
      _rawError = null;
    });
    try {
      final needsPassword = await InviteService().acceptLink(widget.link);
      if (!mounted) return;
      setState(() {
        _needsPassword = needsPassword;
        _messageKey = needsPassword
            ? 'inviteLinkAcceptedChoosePassword'
            : 'inviteLinkAcceptedSignIn';
      });
    } on AuthFailureException catch (e) {
      if (!mounted) return;
      setState(() => _rawError = e.message);
    } catch (_) {
      if (!mounted) return;
      setState(() => _messageKey = 'inviteLinkAcceptFailed');
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _setPassword() async {
    setState(() {
      _busy = true;
      _messageKey = null;
      _rawError = null;
    });
    try {
      await InviteService().setPassword(_password.text);
      if (!mounted) return;
      setState(() {
        _needsPassword = false;
        _done = true;
        _messageKey = 'invitePasswordSetDone';
      });
    } on AuthFailureException catch (e) {
      if (!mounted) return;
      setState(() => _rawError = e.message);
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final String? messageText =
        _rawError ??
        switch (_messageKey) {
          'inviteLinkAcceptedChoosePassword' =>
            context.l10n.inviteLinkAcceptedChoosePassword,
          'inviteLinkAcceptedSignIn' => context.l10n.inviteLinkAcceptedSignIn,
          'inviteLinkAcceptFailed' => context.l10n.inviteLinkAcceptFailed,
          'invitePasswordSetDone' => context.l10n.invitePasswordSetDone,
          _ => null,
        };
    final bool hasMessage = messageText != null;
    final bool isError =
        _rawError != null || _messageKey == 'inviteLinkAcceptFailed';
    return Scaffold(
      appBar: AppBar(title: Text(context.l10n.acceptInvitationTitle)),
      body: Padding(
        padding: const EdgeInsets.all(AppGaps.md),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            if (_busy && !hasMessage)
              const Center(child: CircularProgressIndicator()),
            if (messageText != null)
              Row(
                children: [
                  if (isError)
                    Padding(
                      padding: const EdgeInsets.only(right: AppGaps.sm),
                      child: Icon(
                        Icons.error_outline,
                        color: context.colorScheme.error,
                      ),
                    ),
                  Expanded(
                    child: Text(
                      messageText,
                      style: isError
                          ? context.textTheme.bodyMedium?.copyWith(
                              color: context.colorScheme.error,
                            )
                          : null,
                    ),
                  ),
                ],
              ),
            if (_needsPassword && !_busy) ...[
              const SizedBox(height: AppGaps.md),
              TextField(
                controller: _password,
                obscureText: true,
                decoration: InputDecoration(
                  labelText: context.l10n.choosePasswordLabel,
                  border: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(AppRadii.control),
                  ),
                ),
                enabled: !_busy,
              ),
              const SizedBox(height: AppGaps.md),
              FilledButton.tonal(
                style: const ButtonStyle(
                  minimumSize: WidgetStatePropertyAll(Size(64, 48)),
                ),
                onPressed: _busy ? null : _setPassword,
                child: Text(context.l10n.setPasswordButton),
              ),
            ],
            if (!_busy && (_done || (hasMessage && !_needsPassword))) ...[
              const SizedBox(height: AppGaps.md),
              if (isError)
                OutlinedButton(
                  style: const ButtonStyle(
                    minimumSize: WidgetStatePropertyAll(Size(64, 48)),
                  ),
                  onPressed: _accept,
                  child: Text(context.l10n.retry),
                ),
              if (isError) const SizedBox(height: AppGaps.md),
              OutlinedButton(
                style: const ButtonStyle(
                  minimumSize: WidgetStatePropertyAll(Size(64, 48)),
                ),
                onPressed: () => Navigator.of(context).pop(),
                child: Text(context.l10n.done),
              ),
            ],
          ],
        ),
      ),
    );
  }
}
