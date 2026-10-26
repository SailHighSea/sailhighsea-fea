import 'dart:convert';

import 'package:cryptography/cryptography.dart';
import 'package:drift/drift.dart';
import 'package:file_picker/file_picker.dart';
import 'package:file_selector/file_selector.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/db/app_database.dart';
import '../../core/db/tables.dart' show localHouseholdId;

/// What a backup file contains or what a restore did.
class BackupCounts {
  const BackupCounts({
    this.expenses = 0,
    this.categories = 0,
    this.budgets = 0,
    this.goals = 0,
    this.bills = 0,
    this.rules = 0,
  });

  final int expenses, categories, budgets, goals, bills, rules;

  int get total => expenses + categories + budgets + goals + bills + rules;
}

class BackupFailure implements Exception {
  const BackupFailure(this.message);
  final String message;
  @override
  String toString() => message;
}

const _format = 'family-expenses-backup';
const _version = 1;
const _encryptedFormat = 'family-expenses-backup-encrypted';

/// PBKDF2 rounds for a new password-protected backup. The number used is stored in the file.
const defaultBackupKdfRounds = 150000;
const _maxKdfRounds = 2000000;

/// A backup is one JSON file with everything that lives on this device: expenses, categories,
/// budgets, goals (and what was added to them), bills and the remembered shop categories. Nothing
/// is sent anywhere: the file goes where the person puts it. Amounts stay integer cents.
class BackupService {
  BackupService(
    this._db, {
    required this.currencyCode,
    DateTime Function()? clock,
    this.householdId = localHouseholdId,
    this.kdfRounds = defaultBackupKdfRounds,
  }) : _clock = clock ?? DateTime.now;

  final AppDatabase _db;
  final String currencyCode;
  final String householdId;
  final DateTime Function() _clock;
  final int kdfRounds;

  /// The backup as text. With a [password] the text is encrypted (AES-256-GCM, key from the
  /// password with PBKDF2-HMAC-SHA256 and a random salt); without it, plain JSON.
  Future<String> export({String? password}) async {
    final json = await _plainExport();
    if (password == null || password.isEmpty) return json;
    return encryptBackup(json, password, rounds: kdfRounds);
  }

  Future<String> _plainExport() async {
    List<Map<String, Object?>> rows<T extends DataClass>(List<T> list) => [
      for (final r in list)
        Map<String, Object?>.from((r as dynamic).toJson() as Map),
    ];
    final doc = {
      'format': _format,
      'version': _version,
      'createdAt': _clock().toUtc().toIso8601String(),
      'currency': currencyCode,
      'categories': rows(
        await (_db.select(
          _db.categories,
        )..where((c) => c.deletedAt.isNull())).get(),
      ),
      'expenses': rows(
        await (_db.select(
          _db.expenses,
        )..where((e) => e.deletedAt.isNull())).get(),
      ),
      'budgets': rows(
        await (_db.select(
          _db.budgets,
        )..where((b) => b.deletedAt.isNull() & b.userId.isNull())).get(),
      ),
      'goals': rows(
        await (_db.select(_db.goals)..where((g) => g.deletedAt.isNull())).get(),
      ),
      'goalContributions': rows(
        await (_db.select(
          _db.goalContributions,
        )..where((c) => c.deletedAt.isNull())).get(),
      ),
      'bills': rows(
        await (_db.select(_db.bills)..where((b) => b.deletedAt.isNull())).get(),
      ),
      'categoryRules': rows(await _db.select(_db.categoryRules).get()),
    };
    return const JsonEncoder.withIndent('  ').convert(doc);
  }

  /// Whether [text] is a password-protected backup (it must be decrypted before use).
  static bool isEncrypted(String text) {
    try {
      final doc = jsonDecode(text);
      return doc is Map && doc['format'] == _encryptedFormat;
    } catch (_) {
      return false;
    }
  }

  /// The plain backup inside an encrypted one. A wrong password and a damaged file both fail
  /// the same way, because AES-GCM cannot tell them apart.
  static Future<String> decryptBackup(String text, String password) =>
      _decrypt(text, password);

  /// Reads a backup and says what is in it, without changing anything.
  BackupCounts inspect(String text) {
    final doc = _parse(text);
    int n(String k) => (doc[k] as List?)?.length ?? 0;
    return BackupCounts(
      expenses: n('expenses'),
      categories: n('categories'),
      budgets: n('budgets'),
      goals: n('goals'),
      bills: n('bills'),
      rules: n('categoryRules'),
    );
  }

