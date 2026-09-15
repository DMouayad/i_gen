import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:i_gen/auth/auth_exceptions.dart';
import 'package:i_gen/auth/auth_service.dart';
import 'package:i_gen/auth/invite_service.dart';
import 'package:i_gen/screens/invite_accept_screen.dart';
import 'package:i_gen/sync/sync_bootstrap.dart';
import 'package:i_gen/widgets/sync_status_card.dart';

/// Settings: sign-in state + admin invite surface + sync status.
///
/// Login is optional and never blocks offline use; sign-up is invite-only so
/// there is no "create account" path here — new users arrive via an admin
/// WhatsApp link and accept it below. The sync card appears only after the
/// staging gate passes ([kSyncStagingGatePassed]).
class SettingsScreen extends StatelessWidget {
  const SettingsScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Settings')),
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(16),
        child: Column(
          children: [
            const _AuthCard(),
            const SizedBox(height: 8),
            const _InviteCard(),
            const SizedBox(height: 8),
            if (kSyncStagingGatePassed) ...[
              const SyncStatusCard(),
              const SizedBox(height: 8),
              const Text(
                'Your edits are saved on this device first and sync when '
                'you are online and signed in.',
              ),
            ] else
              const Text(
                'Your edits are saved on this device. '
                'Sync activates after the staging checklist passes.',
              ),
          ],
        ),
      ),
    );
  }
}

class _AuthCard extends StatefulWidget {
  const _AuthCard();

  @override
  State<_AuthCard> createState() => _AuthCardState();
}

class _AuthCardState extends State<_AuthCard> {
  final _email = TextEditingController();
  final _password = TextEditingController();
  final _inviteLink = TextEditingController();
  bool _busy = false;
  String? _error;

  @override
  void dispose() {
    _email.dispose();
    _password.dispose();
    _inviteLink.dispose();
    super.dispose();
  }

  AuthService get _auth => AuthService.instance;

  Future<void> _run(Future<void> Function() call) async {
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      await call();
    } on AuthOfflineException catch (e) {
      setState(() => _error = e.message);
    } on AuthNotConfiguredException catch (e) {
      setState(() => _error = e.message);
    } on AuthFailureException catch (e) {
      setState(() => _error = e.message);
    } catch (e) {
      setState(() => _error = 'Unexpected error: $e');
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    if (!_auth.isConfigured) {
      return const Card(
        child: ListTile(
          leading: Icon(Icons.cloud_off),
          title: Text('Sync not configured'),
          subtitle: Text(
            'The app works fully offline. '
            'Add Supabase credentials to enable sign-in.',
          ),
        ),
      );
    }
    return StreamBuilder(
      stream: _auth.currentUserStream,
      initialData: _auth.currentUser,
      builder: (context, snapshot) {
        final user = snapshot.data ?? _auth.currentUser;
        if (user != null) {
          final role = _auth.currentRole;
          return Card(
            child: ListTile(
              leading: const Icon(Icons.account_circle),
              title: Text(user.email ?? 'Signed in'),
              subtitle: Text(
                role == null
                    ? 'Your edits sync to this account.'
                    : 'Your edits sync to this account. Role: ${role.name}.',
              ),
              trailing: _busy
                  ? const SizedBox(
                      width: 16,
                      height: 16,
                      child: CircularProgressIndicator(strokeWidth: 2),
                    )
                  : TextButton(
                      onPressed: () => _run(() => _auth.signOut()),
                      child: const Text('Sign out'),
                    ),
            ),
          );
        }
        return Card(
          child: Padding(
            padding: const EdgeInsets.all(16),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                const Text(
                  'Sign in to sync',
                  style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold),
                ),
                const SizedBox(height: 4),
                const Text(
                  'Accounts are created by your admin — ask for a WhatsApp invite link.',
                ),
                const SizedBox(height: 8),
                TextField(
                  controller: _email,
                  keyboardType: TextInputType.emailAddress,
                  decoration: const InputDecoration(labelText: 'Email'),
                  enabled: !_busy,
                ),
                const SizedBox(height: 8),
                TextField(
                  controller: _password,
                  obscureText: true,
                  decoration: const InputDecoration(labelText: 'Password'),
                  enabled: !_busy,
                ),
                if (_error != null) ...[
                  const SizedBox(height: 8),
                  Text(
                    _error!,
                    style: TextStyle(
                      color: Theme.of(context).colorScheme.error,
                    ),
                  ),
                ],
                const SizedBox(height: 12),
                FilledButton(
                  onPressed: _busy
                      ? null
                      : () => _run(
                          () => _auth.signIn(
                            email: _email.text.trim(),
                            password: _password.text,
                          ),
                        ),
                  child: const Text('Sign in'),
                ),
                const SizedBox(height: 8),
                const Divider(),
                const Text(
                  'Have an invite link? Paste it to set your password.',
                  style: TextStyle(fontWeight: FontWeight.bold),
                ),
                const SizedBox(height: 8),
                TextField(
                  controller: _inviteLink,
                  minLines: 1,
                  maxLines: 3,
                  decoration: const InputDecoration(
                    labelText: 'WhatsApp invite link',
                    hintText: 'Paste the full link here',
                  ),
                  enabled: !_busy,
                ),
                const SizedBox(height: 8),
                OutlinedButton(
                  onPressed: _busy
                      ? null
                      : () {
                          final link = _inviteLink.text.trim();
                          if (link.isEmpty) return;
                          Navigator.of(context).push(
                            MaterialPageRoute(
                              builder: (_) => InviteAcceptScreen(link: link),
                            ),
                          );
                        },
                  child: const Text('Accept invite link'),
                ),
              ],
            ),
          ),
        );
      },
    );
  }
}

