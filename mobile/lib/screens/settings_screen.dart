import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:get_it/get_it.dart';
import 'package:intl/intl.dart';
import 'package:path/path.dart' as p;
import 'package:shared_preferences/shared_preferences.dart';
import 'package:sqflite/sqflite.dart';
import 'package:i_gen/auth/auth_exceptions.dart';
import 'package:i_gen/auth/auth_service.dart';
import 'package:i_gen/auth/invite_service.dart';
import 'package:i_gen/repos/backup_service.dart';
import 'package:i_gen/screens/invite_accept_screen.dart';
import 'package:i_gen/sync/sync_bootstrap.dart';
import 'package:i_gen/utils/backup_flow.dart';
import 'package:i_gen/utils/context_extensions.dart';
import 'package:i_gen/utils/locale_controller.dart';
import 'package:i_gen/widgets/sync_status_card.dart';

/// Settings: sign-in state + admin invite tiles + sync status + backups.
///
/// Login is optional and never blocks offline use; sign-up is invite-only so
/// there is no "create account" path here — new users arrive via an admin
/// WhatsApp link and accept it below. The sync card appears only after the
/// staging gate passes ([kSyncStagingGatePassed]).
///
/// Invite creation is two role-specific tiles that each open a dialog; there
/// is deliberately no invite history — the generated link/dialog is the only
/// copy, and closing it discards it. Admins are expected to share
/// immediately (see the share-first result panel in [_InviteDialog]).
class SettingsScreen extends StatelessWidget {
  const SettingsScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return DefaultTabController(
      length: 2,
      child: Scaffold(
        appBar: AppBar(
          title: Text(context.l10n.navSettings),
          actions: [
            IconButton(
              tooltip: Localizations.localeOf(context).languageCode == 'ar'
                  ? 'English'
                  : 'العربية',
              icon: const Icon(Icons.language_outlined),
              onPressed: () => LocaleController.instance.toggle(),
            ),
          ],
          bottom: TabBar(
            tabs: [
              Tab(text: context.l10n.settingsTabAccount),
              Tab(text: context.l10n.backupSectionTitle),
            ],
          ),
        ),
        body: TabBarView(
          children: [
            _tab([
              const _AuthCard(),
              const _InviteTilesCard(),
              if (kSyncStagingGatePassed) const _SyncSection(),
            ]),
            _tab(const [_BackupCard()]),
          ],
        ),
      ),
    );
  }

  /// Shared tab padding; content is width-capped and centered so text/cards
  /// stay readable instead of stretching edge-to-edge on wide screens.
  static Widget _tab(List<Widget> children) {
    return SingleChildScrollView(
      padding: const EdgeInsets.all(AppGaps.md),
      child: Center(
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 640),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              for (final child in children) ...[
                child,
                const SizedBox(height: AppGaps.xl),
              ],
            ],
          ),
        ),
      ),
    );
  }
}

/// Consistent card shell used across every settings surface.
class SettingsCard extends StatelessWidget {
  const SettingsCard({super.key, required this.child, this.color});

  final Widget child;
  final Color? color;

  @override
  Widget build(BuildContext context) {
    return Card(
      color: color,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(AppRadii.card),
      ),
      child: Padding(padding: const EdgeInsets.all(AppGaps.md), child: child),
    );
  }
}

