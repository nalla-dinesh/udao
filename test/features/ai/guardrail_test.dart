// phase-06
// The HARD guardrail: ~40 verdicts. False positives acceptable,
// false negatives NOT.
import 'package:flutter_test/flutter_test.dart';
import 'package:udao/features/ai/persona/guardrail.dart';

void main() {
  final Guardrail g = Guardrail();

  group('passes clean spend-roast lines (person NOT targeted)', () {
    const List<String> clean = <String>[
      'Bhai, Swiggy pe 1200? Zomato ka stock tumhare naam pe hai kya?',
      'Ye kharcha dekh ke wallet ne resignation de di.',
      'Shopping 3000 — shaadi hai kya is month?',
      'Netflix, Prime, Hotstar — teen OTT, ek bhi dekhi nahi.',
      '500 ka coffee? USD me soch.',
      'Aaj ka total dekh ke mera ho gaya.',
      'Subscriptions ka total nikal lo — zyada hai.',
      'EK aur order aur tum next month ramen khaoge.',
      'Budget ke andar ho — surprising, but proud of you.',
      'Ye month streak maintain ho gaya, solid.',
    ];
    for (int i = 0; i < clean.length; i++) {
      test('clean#$i', () {
        final GuardrailVerdict v = g.filter(clean[i]);
        expect(v.blocked, isFalse, reason: clean[i]);
        expect(v.text, clean[i]);
      });
    }
  });

  group('blocks slurs', () {
    const List<String> bad = <String>[
      'Tu nota hai', // mota-adjacent family? no — keep explicit ones below
      'Suar ban gaya hai kya?',
      'Fattu nikla tu budget ke saamne.',
      'Chutiya bana raha hai bank?',
      'Harami merchant ne paisa kat liya.',
      'Gandu expense tha ye.',
      'You are worthless with money.',
      'Pathetic spending, truly.',
      'What a loser move.',
      'Idiot hai kya tu?',
      'Stupid kharcha.',
    ];
    for (int i = 0; i < bad.length; i++) {
      test('slur#$i', () {
        final GuardrailVerdict v = g.filter(bad[i]);
        expect(v.blocked, isTrue, reason: bad[i]);
        expect(v.reasons, contains('slur'));
        expect(v.text, isNot(contains(bad[i].split(' ').first)));
      });
    }
  });

  group('blocks person-directed alarmism, allows spend alarmism', () {
    test('tu barbaad → blocked', () {
      expect(g.filter('Tu barbaad hai paisa uda ke').blocked, isTrue);
    });
    test('tumhara kharcha barbaad → spend-directed is fine... (regex: tumhara + barbaad fires — accepted false positive)', () {
      // "tumhara" directly followed by "barbaad" — that IS
      // person-directed phrasing. Spend-directed uses different
      // words. False-positive tolerance law documented here.
      expect(g.filter('Tumhara barbaad budget hai').blocked, isTrue);
    });
    test('spend-called-ruined without pronoun passes', () {
      expect(g.filter('Ye budget barbaad ho gaya hai').blocked, isFalse);
    });
    test('kharcha khatam passes (no pronoun)', () {
      expect(g.filter('Kharcha khatam level ka hai').blocked, isFalse);
    });
    test('aap bekaar → blocked', () {
      expect(g.filter('Aap bekaar ho').blocked, isTrue);
    });
    test('tera kharcha bekaar (pronoun+adj adjacency needed) — passes', () {
      // "tera kharcha" then "bekaar" is NOT adjacent → not alarmist.
      expect(
        g.filter('Tera kharcha bekaar hai? Nahi — but zyada hai').blocked,
        isFalse,
      );
    });
  });

  group('panic/medical triggers blocked everywhere', () {
    const List<String> bad = <String>[
      'Bhikari ban jaoge aise kharche pe',
      'Mar jaoge aise udate hue',
      'Nalayak ho gaya hai budget ke saamne',
      'Ghar baar khoge is speed se',
      'Khatam ho jaoge is mahine me',
      'Ye kharcha cancer jaisa hai',
      'Death by subscriptions',
      'Suicide season after bill',
      'Bhikh maangni padegi',
    ];
    for (int i = 0; i < bad.length; i++) {
      test('panic#$i', () {
        expect(g.filter(bad[i]).blocked, isTrue, reason: bad[i]);
      });
    }
  });

  group('essential-category screen (roast context only)', () {
    const GuardrailContext roast = GuardrailContext(isRoast: true);
    const List<String> essentials = <String>[
      'Rent pe kitna gaya is month?',
      'Kiraya bhi roast karun tera?',
      'Groceries ke kharche pe has raha hoon',
      'Sabzi pe 500? hahaha',
      'Ration ka kharcha roast-time',
      'Medical bill ka mazaak',
      'Dawai pe paisa? Funny.',
      'Hospital jaana padega is kharche se',
      'Doctor ke fees roast',
      'School fees pe joke',
      'College ka kharcha lol',
      'Padhai pe kharcha??',
      'Education loan roast',
      'Bijli ka bill dekh ke hanste hain',
      'Light bill pe meme',
    ];
    for (int i = 0; i < essentials.length; i++) {
      test('essential-roast#$i', () {
        final GuardrailVerdict v = g.filter(essentials[i], context: roast);
        expect(v.blocked, isTrue, reason: essentials[i]);
        expect(v.reasons, contains('essential-target'));
      });
    }

    test('same words PASS outside roast context (chat answers)', () {
      const GuardrailContext chat = GuardrailContext(isRoast: false);
      expect(
        g
            .filter(
              'Rent pe 12000 gaya is month — sab theek hai?',
              context: chat,
            )
            .blocked,
        isFalse,
      );
      expect(
        g.filter('Medical ka total 2000 tha.', context: chat).blocked,
        isFalse,
      );
    });
  });

  group('280-char trim', () {
    test('over-length clean line is trimmed with ellipsis, not blocked', () {
      final String long = 'A'.padRight(400, 'x');
      final GuardrailVerdict v = g.filter(long);
      expect(v.blocked, isFalse);
      expect(v.trimmed, isTrue);
      expect(v.text.length, lessThanOrEqualTo(GuardrailRules.maxChars));
      expect(v.text.endsWith('…'), isTrue);
    });

    test('exactly 280 passes untouched', () {
      final String exact = 'a' * 280;
      final GuardrailVerdict v = g.filter(exact);
      expect(v.trimmed, isFalse);
      expect(v.text, exact);
    });

    test('281 is trimmed', () {
      final String over = 'a' * 281;
      expect(g.filter(over).trimmed, isTrue);
    });
  });

  group('safe fallback templates', () {
    test('blocked output is one of the safe templates', () {
      final Set<String> seen = <String>{};
      for (int i = 0; i < 8; i++) {
        final GuardrailVerdict v = g.filter('suar kharcha');
        expect(GuardrailRules.safeTemplates, contains(v.text));
        seen.add(v.text);
      }
      // Round-robin cycles through all 4.
      expect(seen, hasLength(4));
    });

    test('safe templates themselves are clean and short', () {
      for (final String t in GuardrailRules.safeTemplates) {
        expect(t.length, lessThanOrEqualTo(GuardrailRules.maxChars));
        expect(
          g
              .filter(t, context: const GuardrailContext(isRoast: true))
              .blocked,
          isFalse,
        );
      }
    });
  });

  test('blocked wins over trim (a slur inside a long line still blocks)',
      () {
    final GuardrailVerdict v =
        g.filter('${'pad '.padRight(200, 'x')} suar ${'y'.padLeft(200, 'y')}');
    expect(v.blocked, isTrue);
    expect(v.reasons, contains('slur'));
  });

  test('multiple reasons stack', () {
    final GuardrailVerdict v =
        g.filter('Tu barbaad bhikari ban jaoge', context: const GuardrailContext(isRoast: true));
    expect(v.blocked, isTrue);
    expect(v.reasons, containsAll(<String>['alarmist', 'panic']));
  });
}
