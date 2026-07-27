/// Tests for the drawn mock card pictures.
library;

import 'dart:convert';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:card_optimizer/models/rules.dart';
import 'package:card_optimizer/widgets/card_art.dart';

late Rules rules;

Widget wrap(Widget child) => MaterialApp(home: Scaffold(body: Center(child: child)));

void main() {
  setUpAll(() {
    final raw = File('assets/rules.json').readAsStringSync();
    rules = Rules.fromJson(json.decode(raw) as Map<String, dynamic>);
  });

  testWidgets('every card in the dataset draws without throwing',
      (tester) async {
    for (final card in rules.cards) {
      await tester.pumpWidget(wrap(CardArt(card: card)));
      expect(find.byType(CardArt), findsOneWidget,
          reason: '${card.id} failed to draw');
    }
  });

  testWidgets('a card keeps the real 85.6 x 54 mm proportions', (tester) async {
    await tester.pumpWidget(
      wrap(CardArt(card: rules.cardById('axis-ace')!, width: 158.6)),
    );

    final size = tester.getSize(find.byType(CardArt));
    expect(size.width, 158.6);
    expect(size.height, closeTo(100, 0.5));
  });

  testWidgets('the name appears at large sizes and not at thumbnail size',
      (tester) async {
    final card = rules.cardById('axis-atlas')!;

    await tester.pumpWidget(wrap(CardArt(card: card, width: 200)));
    expect(find.text('ATLAS'), findsOneWidget);

    // At row-thumbnail size text would be an unreadable smudge, so it is
    // dropped rather than rendered too small to read.
    await tester.pumpWidget(wrap(CardArt(card: card, width: 52)));
    expect(find.text('ATLAS'), findsNothing);
  });

  testWidgets('a screen reader hears the card name, not "image"',
      (tester) async {
    final handle = tester.ensureSemantics();
    await tester.pumpWidget(
      wrap(CardArt(card: rules.cardById('sbi-cashback')!)),
    );

    expect(
      find.bySemanticsLabel('SBI Card Cashback SBI Card'),
      findsOneWidget,
    );
    handle.dispose();
  });

  group('colours', () {
    test('co-branded cards take their partner\'s colour, not the bank\'s', () {
      // Both are HDFC cards, but nobody thinks of them as HDFC cards, and two
      // identical blue rectangles in a list would be no help at all.
      final swiggy = CardPalette.forCard(rules.cardById('swiggy-ornge-hdfc')!);
      final blck = CardPalette.forCard(rules.cardById('swiggy-blck-hdfc')!);
      final millennia = CardPalette.forCard(rules.cardById('hdfc-millennia')!);

      expect(swiggy.start, isNot(millennia.start));
      expect(blck.start, isNot(millennia.start));
      expect(swiggy.start, isNot(blck.start));
    });

    test('cards without a partner fall back to their bank\'s colour', () {
      final millennia = CardPalette.forCard(rules.cardById('hdfc-millennia')!);
      expect(millennia.start, const Color(0xFF00579B));
    });

    test('every card gets a distinguishable palette', () {
      // Not all unique - two plain Axis cards may share the bank colour - but
      // there should be real variety rather than one colour for everything.
      final starts =
          rules.cards.map((c) => CardPalette.forCard(c).start).toSet();
      expect(starts.length, greaterThanOrEqualTo(8));
    });
  });
}