/// Inline error banner — reused by every form on this screen.
class ErrorBanner extends StatelessWidget {
  const ErrorBanner({super.key, required this.message});
  final String message;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(AppGaps.sm),
      decoration: BoxDecoration(
        color: context.colorScheme.errorContainer,
        borderRadius: BorderRadius.circular(AppRadii.control),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(
            Icons.error_outline,
            size: 18,
            color: context.colorScheme.onErrorContainer,
          ),
          const SizedBox(width: AppGaps.xs),
          Expanded(
            child: Text(
              message,
              style: context.textTheme.bodyMedium?.copyWith(
                color: context.colorScheme.onErrorContainer,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

/// Dims + locks a form's contents while busy, so "this is working" reads as
/// one visual state instead of relying on users noticing disabled fields.
class BusyGate extends StatelessWidget {
  const BusyGate({super.key, required this.busy, required this.child});
  final bool busy;
  final Widget child;

  @override
  Widget build(BuildContext context) {
    return AnimatedOpacity(
      opacity: busy ? 0.6 : 1,
      duration: const Duration(milliseconds: 150),
      child: AbsorbPointer(absorbing: busy, child: child),
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
  bool _busy = false;
  String? _error;

  @override
  void dispose() {
    _email.dispose();
    _password.dispose();
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
      setState(() => _error = context.l10n.unexpectedError('$e'));
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  void _showInviteSheet() {
    final ctrl = TextEditingController();
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(
          top: Radius.circular(AppRadii.card),
        ),
      ),
      builder: (ctx) {
        return Padding(
          padding: EdgeInsets.only(
            left: AppGaps.md,
            right: AppGaps.md,
            top: AppGaps.md,
            bottom: MediaQuery.of(ctx).viewInsets.bottom + AppGaps.md,
          ),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Container(
                width: 32,
                height: 4,
                margin: const EdgeInsets.only(bottom: AppGaps.md),
                decoration: BoxDecoration(
                  color: context.colorScheme.outlineVariant,
                  borderRadius: BorderRadius.circular(2),
                ),
                alignment: Alignment.center,
              ).center(),
              Text(
                context.l10n.haveInviteLinkTitle,
                style: context.textTheme.titleMedium?.copyWith(
                  fontWeight: FontWeight.bold,
                ),
              ),
              const SizedBox(height: AppGaps.sm),
              TextField(
                controller: ctrl,
                minLines: 1,
                maxLines: 3,
                decoration: InputDecoration(
                  labelText: context.l10n.inviteLinkFieldLabel,
                  hintText: context.l10n.inviteLinkFieldHint,
                  border: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(AppRadii.control),
                  ),
                ),
                autofocus: true,
              ),
              const SizedBox(height: AppGaps.md),
              FilledButton(
                style: const ButtonStyle(
                  minimumSize: WidgetStatePropertyAll(Size(64, 48)),
                ),
                onPressed: () {
                  final link = ctrl.text.trim();
                  if (link.isEmpty) return;
                  Navigator.of(ctx).pop();
                  Navigator.of(context).push(
                    MaterialPageRoute(
                      builder: (_) => InviteAcceptScreen(link: link),
                    ),
                  );
                },
                child: Text(context.l10n.acceptInviteLink),
              ),
              const SizedBox(height: AppGaps.sm),
            ],
          ),
        );
      },
    );
  }

  @override
  Widget build(BuildContext context) {
    if (!_auth.isConfigured) {
      return SettingsCard(
        child: Row(
          children: [
            Icon(
              Icons.cloud_off_outlined,
              color: context.colorScheme.onSurfaceVariant,
            ),
            const SizedBox(width: AppGaps.sm),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    context.l10n.syncNotConfigured,
                    style: context.textTheme.titleSmall?.copyWith(
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                  Text(
                    context.l10n.syncNotConfiguredHint,
                    style: context.textTheme.bodySmall?.copyWith(
                      color: context.colorScheme.onSurfaceVariant,
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
      );
    }
    return StreamBuilder(
      stream: _auth.currentUserStream,
      initialData: _auth.currentUser,
      builder: (context, snapshot) {
        final user = snapshot.data ?? _auth.currentUser;
        if (user != null) {
          return SettingsCard(
            color: context.colorScheme.surfaceContainerHighest.withValues(
              alpha: 0.4,
            ),
            child: Row(
              children: [
                Container(
                  width: 44,
                  height: 44,
                  decoration: BoxDecoration(
                    color: context.colorScheme.primaryContainer,
                    borderRadius: BorderRadius.circular(AppRadii.control),
                  ),
                  child: Icon(
                    Icons.account_circle_outlined,
                    color: context.colorScheme.onPrimaryContainer,
                  ),
                ),
                const SizedBox(width: AppGaps.md),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        user.email ?? context.l10n.signedInFallback,
                        style: context.textTheme.titleSmall?.copyWith(
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                    ],
                  ),
                ),
                const SizedBox(width: AppGaps.sm),
                _busy
                    ? const SizedBox(
                        width: AppGaps.md,
                        height: AppGaps.md,
                        child: CircularProgressIndicator(strokeWidth: 2),
                      )
                    : TextButton(
                        style: const ButtonStyle(
                          minimumSize: WidgetStatePropertyAll(Size(64, 48)),
                        ),
                        onPressed: () => _run(() => _auth.signOut()),
                        child: Text(context.l10n.signOut),
                      ),
              ],
            ),
          );
        }
        return SettingsCard(
          child: BusyGate(
            busy: _busy,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Row(
                  children: [
                    Icon(
                      Icons.login_outlined,
                      color: context.colorScheme.primary,
                      size: 20,
                    ),
                    const SizedBox(width: AppGaps.sm),
                    Text(
                      context.l10n.signInToSync,
                      style: context.textTheme.titleMedium?.copyWith(
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: AppGaps.xs),
                Text(
                  context.l10n.signInInviteHint,
                  style: context.textTheme.bodySmall?.copyWith(
                    color: context.colorScheme.onSurfaceVariant,
                  ),
                ),
                const SizedBox(height: AppGaps.md),
                TextField(
                  controller: _email,
                  keyboardType: TextInputType.emailAddress,
                  decoration: InputDecoration(
                    labelText: context.l10n.emailLabel,
                    prefixIcon: const Icon(
                      Icons.alternate_email_outlined,
                      size: 20,
                    ),
                    border: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(AppRadii.control),
                    ),
                  ),
                ),
                const SizedBox(height: AppGaps.sm),
                TextField(
                  controller: _password,
                  obscureText: true,
                  decoration: InputDecoration(
                    labelText: context.l10n.passwordLabel,
                    prefixIcon: const Icon(Icons.lock_outline, size: 20),
                    border: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(AppRadii.control),
                    ),
                  ),
                ),
                if (_error != null) ...[
                  const SizedBox(height: AppGaps.sm),
                  ErrorBanner(message: _error!),
                ],
                const SizedBox(height: AppGaps.md),
                FilledButton(
                  style: const ButtonStyle(
                    minimumSize: WidgetStatePropertyAll(Size(64, 48)),
                  ),
                  onPressed: () => _run(
                    () => _auth.signIn(
                      email: _email.text.trim(),
                      password: _password.text,
                    ),
                  ),
                  child: Text(context.l10n.signInAction),
                ),
                const SizedBox(height: AppGaps.sm),
                TextButton.icon(
                  style: const ButtonStyle(
                    minimumSize: WidgetStatePropertyAll(Size(64, 48)),
                  ),
                  onPressed: _showInviteSheet,
                  icon: const Icon(Icons.link_outlined, size: 20),
                  label: Text(context.l10n.haveInviteLinkTitle),
                ),
              ],
            ),
          ),
        );
      },
    );
  }
}

extension _Center on Widget {
  Widget center() => Center(child: this);
}

/// Admin-only invite surface: two role-specific tiles, each opening
/// [_InviteDialog] pre-locked to that role. Hidden for every other role —
/// and the server function re-checks adminship, so hiding is convenience,
/// not the defense.
class _InviteTilesCard extends StatelessWidget {
  const _InviteTilesCard();

  static const double _twoColumnThreshold = 420;

  void _openDialog(BuildContext context, UserRole role) {
    showDialog(
      context: context,
      builder: (_) => _InviteDialog(role: role),
    );
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
        return SettingsCard(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Row(
                children: [
                  Icon(
                    Icons.person_add_outlined,
                    color: context.colorScheme.primary,
                  ),
                  const SizedBox(width: AppGaps.sm),
                  Expanded(
                    child: Text(
                      context.l10n.inviteUsersTitle,
                      style: context.textTheme.titleMedium?.copyWith(
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: AppGaps.xs),
              Text(
                context.l10n.inviteUsersHint,
                style: context.textTheme.bodySmall?.copyWith(
                  color: context.colorScheme.onSurfaceVariant,
                ),
              ),
              const SizedBox(height: AppGaps.md),
              LayoutBuilder(
                builder: (context, constraints) {
                  final employee = _InviteRoleTile(
                    icon: Icons.badge_outlined,
                    label: context.l10n.roleEmployee,
                    onTap: () => _openDialog(context, UserRole.employee),
                  );
                  final customer = _InviteRoleTile(
                    icon: Icons.local_shipping_outlined,
                    label: context.l10n.roleCustomer,
                    onTap: () => _openDialog(context, UserRole.customer),
                  );
                  if (constraints.maxWidth < _twoColumnThreshold) {
                    return Column(
                      children: [
                        employee,
                        const SizedBox(height: AppGaps.sm),
                        customer,
                      ],
                    );
                  }
                  return Row(
                    children: [
                      Expanded(child: employee),
                      const SizedBox(width: AppGaps.sm),
                      Expanded(child: customer),
                    ],
                  );
                },
              ),
            ],
          ),
        );
      },
    );
  }
}

/// A single role-specific "start an invite" tile — deliberately not styled
/// as a navigation row (no chevron): tapping opens a dialog on top of the
/// current screen, it doesn't drill into another page.
class _InviteRoleTile extends StatelessWidget {
  const _InviteRoleTile({
    required this.icon,
    required this.label,
    required this.onTap,
  });

  final IconData icon;
  final String label;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return InkWell(
      borderRadius: BorderRadius.circular(AppRadii.control),
      onTap: onTap,
      child: Container(
        width: double.infinity,
        padding: const EdgeInsets.symmetric(
          vertical: AppGaps.md,
          horizontal: AppGaps.sm,
        ),
        decoration: BoxDecoration(
          border: Border.all(color: context.colorScheme.outlineVariant),
          borderRadius: BorderRadius.circular(AppRadii.control),
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Container(
              width: 40,
              height: 40,
              decoration: BoxDecoration(
                color: context.colorScheme.primaryContainer,
                shape: BoxShape.circle,
              ),
              child: Icon(
                icon,
                size: 20,
                color: context.colorScheme.onPrimaryContainer,
              ),
            ),
            const SizedBox(height: AppGaps.xs),
            Text(
              label,
              textAlign: TextAlign.center,
              style: context.textTheme.labelLarge?.copyWith(
                fontWeight: FontWeight.w600,
              ),
            ),
            const SizedBox(height: 2),
            Icon(
              Icons.add_circle_outline,
              size: 16,
              color: context.colorScheme.onSurfaceVariant,
            ),
          ],
        ),
      ),
    );
  }
}

/// The invite creation dialog. Role is fixed by whichever tile opened it —
/// there's no role picker here, since that decision already happened.
/// Mode (new/resend/recovery) is still selectable: it's a different axis
/// than role. On success the dialog flips in place to a share-first result
/// panel; closing the dialog discards the link — there is intentionally no
/// history, so admins are expected to share immediately.
class _InviteDialog extends StatefulWidget {
  const _InviteDialog({required this.role});
  final UserRole role;

  @override
  State<_InviteDialog> createState() => _InviteDialogState();
}

class _InviteDialogState extends State<_InviteDialog> {
  final _formKey = GlobalKey<FormState>();
  final _nameAr = TextEditingController();
  final _nameEn = TextEditingController();
  final _phone = TextEditingController();
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

  String get _roleLabel => widget.role == UserRole.employee
      ? context.l10n.roleEmployee
      : context.l10n.roleCustomer;

  String get _actionLabel => switch (_mode) {
    InviteMode.invite => context.l10n.createInviteLink,
    InviteMode.resend => context.l10n.resendInviteLink,
    InviteMode.recovery => context.l10n.sendPasswordResetLink,
  };

  Future<void> _submit() async {
    if (!(_formKey.currentState?.validate() ?? false)) return;
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      final result = await InviteService().send(
        nameAr: _nameAr.text,
        nameEn: _nameEn.text,
        phone: _phone.text,
        role: widget.role,
        mode: _mode,
      );
      if (mounted) setState(() => _result = result);
    } on AuthOfflineException catch (e) {
      setState(() => _error = e.message);
    } on AuthFailureException catch (e) {
      setState(() => _error = e.message);
    } catch (e) {
      setState(() => _error = context.l10n.unexpectedError('$e'));
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  void _copy(InviteResult result) {
    Clipboard.setData(
      ClipboardData(
        text: context.l10n.inviteShareText(result.fakeEmail, result.actionLink),
      ),
    );
    ScaffoldMessenger.of(
      context,
    ).showSnackBar(SnackBar(content: Text(context.l10n.inviteCopiedHint)));
  }

  Future<void> _share(InviteResult result) async {
    // Once `share_plus` is added to pubspec.yaml, replace this with:
    //   await Share.share(context.l10n.inviteShareText(result.fakeEmail, result.actionLink));
    // Until then, share falls back to copy (same clipboard payload).
    _copy(result);
  }

  @override
  Widget build(BuildContext context) {
    return Dialog(
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(AppRadii.card),
      ),
      insetPadding: const EdgeInsets.all(AppGaps.md),
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 480),
        child: Padding(
          padding: const EdgeInsets.all(AppGaps.lg),
          child: SingleChildScrollView(
            child: _result != null
                ? _buildResult(context)
                : _buildForm(context),
          ),
        ),
      ),
    );
  }

  Widget _buildForm(BuildContext context) {
    final slug = _nameEn.text.trim().isEmpty
        ? null
        : InviteService.slugPreview(_nameEn.text);
    return Form(
      key: _formKey,
      autovalidateMode: AutovalidateMode.onUserInteraction,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            children: [
              Expanded(
                child: Text(
                  // TODO(l10n): a combined "Invite {role}" title string
                  // would read better than concatenating two keys.
                  '${context.l10n.inviteUsersTitle} · $_roleLabel',
                  style: context.textTheme.titleMedium?.copyWith(
                    fontWeight: FontWeight.bold,
                  ),
                ),
              ),
              IconButton(
                icon: const Icon(Icons.close),
                onPressed: () => Navigator.of(context).pop(),
                tooltip: context.l10n.cancelButton,
              ),
            ],
          ),
          const SizedBox(height: AppGaps.sm),
          Text(
            context.l10n.inviteActionLabel,
            style: context.textTheme.labelLarge,
          ),
          const SizedBox(height: AppGaps.xs),
          SizedBox(
            width: double.infinity,
            child: SegmentedButton<InviteMode>(
              segments: [
                ButtonSegment(
                  value: InviteMode.invite,
                  label: Text(context.l10n.inviteModeNew),
                  icon: const Icon(Icons.person_add_alt_1_outlined, size: 16),
                ),
                ButtonSegment(
                  value: InviteMode.resend,
                  label: Text(context.l10n.inviteModeResend),
                  icon: const Icon(Icons.send_outlined, size: 16),
                ),
                ButtonSegment(
                  value: InviteMode.recovery,
                  label: Text(context.l10n.inviteModeRecovery),
                  icon: const Icon(Icons.lock_reset_outlined, size: 16),
                ),
              ],
              selected: {_mode},
              onSelectionChanged: _busy
                  ? null
                  : (s) => setState(() => _mode = s.first),
            ),
          ),
          if (_mode != InviteMode.invite) ...[
            const SizedBox(height: AppGaps.xs),
            Text(
              // TODO(l10n): there's no user lookup yet, so resend/recovery
              // still require re-typing the person's original details.
              "Enter this person's existing details exactly as used before.",
              style: context.textTheme.bodySmall?.copyWith(
                color: context.colorScheme.onSurfaceVariant,
                fontStyle: FontStyle.italic,
              ),
            ),
          ],
          const SizedBox(height: AppGaps.md),
          BusyGate(
            busy: _busy,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                TextFormField(
                  controller: _nameAr,
                  decoration: InputDecoration(
                    labelText: context.l10n.nameArabicLabel,
                    border: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(AppRadii.control),
                    ),
                  ),
                  validator: (v) => (v == null || v.trim().isEmpty)
                      // TODO(l10n): proper "required" validation message.
                      ? context.l10n.nameArabicLabel
                      : null,
                ),
                const SizedBox(height: AppGaps.sm),
                TextFormField(
                  controller: _nameEn,
                  decoration: InputDecoration(
                    labelText: context.l10n.nameEnglishLabel,
                    helperText: slug == null
                        ? null
                        : context.l10n.loginPreview(slug),
                    border: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(AppRadii.control),
                    ),
                  ),
                  onChanged: (_) => setState(() {}),
                  validator: (v) => (v == null || v.trim().isEmpty)
                      ? context.l10n.nameEnglishLabel
                      : null,
                ),
                const SizedBox(height: AppGaps.sm),
                TextFormField(
                  controller: _phone,
                  keyboardType: TextInputType.phone,
                  decoration: InputDecoration(
                    labelText: context.l10n.phoneWhatsappLabel,
                    prefixIcon: const Icon(Icons.phone_outlined, size: 20),
                    border: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(AppRadii.control),
                    ),
                  ),
                  validator: (v) => (v == null || v.trim().length < 6)
                      ? context.l10n.phoneWhatsappLabel
                      : null,
                ),
              ],
            ),
          ),
          if (_error != null) ...[
            const SizedBox(height: AppGaps.md),
            ErrorBanner(message: _error!),
          ],
          const SizedBox(height: AppGaps.lg),
          FilledButton(
            style: const ButtonStyle(
              minimumSize: WidgetStatePropertyAll(Size(64, 48)),
            ),
            onPressed: _busy ? null : _submit,
            child: _busy
                ? const SizedBox(
                    width: AppGaps.md,
                    height: AppGaps.md,
                    child: CircularProgressIndicator(strokeWidth: 2),
                  )
                : Text(_actionLabel),
          ),
        ],
      ),
    );
  }

  Widget _buildResult(BuildContext context) {
    final result = _result!;
    final name = _nameEn.text.trim().isEmpty
        ? _nameAr.text.trim()
        : _nameEn.text.trim();
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Row(
          children: [
            const Spacer(),
            IconButton(
              icon: const Icon(Icons.close),
              onPressed: () => Navigator.of(context).pop(),
              tooltip: context.l10n.cancelButton,
            ),
          ],
        ),
        Icon(
          Icons.check_circle_outline,
          color: context.colorScheme.primary,
          size: 40,
        ),
        const SizedBox(height: AppGaps.sm),
        Text(
          // TODO(l10n): dedicated "Ready to send" string.
          'Ready to send',
          textAlign: TextAlign.center,
          style: context.textTheme.titleMedium?.copyWith(
            fontWeight: FontWeight.bold,
          ),
        ),
        const SizedBox(height: AppGaps.xs),
        Text(
          '$name · $_roleLabel',
          textAlign: TextAlign.center,
          style: context.textTheme.bodyMedium?.copyWith(
            color: context.colorScheme.onSurfaceVariant,
          ),
        ),
        const SizedBox(height: AppGaps.md),
        Container(
          width: double.infinity,
          padding: const EdgeInsets.all(AppGaps.sm),
          decoration: BoxDecoration(
            color: context.colorScheme.surfaceContainerHighest,
            borderRadius: BorderRadius.circular(AppRadii.control),
            border: Border.all(color: context.colorScheme.outlineVariant),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              SelectableText(
                context.l10n.loginEmailLabel(result.fakeEmail),
                style: context.textTheme.bodySmall,
              ),
              const SizedBox(height: AppGaps.xs),
              SelectableText(
                result.actionLink,
                style: context.textTheme.bodySmall?.copyWith(
                  fontFamily: 'monospace',
                ),
              ),
            ],
          ),
        ),
        const SizedBox(height: AppGaps.md),
        FilledButton.icon(
          style: const ButtonStyle(
            minimumSize: WidgetStatePropertyAll(Size(64, 48)),
          ),
          onPressed: () => _share(result),
          icon: const Icon(Icons.share_outlined),
          // TODO(l10n): dedicated "Share link" string — reusing the copy
          // label as a stopgap since both currently do the same thing.
          label: Text(context.l10n.copyForWhatsapp),
        ),
        const SizedBox(height: AppGaps.sm),
        OutlinedButton.icon(
          style: const ButtonStyle(
            minimumSize: WidgetStatePropertyAll(Size(64, 48)),
          ),
          onPressed: () => _copy(result),
          icon: const Icon(Icons.copy_outlined),
          label: Text(context.l10n.copyForWhatsapp),
        ),
        const SizedBox(height: AppGaps.sm),
        TextButton(
          onPressed: () => Navigator.of(context).pop(),
          // TODO(l10n): dedicated "Close" string.
          child: const Text('Close'),
        ),
      ],
    );
  }
}

