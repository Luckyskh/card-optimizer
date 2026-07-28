/// Tests for the transfer partners tab.
///
/// The behaviour that matters is the filtering: the tab must show the user's
/// own cards and nothing else. A list of every issuer's partners is a research
/// document, not a tool.
library;

import 'dart:convert';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart' show rootBundle;
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:card_optimizer/main.dart';
import 'package:card_optimizer/models/card.dart';
import 'package:card_optimizer/models/rules.dart';

late Rules rules;

void main() {
  setUpAll(() {
    rules = Rules.fromJson(
        json.decode(File('assets/rules.json').readAsStringSync())
            as Map<String, dynamic>);
  });

  setUp(() => rootBundle.clear());

  group('parsing', () {
    test('Atlas transfer groups come through with ratios and caps', () {
      final atlas = rules.cardById('axis-atlas')!;
      final transfers = atlas.transferPartners!;

      expect(transfers.groups, hasLength(2));

      final a = transfers.groups.firstWhere((g) => g.name == 'group_a');
      expect(a.ratio, '1:2');
      expect(a.multiplier, 2);
      expect(a.annualCapMiles, 30000);
      expect(a.partners, contains('Singapore KrisFlyer'));

      final b = transfers.groups.firstWhere((g) => g.name == 'group_b');
      expect(b.annualCapMiles, 120000);
    });

    test('removed partners are kept, not dropped', () {
      // The history is the point: a programme that has already lost three
      // partners overnight says something about the ones still listed.
      final transfers = rules.cardById('axis-atlas')!.transferPartners!;

      expect(transfers.removed, contains('Marriott Bonvoy'));
      expect(transfers.removed, contains('Accor Live Limitless'));
      expect(transfers.removedOn, '2026-04-02');
    });

    test('a card with no transfer programme reports none', () {
      expect(rules.cardById('sbi-cashback')!.transferPartners, isNull);
    });

    test('an unparseable ratio yields no multiplier rather than a guess', () {
      const group = TransferGroupTestDouble();
      expect(group.parsed('1:2'), 2);
      expect(group.parsed('2:1'), 0.5);
      expect(group.parsed('5:4'), 0.8);
      expect(group.parsed('varies'), isNull);
      expect(group.parsed(null), isNull);
    });
  });

  group('the tab filters to the cards you hold', () {
    testWidgets('prompts when no cards are added', (tester) async {
      SharedPreferences.setMockInitialValues({});
      await tester.pumpWidget(const CardOptimizerApp());
      await tester.pumpAndSettle();

      await tester.tap(find.text('Transfers'));
      await tester.pumpAndSettle();

      expect(find.text('Add your cards first'), findsOneWidget);
    });

    testWidgets('says so when your cards have no transfer programme',
        (tester) async {
      SharedPreferences.setMockInitialValues({
        'owned_card_ids': ['sbi-cashback', 'axis-ace'],
      });
      await tester.pumpWidget(const CardOptimizerApp());
      await tester.pumpAndSettle();

      await tester.tap(find.text('Transfers'));
      await tester.pumpAndSettle();

      expect(find.text('None of your cards transfer points'), findsOneWidget);
      // And must not show Atlas's partners, which the user does not hold.
      expect(find.text('Singapore KrisFlyer'), findsNothing);
    });

    testWidgets('shows partners only for the card you own', (tester) async {
      tester.view.physicalSize = const Size(1000, 1800);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);

      SharedPreferences.setMockInitialValues({
        'owned_card_ids': ['axis-atlas', 'sbi-cashback'],
      });
      await tester.pumpWidget(const CardOptimizerApp());
      await tester.pumpAndSettle();

      await tester.tap(find.text('Transfers'));
      await tester.pumpAndSettle();

      expect(find.text('Axis Bank Atlas'), findsOneWidget);
      expect(find.text('Singapore KrisFlyer'), findsOneWidget);

      // The cashback card is owned but has no programme, so it is absent
      // rather than listed as empty.
      expect(find.text('SBI Card Cashback SBI Card'), findsNothing);

      // Removed partners are surfaced.
      expect(find.textContaining('Marriott Bonvoy'), findsWidgets);
    });
  });
}

/// Exercises the ratio parsing without needing a full group each time.
class TransferGroupTestDouble {
  const TransferGroupTestDouble();

  double? parsed(String? ratio) =>
      TransferGroup(name: 'g', ratio: ratio).multiplier;
}
