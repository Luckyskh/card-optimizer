/// The whole reward dataset, parsed.
///
/// `assets/rules.json` has a version number, a list of spending categories and
/// a list of cards. This file turns that top level into one object.
library;

import 'card.dart';

class Rules {
  /// Bumped by hand whenever the dataset is corrected. The terms monitor
  /// records this alongside its alerts so you can tell whether an alert has
  /// already been acted on.
  final int version;

  /// The date the dataset was compiled, as written in the JSON.
  final String? generatedOn;

  /// Caveats from the dataset author.
  final String? notes;

  /// Every spending category the app knows about, e.g. `food_delivery`.
  /// The recommendation screen builds its picker from this list, so adding a
  /// category to the JSON is enough to make it appear in the app.
  final List<String> categories;

  final List<CardRule> cards;

  const Rules({
    required this.version,
    this.generatedOn,
    this.notes,
    required this.categories,
    required this.cards,
  });

  CardRule? cardById(String id) {
    for (final card in cards) {
      if (card.id == id) return card;
    }
    return null;
  }

  /// Cards the user owns, in dataset order. Unknown ids are skipped rather
  /// than throwing — a card could be removed from the dataset after someone
  /// has already added it on their phone.
  List<CardRule> cardsByIds(Set<String> ids) =>
      cards.where((card) => ids.contains(card.id)).toList();

  factory Rules.fromJson(Map<String, dynamic> json) {
    return Rules(
      version: (json['version'] as num?)?.toInt() ?? 0,
      generatedOn: json['generated_on'] as String?,
      notes: json['notes'] as String?,
      categories: (json['categories'] as List<dynamic>? ?? [])
          .whereType<String>()
          .toList(),
      cards: (json['cards'] as List<dynamic>? ?? [])
          .map((e) => CardRule.fromJson(e as Map<String, dynamic>))
          .toList(),
    );
  }
}

/// Turns a category id like `food_delivery` into "Food delivery" for display.
String prettyCategory(String category) {
  const special = {
    'upi': 'UPI',
    'other_ecommerce': 'Other online shopping',
    'mobile_dth_recharge': 'Mobile / DTH recharge',
    'travel_flights_hotels': 'Flights and hotels',
    'government_tax': 'Government and tax',
    'quick_commerce': 'Quick commerce',
    'wallet_load': 'Wallet load',
    'other': 'Everything else',
  };
  final override = special[category];
  if (override != null) return override;

  final words = category.split('_');
  final first = words.first;
  final capitalised =
      first.isEmpty ? first : first[0].toUpperCase() + first.substring(1);
  return ([capitalised, ...words.skip(1)]).join(' ');
}