/// Sync status card + the offline-first reassurance note beneath it.
class _SyncSection extends StatelessWidget {
  const _SyncSection();

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        const SyncStatusCard(),
        const SizedBox(height: AppGaps.sm),
        Text(
          context.l10n.settingsOfflineFirstNote,
          style: context.textTheme.bodySmall?.copyWith(
            color: context.colorScheme.onSurfaceVariant,
          ),
        ),
      ],
    );
  }
}

/// Manual backup (save to folder) + restore-from-file + auto-backup status.
///
/// Backup failures toast and never touch live data. Restore validates the
/// picked file before anything is swapped; when the outbox holds unsynced
/// changes the user confirms the replacement count first.
class _BackupCard extends StatefulWidget {
  const _BackupCard();

  @override
  State<_BackupCard> createState() => _BackupCardState();
}

enum _BackupOp { none, backingUp, restoring }

class _BackupCardState extends State<_BackupCard> {
  _BackupOp _op = _BackupOp.none;
  DateTime? _lastAuto;
  int _intervalDays = BackupService.defaultAutoIntervalDays;
  String? _defaultDir;

  bool get _busy => _op != _BackupOp.none;

  @override
  void initState() {
    super.initState();
    _loadStatus();
  }

  Future<void> _loadStatus() async {
    try {
      final service = await buildBackupService();
      final prefs = await SharedPreferences.getInstance();
      final at = await service.lastAutoBackupAt(prefs);
      if (mounted) {
        setState(() {
          _lastAuto = at;
          _intervalDays =
              prefs.getInt(BackupService.autoIntervalDaysKey) ??
              BackupService.defaultAutoIntervalDays;
          _defaultDir = prefs.getString(BackupService.defaultDirKey);
        });
      }
    } catch (e) {
      debugPrint('Backup: status load skipped: $e');
    }
  }

