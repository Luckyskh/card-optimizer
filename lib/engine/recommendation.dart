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

  /// How many points or miles this purchase earns, when the card pays in
  /// something other than rupees. Null for cashback cards, where [rupees] is
  /// already the whole story.
  ///
  /// Shown alongside [rupees] rather than instead of it. "50 NeuCoins" is what
  /// the card actually gives you and what your statement will say; "₹50" is
  /// what it is worth and what the ranking is based on. Showing only the first
  /// invites the "10X rewards!" mistake; showing only the second hides what
  /// you actually earned.
  final double? pointsEarned;

  /// What those points are called — "NeuCoins", "EDGE Miles", "Reward Points".
  final String? pointCurrency;

  const Recommendation({
    required this.card,
    required this.rupees,
    required this.effectivePct,
    required this.headline,
    this.reasons = const [],
    this.capped = false,
    this.excluded = false,
    this.uncertain = false,
    this.pointsEarned,
    this.pointCurrency,
  });

  /// True when this card pays in points or miles rather than rupees.
  bool get paysInPoints => pointsEarned != null && pointCurrency != null;

  /// "50 NeuCoins", "325 Reward Points", "20 EDGE Miles".
  ///
  /// Whole units only, because that is how they are credited — you do not get
  /// two thirds of a point.
  String? get formattedPoints {
    if (!paysInPoints) return null;
    final whole = pointsEarned!.floor();
    return '$whole $pointCurrency';
  }

  /// "₹100" or "₹12.50" — whole rupees when it divides evenly, else 2 decimals.
  String get formattedRupees {
    if (rupees == rupees.roundToDouble()) {
      return '₹${rupees.round()}';
    }
    return '₹${rupees.toStringAsFixed(2)}';
  }

  String get formattedPct => '${effectivePct.toStringAsFixed(2)}%';
}
