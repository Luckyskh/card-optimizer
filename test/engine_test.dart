/// Tests for the six behaviours `CLAUDE.md` calls out as easy to get wrong.
///
/// Each group below corresponds to one numbered item in the project brief's
/// "Non-obvious structures the engine must handle" section. They read the real
/// `assets/rules.json`, not a fixture, so a change to the dataset that breaks
/// an assumption shows up here.
library;

import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

import 'package:card_optimizer/models/card.dart';
import 'package:card_optimizer/models/rules.dart';
import 'package:card_optimizer/engine/recommendation_engine.dart';

late Rules rules;
late RecommendationEngine engine;

CardRule card(String id) {
  final found = rules.cardById(id);
  if (found == null) throw StateError('No card "$id" in assets/rules.json');
  return found;
}

/// Rounds to paise so floating-point noise does not break comparisons.
double round2(double value) => (value * 100).round() / 100;

void main() {
  setUpAll(() {
    final raw = File('assets/rules.json').readAsStringSync();
    rules = Rules.fromJson(json.decode(raw) as Map<String, dynamic>);
    engine = RecommendationEngine(rules);
  });

  // -------------------------------------------------------------------------
  group('1. Shared caps across categories', () {
    // Axis ACE's 5% and 4% categories share ONE Rs 500 monthly ceiling.
    // Treating them as separate per-category caps overestimates badly.

    test('5% utilities is trimmed to the Rs 500 shared ceiling', () {
      final result = engine.evaluate(
        card('axis-ace'),
        const SpendRequest(category: 'utilities', amountInr: 20000),
      );

      // 5% of 20,000 would be 1,000 without the cap.
      expect(result.rupees, 500);
      expect(result.capped, isTrue);
    });

    test('spending in one shared category eats the other one\'s allowance', () {
      // Rs 400 of the Rs 500 group ceiling already used on utilities.
      final result = engine.evaluate(
        card('axis-ace'),
        const SpendRequest(
          category: 'food_delivery',
          amountInr: 5000,
          merchant: 'swiggy',
          usage: {
            'axis-ace': CardUsage(capUsageInr: {'shared:accelerated': 400}),
          },
        ),
      );

      // 4% of 5,000 is 200, but only 100 of the shared ceiling is left.
      expect(result.rupees, 100);
      expect(result.capped, isTrue);
    });

    test('the uncapped base rate is not affected by the shared ceiling', () {
      final result = engine.evaluate(
        card('axis-ace'),
        const SpendRequest(
          category: 'groceries',
          amountInr: 50000,
          usage: {
            'axis-ace': CardUsage(capUsageInr: {'shared:accelerated': 500}),
          },
        ),
      );

      // Base 1.5% on 50,000, uncapped.
      expect(result.rupees, 750);
      expect(result.capped, isFalse);
    });
  });

  // -------------------------------------------------------------------------
  group('2. Mixed cap periods', () {
    test('Flipkart Axis uses a quarterly cap, not a monthly one', () {
      final result = engine.evaluate(
        card('flipkart-axis'),
        const SpendRequest(category: 'flipkart', amountInr: 100000),
      );

      // 5% of 100,000 is 5,000; the quarterly cap is 4,000.
      expect(result.rupees, 4000);
      expect(result.capped, isTrue);
      expect(
        result.reasons.any((r) => r.contains('quarter')),
        isTrue,
        reason: 'the explanation should say the cap is quarterly',
      );
    });

    test('Myntra has its own cap, separate from Flipkart\'s', () {
      final result = engine.evaluate(
        card('flipkart-axis'),
        const SpendRequest(
          category: 'myntra',
          amountInr: 10000,
          usage: {
            'flipkart-axis': CardUsage(capUsageInr: {'cat:flipkart': 4000}),
          },
        ),
      );

      // 7.5% of 10,000 = 750, untouched by the exhausted Flipkart cap.
      expect(result.rupees, 750);
      expect(result.capped, isFalse);
    });
  });

  // -------------------------------------------------------------------------
  group('3. Minimum transaction values', () {
    test('a Rs 1,000 Swiggy order gets the full 5%', () {
      final result = engine.evaluate(
        card('swiggy-ornge-hdfc'),
        const SpendRequest(category: 'food_delivery', amountInr: 1000),
      );
      expect(result.rupees, 50);
    });

    test('a Rs 200 order falls below the Rs 249 minimum and drops to 1%', () {
      final result = engine.evaluate(
        card('swiggy-ornge-hdfc'),
        const SpendRequest(category: 'food_delivery', amountInr: 200),
      );

      expect(result.rupees, 2);
      expect(
        result.reasons.any((r) => r.contains('249')),
        isTrue,
        reason: 'the user should be told why they lost the accelerated rate',
      );
    });

    test('a Rs 50 order is below every minimum and earns nothing', () {
      final result = engine.evaluate(
        card('swiggy-ornge-hdfc'),
        const SpendRequest(category: 'food_delivery', amountInr: 50),
      );
      expect(result.rupees, 0);
    });
  });

  // -------------------------------------------------------------------------
  group('4. Conditional tiers', () {
    test('Amazon Pay ICICI pays 5% to Prime members', () {
      final result = engine.evaluate(
        card('amazon-pay-icici'),
        const SpendRequest(
          category: 'amazon',
          amountInr: 10000,
          amazonPrimeMember: true,
        ),
      );
      expect(result.rupees, 500);
    });

    test('and 3% to everyone else', () {
      final result = engine.evaluate(
        card('amazon-pay-icici'),
        const SpendRequest(
          category: 'amazon',
          amountInr: 10000,
        ),
      );
      expect(result.rupees, 300);
    });
  });

  // -------------------------------------------------------------------------
  group('5. Spend-tiered rates', () {
    // IDFC FIRST Select: 3 points per Rs 200 up to Rs 20,000 of cycle spend,
    // then 10 points per Rs 200 above it. A point is worth Rs 0.25, so the
    // two tiers are 0.375% and 1.25%.

    test('a fresh cycle earns the lower tier', () {
      final result = engine.evaluate(
        card('idfc-first-select'),
        const SpendRequest(category: 'groceries', amountInr: 10000),
      );

      expect(round2(result.rupees), 37.5); // 10,000 * 0.375%
    });

    test('a cycle already past Rs 20,000 earns the upper tier', () {
      final result = engine.evaluate(
        card('idfc-first-select'),
        const SpendRequest(
          category: 'groceries',
          amountInr: 10000,
          usage: {'idfc-first-select': CardUsage(spendThisCycleInr: 25000)},
        ),
      );

      expect(round2(result.rupees), 125); // 10,000 * 1.25%
    });

    test('a purchase straddling the threshold is split across both tiers', () {
      final result = engine.evaluate(
        card('idfc-first-select'),
        const SpendRequest(
          category: 'groceries',
          amountInr: 10000,
          usage: {'idfc-first-select': CardUsage(spendThisCycleInr: 15000)},
        ),
      );

      // 5,000 at 0.375% = 18.75, then 5,000 at 1.25% = 62.50.
      expect(round2(result.rupees), 81.25);
      expect(
        result.reasons.any((r) => r.contains('straddles')),
        isTrue,
        reason: 'the split should be explained, not silently applied',
      );
    });

    test('a category with its own rate ignores the tiers', () {
      final result = engine.evaluate(
        card('idfc-first-select'),
        const SpendRequest(category: 'dining', amountInr: 10000),
      );

      // Dining is a flat 10 points per Rs 200 = 1.25%.
      expect(round2(result.rupees), 125);
    });
  });

  // -------------------------------------------------------------------------
  group('6. Points versus cashback', () {
    test('points are converted to rupees, never compared as raw counts', () {
      final idfc = engine.evaluate(
        card('idfc-first-select'),
        const SpendRequest(category: 'dining', amountInr: 1000),
      );

      // "10X" sounds enormous. At Rs 0.25 a point it is 1.25%.
      expect(round2(idfc.effectivePct), 1.25);
      expect(round2(idfc.rupees), 12.5);
    });

    test('a 10X card can lose to a card with no accelerated rate at all', () {
      // This is the trap the brief warns about: ranking by advertised
      // multiplier rather than by rupees earned gets the answer backwards.
      final results = engine.recommend(
        [
          card('idfc-first-select'), // "10X" on dining -> 1.25%
          card('hdfc-regalia-gold'), // no dining row -> base 1.625%
          card('axis-ace'), // no dining row -> base 1.5%
        ],
        const SpendRequest(category: 'dining', amountInr: 1000),
      );

      expect(results.first.card.id, 'hdfc-regalia-gold');
      expect(results.last.card.id, 'idfc-first-select');
      expect(round2(results.first.rupees), 16.25);
    });

    test('Regalia Gold\'s base rate comes from its base_earn object', () {
      // 5 points per Rs 200, each worth Rs 0.65 -> 1.625%.
      expect(round2(card('hdfc-regalia-gold').resolvedBaseRatePct!), 1.63);
    });
  });

  // -------------------------------------------------------------------------
  // -------------------------------------------------------------------------
  group('merchants change the answer', () {
    test('naming Swiggy unlocks Axis ACE\'s 4% food delivery rate', () {
      // ACE's 4% row is limited to Swiggy, Zomato and Ola. Without a merchant
      // the engine cannot apply it and has to fall back to the base rate.
      final anywhere = engine.evaluate(
        card('axis-ace'),
        const SpendRequest(category: 'food_delivery', amountInr: 1000),
      );
      final atSwiggy = engine.evaluate(
        card('axis-ace'),
        const SpendRequest(
          category: 'food_delivery',
          amountInr: 1000,
          merchant: 'swiggy',
        ),
      );

      expect(anywhere.rupees, 15); // base 1.5%
      expect(atSwiggy.rupees, 40); // 4%
    });

    test('a merchant not on the list still gets the base rate', () {
      final atEatSure = engine.evaluate(
        card('axis-ace'),
        const SpendRequest(
          category: 'food_delivery',
          amountInr: 1000,
          merchant: 'eatsure',
        ),
      );

      expect(atEatSure.rupees, 15,
          reason: 'EatSure is not in ACE\'s merchant list, so no 4%');
    });

    test('naming Cleartrip unlocks Flipkart Axis 5% on travel', () {
      final atCleartrip = engine.evaluate(
        card('flipkart-axis'),
        const SpendRequest(
          category: 'travel_flights_hotels',
          amountInr: 10000,
          merchant: 'cleartrip',
        ),
      );

      expect(atCleartrip.rupees, 500); // 5%
    });

    test('a partner-merchant row applies outside its own category label', () {
      // HDFC Millennia files its "10 partner merchants" row under
      // other_ecommerce, but the list includes Swiggy, Uber and BookMyShow.
      // Matching on the row's category label would mean a Swiggy order never
      // saw the 5%, which is the opposite of what the card actually does.
      final atSwiggy = engine.evaluate(
        card('hdfc-millennia'),
        const SpendRequest(
          category: 'food_delivery',
          amountInr: 1000,
          merchant: 'swiggy',
        ),
      );

      expect(round2(atSwiggy.rupees), 50); // 5% partner rate

      final atEatSure = engine.evaluate(
        card('hdfc-millennia'),
        const SpendRequest(
          category: 'food_delivery',
          amountInr: 1000,
          merchant: 'eatsure',
        ),
      );

      expect(atEatSure.rupees, lessThan(50),
          reason: 'EatSure is not a Millennia partner');
    });

    test('every merchant maps to a category the dataset knows', () {
      for (final merchant in rules.merchants) {
        expect(rules.categories, contains(merchant.category),
            reason: '${merchant.id} points at unknown category '
                '"${merchant.category}"');
      }
    });

    test('merchant ids are lowercase and unique', () {
      final ids = <String>{};
      for (final merchant in rules.merchants) {
        expect(merchant.id, merchant.id.toLowerCase(),
            reason: '${merchant.id} must be lowercase to match rate rows');
        expect(ids.add(merchant.id), isTrue,
            reason: 'duplicate merchant id ${merchant.id}');
      }
    });

    test('every merchant named in a rate row exists in the directory', () {
      // Catches the silent failure where a rate row points at a merchant the
      // user can never actually pick, so the rate can never fire.
      final known = rules.merchants.map((m) => m.id).toSet();
      for (final c in rules.cards) {
        for (final row in c.categoryRates) {
          for (final named in row.merchants) {
            expect(known, contains(named),
                reason: '${c.id} names merchant "$named" in a rate row, but '
                    'it is not in the merchants directory, so a user cannot '
                    'select it and the rate can never apply');
          }
        }
      }
    });
  });

  group('exclusions and honesty about gaps', () {
    test('an excluded category earns nothing and says so', () {
      final result = engine.evaluate(
        card('sbi-cashback'),
        const SpendRequest(category: 'rent', amountInr: 30000),
      );

      expect(result.rupees, 0);
      expect(result.excluded, isTrue);
      expect(result.reasons.single, contains('exclusion list'));
    });

    test('an unquantifiable "up to 10X" is flagged, not guessed at', () {
      final result = engine.evaluate(
        card('hdfc-regalia-gold'),
        const SpendRequest(category: 'other_ecommerce', amountInr: 10000),
      );

      expect(result.uncertain, isTrue);
      expect(result.reasons.any((r) => r.contains('10X')), isTrue);
      // Falls back to the base rate rather than inventing a figure.
      expect(round2(result.rupees), 162.5);
    });

    test('a partner-merchant rate we cannot verify is disclosed', () {
      final result = engine.evaluate(
        card('amazon-pay-icici'),
        const SpendRequest(category: 'groceries', amountInr: 1000),
      );

      // Quotes the ordinary 1%, mentions the 2% partner rate.
      expect(result.rupees, 10);
      expect(result.reasons.any((r) => r.contains('partner')), isTrue);
    });

    test('every card in the dataset parses and can be evaluated', () {
      for (final c in rules.cards) {
        for (final category in rules.categories) {
          final result = engine.evaluate(
            c,
            SpendRequest(category: category, amountInr: 1000),
          );
          expect(result.rupees, greaterThanOrEqualTo(0),
              reason: '${c.id} / $category produced a negative reward');
          expect(result.rupees.isFinite, isTrue,
              reason: '${c.id} / $category produced a non-finite reward');
        }
      }
    });
  });
}