  Map<String, dynamic> _parse(String text) {
    final Object? doc;
    try {
      doc = jsonDecode(text);
    } catch (_) {
      throw const BackupFailure('That file is not a Family Expenses backup.');
    }
    if (doc is! Map<String, dynamic> || doc['format'] != _format) {
      throw const BackupFailure('That file is not a Family Expenses backup.');
    }
    if (doc['version'] is! int || (doc['version'] as int) > _version) {
      throw const BackupFailure(
        'This backup was made by a newer version of the app. Update the app and try again.',
      );
    }
    return doc;
  }

  /// Puts the backup's data back. Rows are matched by id; a row is only replaced when the backup's
  /// copy is newer, so restoring never undoes newer work, and nothing is deleted. Everything
  /// restored belongs to this household and is marked for syncing.
  Future<BackupCounts> restore(String text) async {
    final doc = _parse(text);
    List<Map<String, dynamic>> list(String k) => [
      for (final r in (doc[k] as List? ?? const []))
        Map<String, dynamic>.from(r as Map),
    ];
    var cats = 0, exps = 0, buds = 0, gs = 0, bs = 0, ru = 0;
    try {
      await _db.transaction(() async {
        for (final j in list('categories')) {
          final row = CategoryRow.fromJson(j);
          final old = await (_db.select(
            _db.categories,
          )..where((c) => c.id.equals(row.id))).getSingleOrNull();
          if (old != null && !row.updatedAt.isAfter(old.updatedAt)) continue;
          await _db
              .into(_db.categories)
              .insertOnConflictUpdate(
                row.copyWith(
                  householdId: householdId,
                  dirty: true,
                  deletedAt: const Value(null),
                ),
              );
          cats++;
        }
        final known = {
          for (final c in await _db.select(_db.categories).get()) c.id,
        };
        for (final j in list('expenses')) {
          final row = ExpenseRow.fromJson(j);
          final old = await (_db.select(
            _db.expenses,
          )..where((e) => e.id.equals(row.id))).getSingleOrNull();
          if (old != null && !row.updatedAt.isAfter(old.updatedAt)) continue;
          if (row.amountCents <= 0) continue;
          await _db
              .into(_db.expenses)
              .insertOnConflictUpdate(
                row.copyWith(
                  householdId: householdId,
                  categoryId: known.contains(row.categoryId)
                      ? row.categoryId
                      : 'default-other',
                  dirty: true,
                  deletedAt: const Value(null),
                ),
              );
          exps++;
        }
        for (final j in list('budgets')) {
          final row = BudgetRow.fromJson(j);
          final old = await (_db.select(
            _db.budgets,
          )..where((b) => b.id.equals(row.id))).getSingleOrNull();
          if (old != null && !row.updatedAt.isAfter(old.updatedAt)) continue;
          await _db
              .into(_db.budgets)
              .insertOnConflictUpdate(
                row.copyWith(
                  householdId: householdId,
                  dirty: true,
                  deletedAt: const Value(null),
                ),
              );
          buds++;
        }
        for (final j in list('goals')) {
          final row = GoalRow.fromJson(j);
          final old = await (_db.select(
            _db.goals,
          )..where((g) => g.id.equals(row.id))).getSingleOrNull();
          if (old != null && !row.updatedAt.isAfter(old.updatedAt)) continue;
          await _db
              .into(_db.goals)
              .insertOnConflictUpdate(
                row.copyWith(
                  householdId: householdId,
                  dirty: true,
                  deletedAt: const Value(null),
                ),
              );
          gs++;
        }
        for (final j in list('goalContributions')) {
          final row = GoalContributionRow.fromJson(j);
          final old = await (_db.select(
            _db.goalContributions,
          )..where((c) => c.id.equals(row.id))).getSingleOrNull();
          if (old != null && !row.updatedAt.isAfter(old.updatedAt)) continue;
          await _db
              .into(_db.goalContributions)
              .insertOnConflictUpdate(
                row.copyWith(
                  householdId: householdId,
                  dirty: true,
                  deletedAt: const Value(null),
                ),
              );
        }
        for (final j in list('bills')) {
          final row = BillRow.fromJson(j);
          final old = await (_db.select(
            _db.bills,
          )..where((b) => b.id.equals(row.id))).getSingleOrNull();
          if (old != null && !row.updatedAt.isAfter(old.updatedAt)) continue;
          await _db
              .into(_db.bills)
              .insertOnConflictUpdate(
                row.copyWith(
                  householdId: householdId,
                  dirty: true,
                  deletedAt: const Value(null),
                ),
              );
          bs++;
        }
        for (final j in list('categoryRules')) {
          final row = CategoryRuleRow.fromJson(j);
          final old = await (_db.select(
            _db.categoryRules,
          )..where((r) => r.key.equals(row.key))).getSingleOrNull();
          if (old != null && !row.updatedAt.isAfter(old.updatedAt)) continue;
          await _db.into(_db.categoryRules).insertOnConflictUpdate(row);
          ru++;
        }
      });
    } on BackupFailure {
      rethrow;
    } on Object {
      // A damaged file: the transaction was rolled back, nothing changed.
      throw const BackupFailure('That backup is damaged. Nothing was changed.');
    }
    return BackupCounts(
      expenses: exps,
      categories: cats,
      budgets: buds,
      goals: gs,
      bills: bs,
      rules: ru,
    );
  }
}

