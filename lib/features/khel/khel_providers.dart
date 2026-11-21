// phase-07
// Riverpod wiring for Khel. The service depends on repos that hang
// off the shared DB provider; the screen loads one snapshot per
// visit (no spinners — see the Aaj/Ledger note about fake-async).
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:udao/data/repos/providers.dart';

import '../capture/capture_providers.dart' show kvDaoProvider, txnDaoProvider;
import 'khel_service.dart';

final Provider<KhelService> khelServiceProvider = Provider<KhelService>(
  (Ref ref) => KhelService(
    streaks: ref.watch(streakRepoProvider),
    khel: ref.watch(khelRepoProvider),
    txns: ref.watch(txnDaoProvider),
    kv: ref.watch(kvDaoProvider),
  ),
);
