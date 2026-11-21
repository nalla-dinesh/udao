// phase-02
// Versioned migration framework — wired from day one, exercised every
// open: `onUpgrade` walks [steps] in order; a downgrade throws
// [DatabaseFailure] with a clear message instead of corrupting data.
import 'package:sqflite_sqlcipher/sqflite.dart' show Database;
import 'package:udao/core/errors/failure.dart';

/// One migration: bring the DB **to** version [to] from `to - 1`.
typedef MigrationStep = Future<void> Function(Database db, int fromVersion);

abstract final class UdaoMigrations {
  /// Must equal `UdaoSchema.dbVersion`.
  static const int dbVersion = 1;

  /// `steps[v]` upgrades a v-1 database to v. v1 is the bootstrap
  /// (created by `onCreate`), so the map starts empty — first real
  /// migration lands in Phase 03+.
  static const Map<int, MigrationStep> steps = <int, MigrationStep>{};

  /// Runs every step in `(from, to]` inside a transaction.
  ///
  /// Throws [DatabaseFailure] on a missing step or a downgrade — the
  /// open fails loudly, data is never silently reshaped.
  static Future<void> run(
    Database db, {
    required int from,
    required int to,
  }) async {
    if (to < from) {
      throw DatabaseFailure(
        'Downgrade refused: DB at v$from, app expects v$to. '
        'Reinstall the newer app version — a wipe is safer than guessing.',
      );
    }
    for (int v = from + 1; v <= to; v++) {
      final MigrationStep? step = steps[v];
      if (step == null) {
        throw DatabaseFailure(
          'No migration step to schema v$v — DB left at v$from, untouched.',
        );
      }
      await step(db, v - 1);
    }
  }

  /// `onDowngrade` hook — never silently accept an older schema.
  static Future<void> refuseDowngrade(
    Database db,
    int oldVersion,
    int newVersion,
  ) async {
    throw DatabaseFailure(
      'Downgrade refused: DB at v$oldVersion, app expects v$newVersion. '
      'Reinstall the newer app version — a wipe is safer than guessing.',
    );
  }
}
