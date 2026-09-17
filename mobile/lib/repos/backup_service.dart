import 'dart:io';

import 'package:path/path.dart' as p;
import 'package:shared_preferences/shared_preferences.dart';
import 'package:sqflite/sqflite.dart';

import 'package:i_gen/db.dart';

/// File-level backup/restore for the local SQLite database (service layer,
/// no UI).
///
/// The live database file is identified by [dbPath]; [db] is only used for
/// the WAL checkpoint before a backup. This class never closes or reopens
/// the live handle — the caller owns the [Database] lifecycle.
class BackupService {
  BackupService({
    required this.db,
    required this.dbPath,
    required this.appDocDir,
  });

  final Database db;
  final String dbPath;
  final String appDocDir;

  /// [SharedPreferences] key stamping the last successful auto-backup.
  static const String lastAutoBackupKey = 'backup_last_auto_ms';

  /// [SharedPreferences] key for the auto-backup interval in days.
  /// `0` (or missing→default) disables/sets the cadence; unset means weekly.
  static const String autoIntervalDaysKey = 'backup_interval_days';

  /// Default auto-backup cadence (days) when the user never chose one.
  static const int defaultAutoIntervalDays = 7;

  /// [SharedPreferences] key for the user-chosen default backup folder.
  /// Unset means "ask every time" on manual backup.
  static const String defaultDirKey = 'backup_default_dir';

  /// Effective auto-backup cadence from [autoIntervalDaysKey]
  /// (default [defaultAutoIntervalDays]); null when the user turned it off.
  static Duration? autoIntervalFor(SharedPreferences prefs) {
    final days = prefs.getInt(autoIntervalDaysKey) ?? defaultAutoIntervalDays;
    return days <= 0 ? null : Duration(days: days);
  }

  /// How many `auto-backup-*.db` files are kept in [appDocDir].
  static const int maxAutoBackups = 3;

  /// Opens [path] read-only and runs `PRAGMA integrity_check`, returning the
  /// open handle (ownership transfers to the caller, which must close it).
  ///
  /// Any failure — unreadable file, failed check — is reported as a
  /// [StateError] prefixed with [origin] (`'Backup copy'` / `'Invalid backup
  /// file'`), so both copy verification and pre-restore validation share one
  /// shape instead of two hand-rolled blocks.
  static Future<Database> _openChecked(
    String path, {
    required String origin,
  }) async {
    Database? db;
    try {
      db = await openDatabase(path, readOnly: true);
      final rows = await db.rawQuery('PRAGMA integrity_check');
      final result = rows.isEmpty ? '<empty>' : '${rows.first.values.first}';
      if (result.toLowerCase() != 'ok') {
        throw StateError('$origin "$path" failed integrity_check: $result.');
      }
      final opened = db;
      db = null;
      return opened;
    } catch (e) {
      await db?.close();
      if (e is StateError) rethrow;
      throw StateError('$origin "$path" is not a readable database ($e).');
    }
  }

  /// Copies the live database file to [targetPath], then opens the copy
  /// read-only and runs `PRAGMA integrity_check`.
  ///
  /// If the copy fails the check it is deleted and a [StateError] is thrown;
  /// the live database is never modified.
  Future<void> backupToFile(String targetPath) async {
    if (p.equals(File(targetPath).absolute.path, File(dbPath).absolute.path)) {
      throw ArgumentError('Backup target must differ from the live db path.');
    }
    await db.execute('PRAGMA wal_checkpoint(TRUNCATE)');
    final target = File(targetPath);
    await target.parent.create(recursive: true);
    await File(dbPath).copy(targetPath);
    Database? copy;
    try {
      copy = await _openChecked(targetPath, origin: 'Backup copy');
    } catch (_) {
      if (await target.exists()) {
        await target.delete();
      }
      rethrow;
    } finally {
      await copy?.close();
    }
  }

  /// Throws a [StateError] with a clear message unless [path] is a readable
  /// SQLite database with `integrity_check == 'ok'` and a `user_version`
  /// between 1 and [DbProvider.dbVersion] (inclusive).
  ///
  /// Only [path] is opened (read-only); the live database is never touched.
  static Future<void> validateBackupFile(String path) async {
    final checked = await _openChecked(path, origin: 'Invalid backup file');
    try {
      final versionRows = await checked.rawQuery('PRAGMA user_version');
      final version = versionRows.isEmpty
          ? 0
          : (versionRows.first.values.first as int? ?? 0);
      if (version < 1 || version > DbProvider.dbVersion) {
        throw StateError(
          'Invalid backup file "$path": schema version $version is outside '
          'the supported range 1–${DbProvider.dbVersion}.',
        );
      }
    } finally {
      await checked.close();
    }
  }

