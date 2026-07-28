/// A smoke test: does the app start, and does it tell a new user what to do?
///
/// The detailed reward maths is covered in `engine_test.dart`. This file only
/// checks that the screens build without throwing.
library;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart' show rootBundle;
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:card_optimizer/main.dart';

void main() {
  setUp(() {
    // Gives the test a clean, empty phone storage to work against.
    SharedPreferences.setMockInitialValues({});

    // `rootBundle` is a global cache shared by every test in this file, and it
    // holds on to the Future created the first time an asset was read. Each
    // test runs in its own fake-time zone, so a second test awaiting that
    // leftover Future would wait forever and the screen would sit on its
    // loading spinner. Clearing the cache gives each test a fresh read.
    rootBundle.clear();
  });

  testWidgets('starts on the recommendation tab and prompts for cards',
      (tester) async {
    await tester.pumpWidget(const CardOptimizerApp());
    await tester.pumpAndSettle();

    expect(find.text('Card Optimizer'), findsOneWidget);

    // With no cards saved yet, the user should be told to add some.
    expect(find.text('Add your cards first'), findsOneWidget);
  });

  testWidgets('the My cards tab groups cards by issuing bank', (tester) async {
    await tester.pumpWidget(const CardOptimizerApp());
    await tester.pumpAndSettle();

    await tester.tap(find.text('My cards'));
    await tester.pumpAndSettle();

    // Banks are listed; individual cards stay tucked away until asked for.
    expect(find.text('SBI Card'), findsOneWidget);
    expect(find.text('HDFC Bank'), findsOneWidget);
    expect(find.text('Axis Bank'), findsOneWidget);
    expect(find.text('SBI Card Cashback SBI Card'), findsNothing);

    await tester.tap(find.text('SBI Card'));
    await tester.pumpAndSettle();

    expect(find.text('SBI Card Cashback SBI Card'), findsOneWidget);
    expect(find.byType(CheckboxListTile), findsWidgets);
  });

  testWidgets('search finds a card without opening any bank group',
      (tester) async {
    await tester.pumpWidget(const CardOptimizerApp());
    await tester.pumpAndSettle();

    await tester.tap(find.text('My cards'));
    await tester.pumpAndSettle();

    await tester.enterText(find.byKey(const Key('card-search')), 'atlas');
    await tester.pumpAndSettle();

    // The matching card appears directly; the bank groups get out of the way.
    expect(find.widgetWithText(CheckboxListTile, 'Axis Bank Atlas'),
        findsOneWidget);
    expect(find.text('HDFC Bank'), findsNothing);

    // Ticking from search results works like ticking from the group view.
    await tester.tap(find.widgetWithText(CheckboxListTile, 'Axis Bank Atlas'));
    await tester.pumpAndSettle();

    await tester.enterText(find.byKey(const Key('card-search')), '');
    await tester.pumpAndSettle();
    expect(find.text('HDFC Bank'), findsOneWidget);
    expect(find.textContaining('1 of'), findsOneWidget); // Axis shows it
  });

  testWidgets('the whole journey: add cards, price a purchase, see a winner',
      (tester) async {
    // The default test window is 800x600, which is shorter than the card list.
    // Flutter only builds the list rows that are on screen, so off-screen
    // cards cannot be found or tapped. A taller window keeps the test about
    // the app's behaviour rather than about scrolling.
    tester.view.physicalSize = const Size(1000, 1600);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);

    await tester.pumpWidget(const CardOptimizerApp());
    await tester.pumpAndSettle();

    // --- add two cards -----------------------------------------------------
    await tester.tap(find.text('My cards'));
    await tester.pumpAndSettle();

    // Open each bank and tick its card, one bank at a time. The bank has to be
    // scrolled to first: with a hundred cards, expanding HDFC pushes every
    // later bank off the screen, and a widget that is off-screen cannot be
    // tapped even though it exists.
    for (final entry in const {
      'HDFC Bank': 'HDFC Bank Swiggy ORNGE',
      'Axis Bank': 'Axis Bank ACE',
    }.entries) {
      await tester.ensureVisible(find.text(entry.key));
      await tester.pumpAndSettle();
      await tester.tap(find.text(entry.key));
      await tester.pumpAndSettle();

      final tile = find.widgetWithText(CheckboxListTile, entry.value);
      await tester.ensureVisible(tile);
      await tester.pumpAndSettle();
      await tester.tap(tile);
      await tester.pumpAndSettle();

      // Collapse again so the next bank stays reachable.
      await tester.ensureVisible(find.text(entry.key));
      await tester.pumpAndSettle();
      await tester.tap(find.text(entry.key));
      await tester.pumpAndSettle();
    }

    // --- price a Rs 1,000 Swiggy order -------------------------------------
    await tester.tap(find.text('Which card?'));
    await tester.pumpAndSettle();

    // Food delivery is the screen's starting category, so we only set the
    // amount. 1,000 is above the Rs 249 minimum for the accelerated rate.
    await tester.enterText(find.byType(TextField).first, '1000');
    await tester.pumpAndSettle();

    // Swiggy ORNGE pays 5% on Swiggy = Rs 50. Axis ACE pays its base 1.5%
    // here, because its 4% food-delivery rate needs a named merchant = Rs 15.
    expect(find.text('₹50'), findsOneWidget);
    expect(find.text('₹15'), findsOneWidget);

    // The winner is marked with a trophy, and it should be the Swiggy card.
    final winner = tester.widget<ExpansionTile>(find.byType(ExpansionTile).first);
    expect(
      find.descendant(
        of: find.byWidget(winner),
        matching: find.text('HDFC Bank Swiggy ORNGE'),
      ),
      findsOneWidget,
      reason: 'the Swiggy card should rank first for a Swiggy order',
    );

    // --- and now a Rs 200 order, below the Rs 249 minimum ------------------
    await tester.enterText(find.byType(TextField).first, '200');
    await tester.pumpAndSettle();

    // Swiggy ORNGE drops to its 1% ordinary rate: Rs 2.
    // Axis ACE still pays 1.5%: Rs 3. So the ranking flips.
    expect(find.text('₹3'), findsOneWidget);
    expect(find.text('₹2'), findsOneWidget);

    final smallWinner =
        tester.widget<ExpansionTile>(find.byType(ExpansionTile).first);
    expect(
      find.descendant(
        of: find.byWidget(smallWinner),
        matching: find.text('Axis Bank ACE'),
      ),
      findsOneWidget,
      reason: 'below the minimum, the Swiggy card should lose to Axis ACE',
    );
  });
}
