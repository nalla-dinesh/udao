// phase-02
// The encrypted ledger connection — single instance, SQLCipher-keyed
// in production, WAL-journaled, FK-enforced.
//
// **Schema single source of truth:** every schema touch (create,
// upgrade, downgrade) routes through the static hooks [onConfigure],
// [onCreate], [onUpgrade] — production (`sqflite_sqlcipher`) and
// tests (`sqflite_common_ffi`, unencrypted `:memory:`) run byte-identical
// DDL because both factories re-export the same `sqflite_common`
// types. No drift is possible by construction.
import 'package:flutter/foundation.dart' show visibleForTesting;
import 'package:sqflite_sqlcipher/sqflite.dart';
import 'package:udao/core/errors/failure.dart';
import 'package:udao/core/log/udao_logger.dart';
import 'package:udao/data/db/db_key_store.dart';
import 'package:udao/data/db/migrations.dart';
import 'package:udao/data/db/schema.dart';
import 'package:udao/data/models/category.dart';

class UdaoDatabase {
  UdaoDatabase._(Future<Database> Function() open, {required this.encrypted})
      : _open = open;

  /// Test constructor: wrap any opener (typically `databaseFactoryFfi`
  /// over `inMemoryDatabasePath`). Schema hooks stay identical.
  @visibleForTesting
  UdaoDatabase.forTesting(Future<Database> Function() open)
      : this._(open, encrypted: false);

  final Future<Database> Function() _open;

  /// True when the connection is SQLCipher-encrypted (production).
  /// Test builds use plain sqlite via `sqflite_common_ffi`.
  final bool encrypted;

  static UdaoDatabase? _instance;

  /// Production singleton (cipher on).
  static UdaoDatabase get instance =>
      _instance ??= UdaoDatabase._(_openProduction, encrypted: true);

  /// Test hook: an unencrypted connection over a caller-provided
  /// factory/opener (typically `databaseFactoryFfi` on an in-memory
  /// path). The schema hooks stay identical.
  @visibleForTesting
  static void injectForTesting(UdaoDatabase database) {
    _instance = database;
  }

  /// Drops any injected/production instance (test teardown).
  @visibleForTesting
  static void resetInstance() {
    _instance = null;
  }

  Future<Database>? _opened;

  /// The lazily-opened shared handle.
  Future<Database> get db => _opened ??= _open();

  /// Closes and forgets the current handle (tests, wipe flows).
  Future<void> close() async {
    final Future<Database>? pending = _opened;
    _opened = null;
    if (pending != null) {
      try {
        final Database database = await pending;
        await database.close();
      } on Object catch (e) {
        udaoLog.warn('udao db close failed: $e');
      }
    }
  }

  // ------------------------------------------------------------------
  // Static schema hooks — shared by production AND test connections.
  // ------------------------------------------------------------------

  /// Pragmas applied to every connection. `cipher_page_size` is a
  /// no-op on plain sqlite (unknown pragmas are silently ignored),
  /// which is exactly what the FFI test path wants.
  static Future<void> onConfigure(Database db) async {
    await db.rawQuery('PRAGMA cipher_page_size = 4096');
    await db.rawQuery('PRAGMA journal_mode = WAL');
    await db.rawQuery('PRAGMA foreign_keys = ON');
  }

  /// Bootstrap: full DDL + 16 seed categories, one batch.
  static Future<void> onCreate(Database db, int version) async {
    final Batch batch = db.batch();
    for (final String ddl in UdaoSchema.createTables) {
      batch.execute(ddl);
    }
    for (final String idx in UdaoSchema.createIndexes) {
      batch.execute(idx);
    }
    for (final Category category in kSeedCategories) {
      batch.insert('category', category.toRow());
    }
    await batch.commit(noResult: true);
  }

  /// Walks registered migration steps (see [UdaoMigrations.run]).
  static Future<void> onUpgrade(
    Database db,
    int oldVersion,
    int newVersion,
  ) async {
    await UdaoMigrations.run(db, from: oldVersion, to: newVersion);
  }

  /// Downgrades are refused loudly — see [UdaoMigrations.refuseDowngrade].
  static Future<void> onDowngrade(
    Database db,
    int oldVersion,
    int newVersion,
  ) async {
    await UdaoMigrations.refuseDowngrade(db, oldVersion, newVersion);
  }

  /// Production-only `onOpen`: prove cipher is live. An empty
  /// `cipher_version` on the production path means the binary lacks
  /// SQLCipher — the DB is sitting in plaintext. We log an error and
  /// keep running (DB stays usable; the user is told in Settings).
  static Future<void> logCipherHealth(Database db) async {
    try {
      final List<Map<String, Object?>> rows =
          await db.rawQuery('PRAGMA cipher_version');
      final String? version = rows.isEmpty ? null : rows.first.values.first as String?;
      if (version == null || version.isEmpty) {
        udaoLog.error('cipher_version EMPTY — SQLCipher not active!');
      } else {
        udaoLog.info('SQLCipher active: $version');
      }
    } on Object catch (e) {
      udaoLog.warn('cipher_version probe failed: $e');
    }
  }

  // ------------------------------------------------------------------
  // Operations
  // ------------------------------------------------------------------

  /// Wipes every ledger row (DPDP "delete my data"). Categories are
  /// reseeded — the app keeps working; `streak_state` is reset to
  /// initial. VACUUM afterwards so purged pages don't linger in the file.
  Future<void> wipeAll() async {
    final Database db = await this.db;
    try {
      final Batch batch = db.batch();
      for (final String table in UdaoSchema.wipeOrder) {
        batch.execute('DELETE FROM $table');
      }
      for (final Category category in kSeedCategories) {
        batch.insert('category', category.toRow());
      }
      await batch.commit(noResult: true);
      await db.execute('VACUUM');
    } on Object catch (e) {
      throw DatabaseFailure('wipeAll failed', cause: e);
    }
  }

  /// The production connection: encrypted file DB, migrations wired,
  /// cipher health probed on open.
  static Future<Database> _openProduction() async {
    final String dir = await getDatabasesPath();
    final String key = await DbKeyStore.ensureDbKey();
    return openDatabase(
      '$dir/udao.db',
      password: key,
      version: UdaoSchema.dbVersion,
      onConfigure: UdaoDatabase.onConfigure,
      onCreate: UdaoDatabase.onCreate,
      onUpgrade: UdaoDatabase.onUpgrade,
      onDowngrade: UdaoDatabase.onDowngrade,
      onOpen: UdaoDatabase.logCipherHealth,
    );
  }
}
