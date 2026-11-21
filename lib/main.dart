import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'app.dart';
import 'core/result/result.dart';
import 'core/log/udao_logger.dart';
import 'data/db/udao_database.dart';
import 'data/db/dao/kv_dao.dart';
import 'features/capture/capture_providers.dart';
import 'features/ai/persona/stress_detector.dart';
import 'features/khel/khel_providers.dart';
import 'features/khel/khel_service.dart';
import 'features/survival/jobs/background_jobs.dart';

/// UDAO bootstrap. Deliberately tiny — everything else is wired in
/// later phases (router shell: Phase 01, capture pipelines: Phase 03+).
void main() {
  // Platform channels are used the moment the warm-up below runs
  // (sqflite + secure-storage) — the binding must exist before any
  // of that, not just before the first widget.
  WidgetsFlutterBinding.ensureInitialized();

  // The container is created HERE (not by ProviderScope) so the
  // data-layer warm-up can seed capture BEFORE the widget tree exists
  // — WAL replay must be running even if the user never opens the app
  // past the first frame.
  final ProviderContainer container = ProviderContainer();
  unawaited(_warmUpDataLayer(container));
  runApp(
    UncontrolledProviderScope(
      container: container,
      child: const UdaoApp(),
    ),
  );
}

Future<void> _warmUpDataLayer(ProviderContainer container) async {
  try {
    await UdaoDatabase.instance.db;
  } on Object catch (e, s) {
    udaoLog.error('data-layer warm-up failed', error: e);
    udaoLog.fatal('warm-up stack', error: s);
    return;
  }
  // DB is warm: push the allowlist, replay the WAL, start the live
  // daemon. Never throws (bootstrapCapture swallows), never blocks
  // first frame — capture health is observable from the gate screen
  // and settings.
  try {
    await bootstrapCapture(container);
  } on Object catch (e, s) {
    udaoLog.error('capture bootstrap failed', error: e);
    udaoLog.fatal('capture bootstrap stack', error: s);
  }
  // Phase 07: judge completed Khel days — AFTER the WAL replay so
  // yesterday's late-captured spends count before the streak rules.
  // Idempotent; a failure never blocks boot.
  try {
    final Result<KhelEvaluation> khel =
        await container.read(khelServiceProvider).evaluate();
    if (khel is Err<KhelEvaluation>) {
      udaoLog.warn('khel evaluate failed: ${khel.failureOrNull}');
    }
  } on Object catch (e, s) {
    udaoLog.error('khel evaluate failed', error: e);
    udaoLog.fatal('khel evaluate stack', error: s);
  }
  // Phase 05: arm the workmanager jobs (nightly sweep + weekly gap).
  // Idempotent (KEEP policies); failures never block the app. Not
  // called from widget tests — main() itself never runs there.
  await initializeBackgroundJobs();
  // Phase 06: stamp today's open for the stress detector (14d vs
  // 14d app-open comparison). Best-effort — never blocks boot.
  try {
    await stampAppOpenDay(KvDao(UdaoDatabase.instance.db));
  } on Object catch (e) {
    udaoLog.warn('app-open stamp failed: $e');
  }
}