  void _toast(String message) {
    ScaffoldMessenger.of(
      context,
    ).showSnackBar(SnackBar(content: Text(message)));
  }

  static String _message(Object e) => e is StateError ? e.message : '$e';

  String _format(DateTime time) {
    final code = Localizations.localeOf(context).languageCode;
    return DateFormat.yMd(code).add_Hm().format(time.toLocal());
  }

  Future<void> _backupNow() async {
    if (_busy) return;
    setState(() => _op = _BackupOp.backingUp);
    try {
      final service = await buildBackupService();
      final prefs = await SharedPreferences.getInstance();
      final dir =
          prefs.getString(BackupService.defaultDirKey) ??
          await FilePicker.getDirectoryPath();
      if (dir == null) return; // Picker cancelled.
      final target = p.join(
        dir,
        'i_gen-backup-${BackupService.fileStamp()}.db',
      );
      await service.backupToFile(target);
      await _loadStatus();
      if (!mounted) return;
      _toast(context.l10n.backupSaved(target));
    } catch (e) {
      if (!mounted) return;
      _toast(context.l10n.backupFailed(_message(e)));
    } finally {
      if (mounted) setState(() => _op = _BackupOp.none);
    }
  }

  Future<void> _pickDefaultDir() async {
    final dir = await FilePicker.getDirectoryPath();
    if (dir == null) return; // Picker cancelled.
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(BackupService.defaultDirKey, dir);
    await _loadStatus();
  }

