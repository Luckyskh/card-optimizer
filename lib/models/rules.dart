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

  /// Where you can spend, e.g. Swiggy, IRCTC, BookMyShow.
  ///
  /// Naming the merchant matters: several accelerated rates only apply at
  /// specific places, and the engine cannot use those rate rows unless it is
  /// told where the money is going.
  final List<Merchant> merchants;

  const Rules({
    required this.version,
    this.generatedOn,
    this.notes,
    required this.categories,
    required this.cards,
    this.merchants = const [],
  });

  /// The merchants that fall under a category, alphabetically.
  List<Merchant> merchantsIn(String category) {
    final matching =
        merchants.where((m) => m.category == category).toList();
    matching.sort((a, b) => a.name.toLowerCase().compareTo(b.name.toLowerCase()));
    return matching;
  }

  Merchant? merchantById(String id) {
    for (final merchant in merchants) {
      if (merchant.id == id) return merchant;
    }
    return null;
  }

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
      merchants: (json['merchants'] as List<dynamic>? ?? [])
          .whereType<Map<String, dynamic>>()
          .map(Merchant.fromJson)
          .toList(),
    );
  }
}

/// A place you can spend money.
class Merchant {
  /// Lowercase, and matched against the `merchants` lists inside a card's
  /// `category_rates`. Renaming one silently disconnects it from any rate row
  /// that names it, so ids are treated as fixed.
  final String id;

  /// What the user sees, e.g. "Domino's".
  final String name;

  /// The spending category this merchant's purchases fall under.
  final String category;

  const Merchant({
    required this.id,
    required this.name,
    required this.category,
  });

  factory Merchant.fromJson(Map<String, dynamic> json) => Merchant(
        id: (json['id'] as String? ?? '').toLowerCase(),
        name: json['name'] as String? ?? '',
        category: json['category'] as String? ?? 'other',
      );
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
