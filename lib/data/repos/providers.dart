// phase-02
// Riverpod wiring: one DB provider, repo providers on top. Repos are
// cheap singletons — the heavy object (the database) is shared.
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:udao/data/db/udao_database.dart';
import 'package:udao/data/repos/ledger_repo.dart';
import 'package:udao/data/repos/pending_review_repo.dart';
import 'package:udao/data/repos/query_repos.dart';

/// The encrypted ledger. Opening (key fetch + migration) happens on
/// first read — `main.dart` warms it up at boot.
final Provider<UdaoDatabase> udaoDatabaseProvider =
    Provider<UdaoDatabase>((Ref ref) => UdaoDatabase.instance);

final Provider<LedgerRepo> ledgerRepoProvider = Provider<LedgerRepo>(
  (Ref ref) => LedgerRepo(ref.watch(udaoDatabaseProvider)),
);

final Provider<PendingReviewRepo> pendingReviewRepoProvider =
    Provider<PendingReviewRepo>(
      (Ref ref) => PendingReviewRepo(ref.watch(udaoDatabaseProvider)),
    );

final Provider<CategoryRepo> categoryRepoProvider = Provider<CategoryRepo>(
  (Ref ref) => CategoryRepo(ref.watch(udaoDatabaseProvider)),
);

final Provider<BudgetRepo> budgetRepoProvider = Provider<BudgetRepo>(
  (Ref ref) => BudgetRepo(ref.watch(udaoDatabaseProvider)),
);

final Provider<SubscriptionRepo> subscriptionRepoProvider =
    Provider<SubscriptionRepo>(
      (Ref ref) => SubscriptionRepo(ref.watch(udaoDatabaseProvider)),
    );

final Provider<StreakRepo> streakRepoProvider = Provider<StreakRepo>(
  (Ref ref) => StreakRepo(ref.watch(udaoDatabaseProvider)),
);

final Provider<RoastRepo> roastRepoProvider = Provider<RoastRepo>(
  (Ref ref) => RoastRepo(ref.watch(udaoDatabaseProvider)),
);

final Provider<JarRepo> jarRepoProvider = Provider<JarRepo>(
  (Ref ref) => JarRepo(ref.watch(udaoDatabaseProvider)),
);

final Provider<CaptureHealthRepo> captureHealthRepoProvider =
    Provider<CaptureHealthRepo>(
      (Ref ref) => CaptureHealthRepo(ref.watch(udaoDatabaseProvider)),
    );

final Provider<KhelRepo> khelRepoProvider = Provider<KhelRepo>(
  (Ref ref) => KhelRepo(ref.watch(udaoDatabaseProvider)),
);