Future<SecretKey> _key(String password, List<int> salt, int rounds) => Pbkdf2(
  macAlgorithm: Hmac.sha256(),
  iterations: rounds,
  bits: 256,
).deriveKeyFromPassword(password: password, nonce: salt);

/// Encrypts a plain backup with [password]. Public for tests; the app calls
/// [BackupService.export].
Future<String> encryptBackup(
  String plain,
  String password, {
  int rounds = defaultBackupKdfRounds,
}) async {
  final algo = AesGcm.with256bits();
  final salt = SecretKeyData.random(length: 16).bytes;
  final key = await _key(password, salt, rounds);
  final box = await algo.encrypt(utf8.encode(plain), secretKey: key);
  return jsonEncode({
    'format': _encryptedFormat,
    'version': 1,
    'kdf': 'pbkdf2-hmac-sha256',
    'rounds': rounds,
    'cipher': 'aes-256-gcm',
    'salt': base64.encode(salt),
    'nonce': base64.encode(box.nonce),
    'data': base64.encode(box.cipherText),
    'mac': base64.encode(box.mac.bytes),
  });
}

Future<String> _decrypt(String text, String password) async {
  try {
    final doc = jsonDecode(text) as Map<String, dynamic>;
    if (doc['format'] != _encryptedFormat) throw const FormatException();
    final rounds = doc['rounds'] as int;
    if (rounds < 1 || rounds > _maxKdfRounds) throw const FormatException();
    final key = await _key(
      password,
      base64.decode(doc['salt'] as String),
      rounds,
    );
    final box = SecretBox(
      base64.decode(doc['data'] as String),
      nonce: base64.decode(doc['nonce'] as String),
      mac: Mac(base64.decode(doc['mac'] as String)),
    );
    final plain = await AesGcm.with256bits().decrypt(box, secretKey: key);
    return utf8.decode(plain);
  } on Object {
    throw const BackupFailure('Wrong password, or the backup file is damaged.');
  }
}

/// Writes a backup where the person chooses (a save dialog: Files on a phone, the file manager
/// on a computer). Returns whether it was saved; false when they cancelled.
/// How many PBKDF2 rounds a new encrypted backup uses (tests lower it to run fast).
final backupKdfRoundsProvider = Provider<int>((ref) => defaultBackupKdfRounds);

typedef BackupSaver = Future<bool> Function(String filename, Uint8List bytes);

final backupSaverProvider = Provider<BackupSaver>(
  (ref) => (filename, bytes) async {
    final saved = await FilePicker.saveFile(
      fileName: filename,
      bytes: bytes,
      mimeType: 'application/json',
      dialogTitle: 'Save your backup',
    );
    return saved != null;
  },
);

/// Opens a file chooser for a backup; returns its text, or null when cancelled.
typedef BackupFilePicker = Future<String?> Function();

final backupFilePickerProvider = Provider<BackupFilePicker>(
  (ref) => () async {
    // Any file: some phones hide a file whose type they do not know.
    final file = await openFile();
    return file?.readAsString();
  },
);