  Future<void> _clearDefaultDir() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.remove(BackupService.defaultDirKey);
    await _loadStatus();
  }

  Future<void> _setInterval(int days) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setInt(BackupService.autoIntervalDaysKey, days);
    await _loadStatus();
  }

  Future<void> _restore() async {
    if (_busy) return;
    final picked = await FilePicker.pickFile(
      type: FileType.custom,
      allowedExtensions: ['db'],
    );
    final path = picked?.path;
    if (path == null) return; // Picker cancelled.
    if (!mounted) return;
    try {
      await BackupService.validateBackupFile(path);
    } catch (e) {
      if (!mounted) return;
      _toast(context.l10n.restoreFailed(_message(e)));
      return;
    }
    int pending = 0;
    try {
      pending = await outboxPendingCount(GetIt.I.get<Database>());
    } catch (e) {
      debugPrint('Backup: outbox count skipped: $e');
    }
    if (!mounted) return;
    if (pending > 0) {
      final confirmed = await showDialog<bool>(
        context: context,
        builder: (ctx) => AlertDialog(
          title: Text(context.l10n.restoreConfirmTitle),
          content: Text(context.l10n.restoreConfirmMessage(pending)),
          actions: [
            TextButton(
              onPressed: () => Navigator.of(ctx).pop(false),
              child: Text(context.l10n.cancelButton),
            ),
            FilledButton(
              onPressed: () => Navigator.of(ctx).pop(true),
              child: Text(context.l10n.backupRestore),
            ),
          ],
        ),
      );
      if (confirmed != true || !mounted) return;
    }
    setState(() => _op = _BackupOp.restoring);
    try {
      await restoreDatabaseFromFile(path);
      await _loadStatus();
      if (!mounted) return;
      _toast(context.l10n.restoreSuccess);
    } catch (e) {
      if (!mounted) return;
      _toast(context.l10n.restoreFailed(_message(e)));
    } finally {
      if (mounted) setState(() => _op = _BackupOp.none);
    }
  }

  @override
  Widget build(BuildContext context) {
    final status = _lastAuto == null
        ? context.l10n.backupLastAuto(context.l10n.neverSynced)
        : context.l10n.backupLastAuto(_format(_lastAuto!));
    return SettingsCard(
      child: BusyGate(
        busy: _busy,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Row(
              children: [
                Icon(Icons.backup_outlined, color: context.colorScheme.primary),
                const SizedBox(width: AppGaps.sm),
                Expanded(
                  child: Text(
                    context.l10n.backupSectionTitle,
                    style: context.textTheme.titleMedium?.copyWith(
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                ),
              ],
            ),
            const SizedBox(height: AppGaps.xs),
            Text(
              status,
              style: context.textTheme.bodySmall?.copyWith(
                color: context.colorScheme.onSurfaceVariant,
              ),
            ),
            const Divider(height: AppGaps.xl),
            Text(
              context.l10n.backupInterval,
              style: context.textTheme.labelLarge,
            ),
            const SizedBox(height: AppGaps.xs),
            SizedBox(
              width: double.infinity,
              child: SegmentedButton<int>(
                segments: [
                  ButtonSegment(
                    value: 0,
                    label: Text(context.l10n.backupIntervalOff),
                  ),
                  ButtonSegment(
                    value: 1,
                    label: Text(context.l10n.backupIntervalDaily),
                  ),
                  ButtonSegment(
                    value: 7,
                    label: Text(context.l10n.backupIntervalWeekly),
                  ),
                  ButtonSegment(
                    value: 30,
                    label: Text(context.l10n.backupIntervalMonthly),
                  ),
                ],
                selected: {_intervalDays},
                onSelectionChanged: _busy
                    ? null
                    : (selection) => _setInterval(selection.first),
              ),
            ),
            const Divider(height: AppGaps.xl),
            Text(
              context.l10n.backupLocation,
              style: context.textTheme.labelLarge,
            ),
            const SizedBox(height: AppGaps.xs),
            Row(
              children: [
                Expanded(
                  child: Tooltip(
                    message: _defaultDir ?? context.l10n.backupNoLocation,
                    child: Text(
                      _defaultDir ?? context.l10n.backupNoLocation,
                      style: context.textTheme.bodySmall?.copyWith(
                        color: context.colorScheme.onSurfaceVariant,
                      ),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                  ),
                ),
                TextButton(
                  onPressed: _pickDefaultDir,
                  child: Text(context.l10n.backupPickFolder),
                ),
                if (_defaultDir != null)
                  TextButton(
                    onPressed: _clearDefaultDir,
                    child: Text(context.l10n.backupClearFolder),
                  ),
              ],
            ),
            const SizedBox(height: AppGaps.md),
            if (_busy)
              Row(
                children: [
                  const SizedBox(
                    width: AppGaps.md,
                    height: AppGaps.md,
                    child: CircularProgressIndicator(strokeWidth: 2),
                  ),
                  const SizedBox(width: AppGaps.sm),
                  Text(
                    _op == _BackupOp.backingUp
                        ? context.l10n.backupInProgress
                        : context.l10n.backupRestoreInProgress,
                    style: context.textTheme.bodyMedium,
                  ),
                ],
              )
            else
              Wrap(
                spacing: AppGaps.sm,
                runSpacing: AppGaps.sm,
                children: [
                  ConstrainedBox(
                    constraints: const BoxConstraints(minWidth: 160),
                    child: FilledButton.icon(
                      onPressed: _backupNow,
                      icon: const Icon(Icons.save_alt_outlined, size: 20),
                      label: Text(context.l10n.backupNow),
                    ),
                  ),
                  ConstrainedBox(
                    constraints: const BoxConstraints(minWidth: 160),
                    child: OutlinedButton.icon(
                      onPressed: _restore,
                      icon: const Icon(Icons.restore_outlined, size: 20),
                      label: Text(context.l10n.backupRestore),
                    ),
                  ),
                ],
              ),
          ],
        ),
      ),
    );
  }
}
