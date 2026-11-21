// phase-06
// The roast template model. The template is the SEMANTIC FLOOR: with
// no model, slots are filled and shipped; with a model, the body is
// rewritten in persona voice keeping the slots' meaning (never the
// numbers — those come from the ledger only).
class RoastTemplate {
  const RoastTemplate({
    required this.id,
    required this.category,
    required this.intensity,
    required this.body,
    this.tags = const <String>[],
  });

  /// Stable id — persisted in roast_entry for freshness rotation.
  final String id;

  /// Template family: food-delivery | shopping | subscriptions |
  /// overspend | streak-win | month-end | salary-day | no-spend.
  final String category;

  /// 1 = light, 2 = proper, 3 = full blast (ramped by overspend %).
  final int intensity;

  /// Hinglish body with {slots}. Supported slots:
  /// {merchant} {amount} {delta} {days} {count} {streak}
  final String body;

  final List<String> tags;

  bool get targetsSpend => category != 'streak-win' && category != 'no-spend';
}

/// Slot values for one roast render.
class RoastSlots {
  const RoastSlots({
    this.merchant,
    this.amount,
    this.delta,
    this.days,
    this.count,
    this.streak,
  });

  final String? merchant;
  final String? amount;
  final String? delta;
  final String? days;
  final String? count;
  final String? streak;

  Map<String, String> get present => <String, String>{
        if (merchant != null) 'merchant': merchant!,
        if (amount != null) 'amount': amount!,
        if (delta != null) 'delta': delta!,
        if (days != null) 'days': days!,
        if (count != null) 'count': count!,
        if (streak != null) 'streak': streak!,
      };
}
