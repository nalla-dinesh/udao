// phase-08
// Budget feature wiring — one service provider; the screen refreshes
// itself off the ledger event stream (same pattern as Aaj/Khel).
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../data/repos/providers.dart'
    show budgetRepoProvider, categoryRepoProvider;
import 'budget_service.dart';

final Provider<BudgetService> budgetServiceProvider = Provider<BudgetService>(
  (Ref ref) => BudgetService(
    budgets: ref.watch(budgetRepoProvider),
    categories: ref.watch(categoryRepoProvider),
  ),
);
