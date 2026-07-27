/// The answer the engine gives for one card.
library;

import '../models/card.dart';

/// What one of the user's cards would earn on one specific purchase.
///
/// [rupees] is the number that matters and the number we rank on. Percentages
/// and point counts are shown alongside it, but never compared directly — a
/// card paying "10 points per Rs 200" may be worth less than a 1% cashback
/// card once the point value is taken into account.
class Recommendation {
  final CardRule card;

  /// Rupees of value earned on this purchase, after caps and minimums.
  final double rupees;

  /// [rupees] expressed as a percentage of the purchase amount.
  final double effectivePct;

  /// One short line for the card row, e.g. "5% back on Swiggy orders".
  final String headline;

  /// Plain-language explanations, shown when the row is expanded. These exist
  /// because a beginner should be able to see *why* a card won or lost, not
  /// just that it did.
  final List<String> reasons;

  /// True when a cap stopped this purchase earning its full rate.
  final bool capped;

  /// True when the category earns nothing at all on this card.
  final bool excluded;

  /// True when the dataset could not give a firm number — for example Regalia
  /// Gold's "up to 10X on SmartBuy", which has no single value. The app shows
  /// these cards with a caveat rather than guessing a rate.
  final bool uncertain;

  const Recommendation({
    required this.card,
    required this.rupees,
    required this.effectivePct,
    required this.headline,
    this.reasons = const [],
    this.capped = false,
    this.excluded = false,
    this.uncertain = false,
  });

  /// "₹100" or "₹12.50" — whole rupees when it divides evenly, else 2 decimals.
  String get formattedRupees {
    if (rupees == rupees.roundToDouble()) {
      return '₹${rupees.round()}';
    }
    return '₹${rupees.toStringAsFixed(2)}';
  }

  String get formattedPct => '${effectivePct.toStringAsFixed(2)}%';
}