  /// Replaces the live database file with the validated backup at
  /// [backupPath].
  ///
  /// The current live file (if any) is renamed to `<dbPath>.pre-restore`
  /// first — any older fallback is deleted, so exactly one fallback is kept —
  /// then the backup is copied over [dbPath]. Stale `-wal`/`-shm`/`-journal`
  /// sidecars of the old live file are removed so they cannot shadow the
  /// restored content.
  ///
  /// Contract for the caller (this method never touches the [Database]
  /// handle): close the database BEFORE calling (the file swap fails on an
  /// open handle, on Windows in particular), then reopen via
  /// `DbProvider.open(dbPath)` — pending migrations run there — and trigger
  /// a sync so the server converges on the restored state.
  Future<void> restoreFromFile(String backupPath) async {
    if (p.equals(File(backupPath).absolute.path, File(dbPath).absolute.path)) {
      throw ArgumentError('Backup path must differ from the live db path.');
    }
    await validateBackupFile(backupPath);
    final live = File(dbPath);
    final fallback = File('$dbPath.pre-restore');
    if (await fallback.exists()) {
      await fallback.delete();
    }
    for (final suffix in ['-wal', '-shm', '-journal']) {
      final sidecar = File('${fallback.path}$suffix');
      if (await sidecar.exists()) {
        await sidecar.delete();
      }
    }
    if (await live.exists()) {
      await live.rename(fallback.path);
    }
    for (final suffix in ['-wal', '-shm', '-journal']) {
      final sidecar = File('$dbPath$suffix');
      if (await sidecar.exists()) {
        await sidecar.delete();
      }
    }
    await File(backupPath).copy(dbPath);
  }

  /// When the last successful auto-backup was taken, or null if never.
  Future<DateTime?> lastAutoBackupAt(SharedPreferences prefs) async {
    final ms = prefs.getInt(lastAutoBackupKey);
    return ms == null ? null : DateTime.fromMillisecondsSinceEpoch(ms);
  }

  /// Writes `<appDocDir>/auto-backup-<stamp>.db` via [backupToFile]
  /// when auto-backup is enabled and no stamp exists or the last one is older
  /// than the chosen cadence, then prunes auto-backups to the newest
  /// [maxAutoBackups] and stamps [lastAutoBackupKey].
  ///
  /// Does nothing when disabled (`0`) or still fresh. Failures leave
  /// the stamp untouched so the next launch retries.
  Future<void> maybeAutoBackup(SharedPreferences prefs) async {
    final interval = autoIntervalFor(prefs);
    if (interval == null) {
      return;
    }
    final now = DateTime.now();
    final last = await lastAutoBackupAt(prefs);
    if (last != null && now.difference(last) < interval) {
      return;
    }
    final target = p.join(appDocDir, 'auto-backup-${fileStamp(now)}.db');
    await backupToFile(target);
    await _pruneAutoBackups();
    await prefs.setInt(lastAutoBackupKey, now.millisecondsSinceEpoch);
  }

  /// Filename stamp (`yyyyMMdd-HHmmss`, sortable). Shared by auto-backups
  /// and the manual share-sheet backup so the format lives in one place.
  /// Pass [now] in tests for determinism.
  static String fileStamp([DateTime? now]) {
    final time = now ?? DateTime.now();
    String two(int v) => v.toString().padLeft(2, '0');
    return '${time.year}${two(time.month)}${two(time.day)}-'
        '${two(time.hour)}${two(time.minute)}${two(time.second)}';
  }

  Future<void> _pruneAutoBackups() async {
    final dir = Directory(appDocDir);
    if (!await dir.exists()) {
      return;
    }
    final backups = <File>[];
    await for (final entity in dir.list()) {
      if (entity is File) {
        final name = p.basename(entity.path);
        if (name.startsWith('auto-backup-') && name.endsWith('.db')) {
          backups.add(entity);
        }
      }
    }
    // Oldest first by filesystem mtime (not filename: robust to any future
    // stamp-format change), filename as the deterministic tiebreak, then
    // delete past the keep limit.
    final mtimes = <File, DateTime>{};
    for (final file in backups) {
      mtimes[file] = (await file.stat()).modified;
    }
    backups.sort((a, b) {
      final byTime = mtimes[a]!.compareTo(mtimes[b]!);
      return byTime != 0 ? byTime : a.path.compareTo(b.path);
    });
    while (backups.length > maxAutoBackups) {
      await backups.removeAt(0).delete();
    }
  }
}
