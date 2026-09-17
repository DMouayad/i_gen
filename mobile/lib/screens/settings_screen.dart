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
    return DefaultTabController(
      length: 2,
      child: Scaffold(
        appBar: AppBar(
          title: Text(context.l10n.navSettings),
          actions: [
            // Locale lives here now (was the General tab): one tap toggles
            // ar/en via LocaleController; MaterialApp rebuilds on notify.
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
            _tab(
              Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  const _AuthCard(),
                  const SizedBox(height: AppGaps.xl),
                  const _InviteCard(),
                  if (kSyncStagingGatePassed) ...[
                    const SizedBox(height: AppGaps.xl),
                    const SyncStatusCard(),
                    const SizedBox(height: AppGaps.sm),
                    Text(
                      context.l10n.settingsOfflineFirstNote,
                      style: context.textTheme.bodySmall?.copyWith(
                        color: context.colorScheme.onSurfaceVariant,
                      ),
                    ),
                  ],
                ],
              ),
            ),
            _tab(
              Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: const [_BackupCard()],
              ),
            ),
          ],
        ),
      ),
    );
  }

  /// Shared tab padding: the old single-scroll body padded once at the top.
  static Widget _tab(Widget child) {
    return SingleChildScrollView(
      padding: const EdgeInsets.all(AppGaps.md),
      child: child,
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
      return Card(
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(AppRadii.card),
        ),
        child: Padding(
          padding: const EdgeInsets.all(AppGaps.md),
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
        ),
      );
    }
    return StreamBuilder(
      stream: _auth.currentUserStream,
      initialData: _auth.currentUser,
      builder: (context, snapshot) {
        final user = snapshot.data ?? _auth.currentUser;
        if (user != null) {
          return Card(
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(AppRadii.card),
            ),
            color: context.colorScheme.surfaceContainerHighest.withValues(
              alpha: 0.4,
            ),
            child: Padding(
              padding: const EdgeInsets.all(AppGaps.md),
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
            ),
          );
        }
        return Card(
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(AppRadii.card),
          ),
          child: Padding(
            padding: const EdgeInsets.all(AppGaps.md),
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
                  enabled: !_busy,
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
                  enabled: !_busy,
                ),
                if (_error != null) ...[
                  const SizedBox(height: AppGaps.sm),
                  Text(
                    _error!,
                    style: context.textTheme.bodyMedium?.copyWith(
                      color: context.colorScheme.error,
                    ),
                  ),
                ],
                const SizedBox(height: AppGaps.md),
                FilledButton(
                  style: const ButtonStyle(
                    minimumSize: WidgetStatePropertyAll(Size(64, 48)),
                  ),
                  onPressed: _busy
                      ? null
                      : () => _run(
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
                  onPressed: _busy ? null : _showInviteSheet,
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

/// Manual backup (share sheet) + restore-from-file + auto-backup status.
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

  /// Saves a timestamped `.db` to the default folder (or a one-off folder
  /// picked now when none is set), then toasts the path. No share sheet:
  /// the folder IS the destination.
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

  Future<void> _setInterval(int? days) async {
    if (days == null) return;
    final prefs = await SharedPreferences.getInstance();
    await prefs.setInt(BackupService.autoIntervalDaysKey, days);
    await _loadStatus();
  }

  /// Picks a `.db` file, validates it before touching live data, confirms
  /// the replacement when unsynced changes exist, then swaps + re-seats
  /// the database and triggers a post-restore sync.
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
    return Card(
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(AppRadii.card),
      ),
      child: Padding(
        padding: const EdgeInsets.all(AppGaps.md),
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
            const SizedBox(height: AppGaps.md),
            Row(
              children: [
                Expanded(child: Text(context.l10n.backupInterval)),
                DropdownButton<int>(
                  value: _intervalDays,
                  items: [
                    DropdownMenuItem(
                      value: 0,
                      child: Text(context.l10n.backupIntervalOff),
                    ),
                    DropdownMenuItem(
                      value: 1,
                      child: Text(context.l10n.backupIntervalDaily),
                    ),
                    DropdownMenuItem(
                      value: 7,
                      child: Text(context.l10n.backupIntervalWeekly),
                    ),
                    DropdownMenuItem(
                      value: 30,
                      child: Text(context.l10n.backupIntervalMonthly),
                    ),
                  ],
                  onChanged: _busy ? null : _setInterval,
                ),
              ],
            ),
            const SizedBox(height: AppGaps.sm),
            Row(
              children: [
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(context.l10n.backupLocation),
                      Text(
                        _defaultDir ?? context.l10n.backupNoLocation,
                        style: context.textTheme.bodySmall?.copyWith(
                          color: context.colorScheme.onSurfaceVariant,
                        ),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                      ),
                    ],
                  ),
                ),
                TextButton(
                  onPressed: _busy ? null : _pickDefaultDir,
                  child: Text(context.l10n.backupPickFolder),
                ),
                if (_defaultDir != null)
                  TextButton(
                    onPressed: _busy ? null : _clearDefaultDir,
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
              Row(
                children: [
                  Expanded(
                    child: FilledButton.icon(
                      onPressed: _backupNow,
                      icon: const Icon(Icons.save_alt_outlined, size: 20),
                      label: Text(context.l10n.backupNow),
                    ),
                  ),
                  const SizedBox(width: AppGaps.sm),
                  Expanded(
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
  bool _expanded = false;
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
      setState(() => _error = context.l10n.unexpectedError('$e'));
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
            : context.l10n.loginPreview(
                InviteService.slugPreview(_nameEn.text),
              );
        return Card(
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(AppRadii.card),
          ),
          child: Padding(
            padding: const EdgeInsets.all(AppGaps.md),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                InkWell(
                  borderRadius: BorderRadius.circular(AppRadii.control),
                  onTap: () => setState(() => _expanded = !_expanded),
                  child: Padding(
                    padding: const EdgeInsets.symmetric(vertical: AppGaps.xs),
                    child: Row(
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
                        AnimatedRotation(
                          turns: _expanded ? 0.5 : 0,
                          duration: const Duration(milliseconds: 200),
                          child: Icon(
                            Icons.expand_more_outlined,
                            color: context.colorScheme.onSurfaceVariant,
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
                if (!_expanded) ...[
                  const SizedBox(height: AppGaps.xs),
                  Text(
                    context.l10n.inviteUsersHint,
                    style: context.textTheme.bodySmall?.copyWith(
                      color: context.colorScheme.onSurfaceVariant,
                    ),
                  ),
                  const SizedBox(height: AppGaps.md),
                  FilledButton.icon(
                    style: const ButtonStyle(
                      minimumSize: WidgetStatePropertyAll(Size(64, 48)),
                    ),
                    onPressed: () => setState(() => _expanded = true),
                    icon: const Icon(Icons.add, size: 20),
                    label: Text(switch (_mode) {
                      InviteMode.invite => context.l10n.createInviteLink,
                      InviteMode.resend => context.l10n.resendInviteLink,
                      InviteMode.recovery => context.l10n.sendPasswordResetLink,
                    }),
                  ),
                ],
                AnimatedCrossFade(
                  firstChild: const SizedBox.shrink(),
                  secondChild: Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      const SizedBox(height: AppGaps.xs),
                      Text(
                        context.l10n.inviteUsersHint,
                        style: context.textTheme.bodySmall?.copyWith(
                          color: context.colorScheme.onSurfaceVariant,
                        ),
                      ),
                      const SizedBox(height: AppGaps.md),
                      TextField(
                        controller: _nameAr,
                        decoration: InputDecoration(
                          labelText: context.l10n.nameArabicLabel,
                          border: OutlineInputBorder(
                            borderRadius: BorderRadius.circular(
                              AppRadii.control,
                            ),
                          ),
                        ),
                        enabled: !_busy,
                      ),
                      const SizedBox(height: AppGaps.sm),
                      TextField(
                        controller: _nameEn,
                        decoration: InputDecoration(
                          labelText: context.l10n.nameEnglishLabel,
                          border: OutlineInputBorder(
                            borderRadius: BorderRadius.circular(
                              AppRadii.control,
                            ),
                          ),
                        ),
                        enabled: !_busy,
                        onChanged: (_) => setState(() {}),
                      ),
                      if (slugHint.isNotEmpty) ...[
                        const SizedBox(height: AppGaps.xs),
                        Text(slugHint, style: context.textTheme.bodySmall),
                      ],
                      const SizedBox(height: AppGaps.sm),
                      TextField(
                        controller: _phone,
                        keyboardType: TextInputType.phone,
                        decoration: InputDecoration(
                          labelText: context.l10n.phoneWhatsappLabel,
                          prefixIcon: const Icon(
                            Icons.phone_outlined,
                            size: 20,
                          ),
                          border: OutlineInputBorder(
                            borderRadius: BorderRadius.circular(
                              AppRadii.control,
                            ),
                          ),
                        ),
                        enabled: !_busy,
                      ),
                      const SizedBox(height: AppGaps.md),
                      Row(
                        children: [
                          Expanded(
                            child: DropdownButtonFormField<UserRole>(
                              initialValue: _role,
                              decoration: InputDecoration(
                                labelText: context.l10n.roleFieldLabel,
                                border: OutlineInputBorder(
                                  borderRadius: BorderRadius.circular(
                                    AppRadii.control,
                                  ),
                                ),
                              ),
                              items: [
                                DropdownMenuItem(
                                  value: UserRole.employee,
                                  child: Text(context.l10n.roleEmployee),
                                ),
                                DropdownMenuItem(
                                  value: UserRole.distributor,
                                  child: Text(context.l10n.roleDistributor),
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
                          const SizedBox(width: AppGaps.sm),
                          Expanded(
                            child: DropdownButtonFormField<InviteMode>(
                              initialValue: _mode,
                              decoration: InputDecoration(
                                labelText: context.l10n.inviteActionLabel,
                                border: OutlineInputBorder(
                                  borderRadius: BorderRadius.circular(
                                    AppRadii.control,
                                  ),
                                ),
                              ),
                              items: [
                                DropdownMenuItem(
                                  value: InviteMode.invite,
                                  child: Text(context.l10n.inviteModeNew),
                                ),
                                DropdownMenuItem(
                                  value: InviteMode.resend,
                                  child: Text(context.l10n.inviteModeResend),
                                ),
                                DropdownMenuItem(
                                  value: InviteMode.recovery,
                                  child: Text(context.l10n.inviteModeRecovery),
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
                        const SizedBox(height: AppGaps.sm),
                        Text(
                          _error!,
                          style: context.textTheme.bodyMedium?.copyWith(
                            color: context.colorScheme.error,
                          ),
                        ),
                      ],
                      if (_result != null) ...[
                        const SizedBox(height: AppGaps.sm),
                        SelectableText(
                          context.l10n.loginEmailLabel(_result!.fakeEmail),
                        ),
                        const SizedBox(height: AppGaps.xs),
                        SelectableText(_result!.actionLink),
                        const SizedBox(height: AppGaps.sm),
                        OutlinedButton.icon(
                          style: const ButtonStyle(
                            minimumSize: WidgetStatePropertyAll(Size(64, 48)),
                          ),
                          onPressed: () {
                            Clipboard.setData(
                              ClipboardData(
                                text: context.l10n.inviteShareText(
                                  _result!.fakeEmail,
                                  _result!.actionLink,
                                ),
                              ),
                            );
                            ScaffoldMessenger.of(context).showSnackBar(
                              SnackBar(
                                content: Text(context.l10n.inviteCopiedHint),
                              ),
                            );
                          },
                          icon: const Icon(Icons.copy_outlined),
                          label: Text(context.l10n.copyForWhatsapp),
                        ),
                      ],
                      const SizedBox(height: AppGaps.md),
                      FilledButton(
                        style: const ButtonStyle(
                          minimumSize: WidgetStatePropertyAll(Size(64, 48)),
                        ),
                        onPressed: _busy ? null : _send,
                        child: _busy
                            ? const SizedBox(
                                width: AppGaps.md,
                                height: AppGaps.md,
                                child: CircularProgressIndicator(
                                  strokeWidth: 2,
                                ),
                              )
                            : Text(switch (_mode) {
                                InviteMode.invite =>
                                  context.l10n.createInviteLink,
                                InviteMode.resend =>
                                  context.l10n.resendInviteLink,
                                InviteMode.recovery =>
                                  context.l10n.sendPasswordResetLink,
                              }),
                      ),
                    ],
                  ),
                  crossFadeState: _expanded
                      ? CrossFadeState.showSecond
                      : CrossFadeState.showFirst,
                  duration: const Duration(milliseconds: 200),
                ),
              ],
            ),
          ),
        );
      },
    );
  }
}
