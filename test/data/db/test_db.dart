// phase-02
// Shared DB test scaffolding: a fresh in-memory sqlite per test via
// sqflite_common_ffi, wired to the SAME schema hooks production uses
// (`UdaoDatabase.onConfigure/onCreate/onUpgrade/onDowngrade`), so
// test schema and shipped schema cannot drift.
import 'package:sqflite_common_ffi/sqflite_ffi.dart';
import 'package:udao/data/db/schema.dart';
import 'package:udao/data/db/udao_database.dart';

/// Creates (and injects as the singleton) a fresh unencrypted
/// in-memory database. Call [disposeTestDb] in `tearDown`-style
/// teardown — or pass `autoReset: false` to manage manually.
///
/// Uses the NO-ISOLATE ffi factory deliberately: the default
/// `databaseFactoryFfi` proxies every call through a background
/// isolate whose replies never arrive inside `testWidgets`' fake-async
/// zone — widget flows that touch the DB then hang until
/// `pumpAndSettle` times out (sqflite_common_ffi doc/testing.md
/// recommends exactly this for widget tests; plain tests are happy
/// with it too).
Future<UdaoDatabase> createTestDb() async {
  sqfliteFfiInit();
  final UdaoDatabase db = UdaoDatabase.forTesting(
    () => databaseFactoryFfiNoIsolate.openDatabase(
      inMemoryDatabasePath,
      options: OpenDatabaseOptions(
        version: UdaoSchema.dbVersion,
        singleInstance: false,
        onConfigure: UdaoDatabase.onConfigure,
        onCreate: UdaoDatabase.onCreate,
        onUpgrade: UdaoDatabase.onUpgrade,
        onDowngrade: UdaoDatabase.onDowngrade,
      ),
    ),
  );
  UdaoDatabase.injectForTesting(db);
  // Open FULLY (pragmas + DDL + seeds) before returning.
  //
  // Widget tests run inside a fake-async zone. `UdaoDatabase.db` is a
  // LAZY future — if the first open happens from inside the widget
  // flow, the in-flight open crosses the real->fake zone boundary and
  // the chain can strand mid-pump (observed as `pumpAndSettle timed
  // out`). Pre-awaiting here means every later `await dao._db` in the
  // fake zone resolves an ALREADY-COMPLETED future — pure microtasks,
  // which pumps always flush.
  await db.db;
  if (!_announced) {
    _announced = true;
    // Freshness marker: one line per test-file isolate. If this line
    // is missing from `flutter test` output, an old tree is running.
    // ignore: avoid_print
    print('[udao-test-db] r6: no-isolate ffi, pre-opened');
  }
  return db;
}

bool _announced = false;

/// Closes [db] and clears the injected singleton.
Future<void> disposeTestDb(UdaoDatabase db) async {
  await db.close();
  UdaoDatabase.resetInstance();
}
