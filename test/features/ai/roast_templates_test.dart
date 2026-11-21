// phase-06
// The 60-template corpus: counts, distribution, ids, slots,
// guardrail-cleanliness, no essential words.
import 'package:flutter_test/flutter_test.dart';
import 'package:udao/features/ai/persona/guardrail.dart';
import 'package:udao/features/ai/roast/roast_template.dart';
import 'package:udao/features/ai/roast/roast_templates.dart';

void main() {
  test('exactly 60 templates', () {
    expect(RoastTemplates.all, hasLength(60));
  });

  test('category distribution matches the spec', () {
    final Map<String, int> count = <String, int>{};
    for (final RoastTemplate t in RoastTemplates.all) {
      count[t.category] = (count[t.category] ?? 0) + 1;
    }
    expect(count['food-delivery'], 12);
    expect(count['shopping'], 8);
    expect(count['subscriptions'], 8);
    expect(count['overspend'], 10);
    expect(count['streak-win'], 8);
    expect(count['month-end'], 6);
    expect(count['salary-day'], 4);
    expect(count['no-spend'], 4);
  });

  test('ids are unique and stable-shaped', () {
    final Set<String> ids = <String>{};
    for (final RoastTemplate t in RoastTemplates.all) {
      expect(t.id, matches(RegExp(r'^[a-z]+-\d{2}$')));
      ids.add(t.id);
    }
    expect(ids, hasLength(60));
  });

  test('intensities stay in 1..3', () {
    for (final RoastTemplate t in RoastTemplates.all) {
      expect(t.intensity, inInclusiveRange(1, 3), reason: t.id);
    }
  });

  test('bodies are non-empty and within the display cap', () {
    for (final RoastTemplate t in RoastTemplates.all) {
      expect(t.body.trim().length, greaterThan(15), reason: t.id);
      // Guardrail trims at 280 — pre-filled templates with slots
      // should not blow far past it.
      expect(t.body.length, lessThan(280), reason: t.id);
    }
  });

  test('only supported slots appear in bodies', () {
    final RegExp slot = RegExp(r'\{([a-z]+)\}');
    const Set<String> allowed = <String>{
      'merchant', 'amount', 'delta', 'days', 'count', 'streak',
    };
    for (final RoastTemplate t in RoastTemplates.all) {
      for (final RegExpMatch m in slot.allMatches(t.body)) {
        expect(
          allowed,
          contains(m.group(1)),
          reason: '${t.id}: {${m.group(1)}}',
        );
      }
    }
  });

  test('templates survive the roast-context guardrail (filled)',
      () {
    final Guardrail g = Guardrail();
    const RoastSlots fill = RoastSlots(
      merchant: 'Swiggy',
      amount: 'Rs.640',
      delta: 'Rs.300',
      days: '3',
      count: '5',
      streak: '12',
    );
    for (final RoastTemplate t in RoastTemplates.all) {
      final String filled = t.body
          .replaceAll('{merchant}', fill.merchant!)
          .replaceAll('{amount}', fill.amount!)
          .replaceAll('{delta}', fill.delta!)
          .replaceAll('{days}', fill.days!)
          .replaceAll('{count}', fill.count!)
          .replaceAll('{streak}', fill.streak!);
      final GuardrailVerdict v = g.filter(
        filled,
        context: const GuardrailContext(isRoast: true),
      );
      expect(
        v.blocked,
        isFalse,
        reason: '${t.id}: ${v.reasons} — "$filled"',
      );
    }
  });

  test('targetsSpend flag: wins never get model rewrites', () {
    for (final RoastTemplate t in RoastTemplates.all) {
      final bool isWin =
          t.category == 'streak-win' || t.category == 'no-spend';
      expect(t.targetsSpend, isNot(isWin), reason: t.id);
    }
  });

  test('streak-win templates carry the {streak} slot', () {
    for (final RoastTemplate t in RoastTemplates.all
        .where((RoastTemplate t) => t.category == 'streak-win')) {
      expect(t.body, contains('{streak}'), reason: t.id);
    }
  });
}