/// Admin-only invite/resend/recover surface. Hidden for every other role —
/// and the server function re-checks adminship, so hiding is convenience,
/// not the defense.
class _InviteCard extends StatefulWidget {
  const _InviteCard();

  @override
  State<_InviteCard> createState() => _InviteCardState();
}

class _InviteCardState extends State<_InviteCard> {
  final _nameAr = TextEditingController();
  final _nameEn = TextEditingController();
  final _phone = TextEditingController();
  UserRole _role = UserRole.employee;
  InviteMode _mode = InviteMode.invite;
  bool _busy = false;
  String? _error;
  InviteResult? _result;

  @override
  void dispose() {
    _nameAr.dispose();
    _nameEn.dispose();
    _phone.dispose();
    super.dispose();
  }

  Future<void> _send() async {
    setState(() {
      _busy = true;
      _error = null;
      _result = null;
    });
    try {
      final result = await InviteService().send(
        nameAr: _nameAr.text,
        nameEn: _nameEn.text,
        phone: _phone.text,
        role: _role,
        mode: _mode,
      );
      if (mounted) setState(() => _result = result);
    } on AuthOfflineException catch (e) {
      setState(() => _error = e.message);
    } on AuthFailureException catch (e) {
      setState(() => _error = e.message);
    } catch (e) {
      setState(() => _error = 'Unexpected error: $e');
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final auth = AuthService.instance;
    if (!auth.isConfigured) return const SizedBox.shrink();
    return StreamBuilder<UserRole?>(
      stream: auth.currentRoleStream,
      initialData: auth.currentRole,
      builder: (context, snapshot) {
        if (!auth.isSignedIn || snapshot.data != UserRole.admin) {
          return const SizedBox.shrink();
        }
        final slugHint = _nameEn.text.trim().isEmpty
            ? ''
            : 'Login preview: ${InviteService.slugPreview(_nameEn.text)}@…';
        return Card(
          child: Padding(
            padding: const EdgeInsets.all(16),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                const Text(
                  'Invite users',
                  style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold),
                ),
                const SizedBox(height: 4),
                const Text(
                  'Send the generated link over WhatsApp. The user sets their own password — nothing secret stays in chat.',
                ),
                const SizedBox(height: 8),
                TextField(
                  controller: _nameAr,
                  decoration: const InputDecoration(labelText: 'Name (Arabic)'),
                  enabled: !_busy,
                ),
                const SizedBox(height: 8),
                TextField(
                  controller: _nameEn,
                  decoration: const InputDecoration(
                    labelText: 'Name (English)',
                  ),
                  enabled: !_busy,
                  onChanged: (_) => setState(() {}),
                ),
                if (slugHint.isNotEmpty) ...[
                  const SizedBox(height: 4),
                  Text(slugHint, style: Theme.of(context).textTheme.bodySmall),
                ],
                const SizedBox(height: 8),
                TextField(
                  controller: _phone,
                  keyboardType: TextInputType.phone,
                  decoration: const InputDecoration(
                    labelText: 'Phone (WhatsApp)',
                  ),
                  enabled: !_busy,
                ),
                const SizedBox(height: 8),
                Row(
                  children: [
                    Expanded(
                      child: DropdownButtonFormField<UserRole>(
                        initialValue: _role,
                        decoration: const InputDecoration(labelText: 'Role'),
                        items: const [
                          DropdownMenuItem(
                            value: UserRole.employee,
                            child: Text('Employee'),
                          ),
                          DropdownMenuItem(
                            value: UserRole.distributor,
                            child: Text('Distributor'),
                          ),
                        ],
                        onChanged: _busy
                            ? null
                            : (value) {
                                if (value != null) {
                                  setState(() => _role = value);
                                }
                              },
                      ),
                    ),
                    const SizedBox(width: 8),
                    Expanded(
                      child: DropdownButtonFormField<InviteMode>(
                        initialValue: _mode,
                        decoration: const InputDecoration(labelText: 'Action'),
                        items: const [
                          DropdownMenuItem(
                            value: InviteMode.invite,
                            child: Text('New invite'),
                          ),
                          DropdownMenuItem(
                            value: InviteMode.resend,
                            child: Text('Resend link'),
                          ),
                          DropdownMenuItem(
                            value: InviteMode.recovery,
                            child: Text('Reset password'),
                          ),
                        ],
                        onChanged: _busy
                            ? null
                            : (value) {
                                if (value != null) {
                                  setState(() => _mode = value);
                                }
                              },
                      ),
                    ),
                  ],
                ),
                if (_error != null) ...[
                  const SizedBox(height: 8),
                  Text(
                    _error!,
                    style: TextStyle(
                      color: Theme.of(context).colorScheme.error,
                    ),
                  ),
                ],
                if (_result != null) ...[
                  const SizedBox(height: 8),
                  SelectableText('Login: ${_result!.fakeEmail}'),
                  const SizedBox(height: 4),
                  SelectableText(_result!.actionLink),
                  const SizedBox(height: 8),
                  OutlinedButton.icon(
                    onPressed: () {
                      Clipboard.setData(
                        ClipboardData(
                          text:
                              'Your account: ${_result!.fakeEmail}\nOpen this link to set your password:\n${_result!.actionLink}',
                        ),
                      );
                      ScaffoldMessenger.of(context).showSnackBar(
                        const SnackBar(
                          content: Text('Copied — forward it over WhatsApp.'),
                        ),
                      );
                    },
                    icon: const Icon(Icons.copy),
                    label: const Text('Copy for WhatsApp'),
                  ),
                ],
                const SizedBox(height: 12),
                FilledButton(
                  onPressed: _busy ? null : _send,
                  child: _busy
                      ? const SizedBox(
                          width: 16,
                          height: 16,
                          child: CircularProgressIndicator(strokeWidth: 2),
                        )
                      : Text(switch (_mode) {
                          InviteMode.invite => 'Create invite link',
                          InviteMode.resend => 'Resend invite link',
                          InviteMode.recovery => 'Send password-reset link',
                        }),
                ),
              ],
            ),
          ),
        );
      },
    );
  }
}
