/// Dart versions of the things described in `assets/rules.json`.
///
/// Think of this file as the translation layer. `rules.json` is plain text;
/// these classes turn that text into objects the rest of the app can use
/// without re-reading the file or guessing at spellings.
///
/// A rule of thumb used everywhere below: if a number is missing from the JSON
/// it stays `null` here. We never substitute a made-up default, because a
/// wrong reward rate is worse than an admitted gap.
library;

/// One row inside a card's `category_rates` list.
///
/// A row answers "when you spend on X, what do you earn?" — but the JSON
/// expresses that answer in four different ways depending on the card, so most
/// fields here are null most of the time.
class CategoryRate {
  /// Which spending category this row applies to, e.g. `food_delivery`.
  /// The special value `other` means "anything not matched by another row".
  final String category;

  /// Human-readable description from the JSON, e.g. "All online spends".
  final String? label;

  /// Some rows only apply at named merchants, e.g. Axis ACE's 4% is only for
  /// Swiggy, Zomato and Ola. Empty means the row applies to the whole category.
  final List<String> merchants;

  /// Straight cashback percentage, e.g. 5.0 for "5% back".
  final double? ratePct;

  /// Amazon Pay ICICI pays different rates to Prime and non-Prime members,
  /// so it uses this pair instead of [ratePct].
  final double? ratePctPrime;
  final double? ratePctNonPrime;

  /// Points-earning cards express the rate as "N points per Rs 200 spent".
  final double? pointsPer200;

  /// Miles-earning cards (Axis Atlas) use "N miles per Rs 100 spent".
  final double? milesPer100;

  /// Some rows pre-compute the percentage. We prefer to calculate it ourselves
  /// so the maths is visible, but we keep this to cross-check.
  final double? effectivePct;

  /// Marketing text like "10X" or "up to 10X". Deliberately NOT parsed into a
  /// number: "up to 10X" has no single value, and inventing one would mislead.
  final String? multiplier;

  /// Caps limit how much you can earn. A card may use any one of these.
  final double? monthlyCapInr;
  final double? quarterlyCapInr;
  final double? monthlyCapPoints;

  /// Below this transaction amount the accelerated rate does not apply at all.
  /// A Rs 150 Swiggy order on a card with a Rs 249 minimum earns the base rate.
  final double? minTransactionInr;

  /// When several rows share one ceiling, they all name the same group here and
  /// the card's `shared_caps` list holds the actual limit. Axis ACE does this:
  /// its 5% and 4% categories share a single Rs 500 monthly cap.
  final String? sharedCapGroup;

  /// Free-text caveat from the JSON, shown to the user as-is.
  final String? note;

  /// Fields the dataset author has not verified against an issuer document.
  final List<String> unverified;

  const CategoryRate({
    required this.category,
    this.label,
    this.merchants = const [],
    this.ratePct,
    this.ratePctPrime,
    this.ratePctNonPrime,
    this.pointsPer200,
    this.milesPer100,
    this.effectivePct,
    this.multiplier,
    this.monthlyCapInr,
    this.quarterlyCapInr,
    this.monthlyCapPoints,
    this.minTransactionInr,
    this.sharedCapGroup,
    this.note,
    this.unverified = const [],
  });

  /// True when this row names no usable number anywhere.
  ///
  /// Regalia Gold has rows like `{"category": "utilities", "monthly_cap_points": 2000}`
  /// which cap the base rate rather than setting a new one, and
  /// `{"multiplier": "up to 10X"}` which cannot be turned into a percentage.
  /// The engine treats these as "use the card's base rate, and say why".
  bool get hasNoOwnRate =>
      ratePct == null &&
      ratePctPrime == null &&
      ratePctNonPrime == null &&
      pointsPer200 == null &&
      milesPer100 == null;

  factory CategoryRate.fromJson(Map<String, dynamic> json) {
    return CategoryRate(
      category: json['category'] as String? ?? 'other',
      label: json['label'] as String?,
      merchants: _stringList(json['merchants']),
      ratePct: _toDouble(json['rate_pct']),
      ratePctPrime: _toDouble(json['rate_pct_prime']),
      ratePctNonPrime: _toDouble(json['rate_pct_non_prime']),
      pointsPer200: _toDouble(json['points_per_200']),
      milesPer100: _toDouble(json['miles_per_100']),
      effectivePct: _toDouble(json['effective_pct']),
      multiplier: json['multiplier'] as String?,
      monthlyCapInr: _toDouble(json['monthly_cap_inr']),
      quarterlyCapInr: _toDouble(json['quarterly_cap_inr']),
      monthlyCapPoints: _toDouble(json['monthly_cap_points']),
      minTransactionInr: _toDouble(json['min_transaction_inr']),
      sharedCapGroup: json['shared_cap_group'] as String?,
      note: json['note'] as String?,
      unverified: _stringList(json['_verify']),
    );
  }
}

/// A ceiling shared by several [CategoryRate] rows at once.
class SharedCap {
  final String group;
  final double? monthlyCapInr;
  final double? quarterlyCapInr;
  final String? note;

  const SharedCap({
    required this.group,
    this.monthlyCapInr,
    this.quarterlyCapInr,
    this.note,
  });

  factory SharedCap.fromJson(Map<String, dynamic> json) => SharedCap(
        group: json['group'] as String? ?? '',
        monthlyCapInr: _toDouble(json['monthly_cap_inr']),
        quarterlyCapInr: _toDouble(json['quarterly_cap_inr']),
        note: json['note'] as String?,
      );
}

/// HDFC Regalia Gold describes its base rate as an object rather than a plain
/// percentage: 5 points per Rs 200. Other cards use `base_rate_pct` instead.
class BaseEarn {
  final double? points;
  final double? perSpendInr;
  final double? effectivePct;
  final String? previous;

  const BaseEarn({
    this.points,
    this.perSpendInr,
    this.effectivePct,
    this.previous,
  });

  factory BaseEarn.fromJson(Map<String, dynamic> json) => BaseEarn(
        points: _toDouble(json['points']),
        perSpendInr: _toDouble(json['per_spend_inr']),
        effectivePct: _toDouble(json['effective_pct']),
        previous: json['previous'] as String?,
      );
}

/// Everything the app knows about one credit card.
///
/// Note what is absent: no card number, no expiry, no CVV, no name on card.
/// The app identifies a card purely by its product name, which is what keeps
/// this project out of payment-card compliance scope entirely.
class CardRule {
  final String id;
  final String bank;
  final String name;
  final List<String> network;

  final double? annualFee;
  final double? feeWaiverAnnualSpend;
  final bool lifetimeFree;

  /// `cashback`, `points` or `miles`.
  final String rewardType;

  /// What one point or mile is worth in rupees. This is the number that makes
  /// different cards comparable — see [CardRule.pointValueInr] usage in the
  /// engine. A card offering "4 points per Rs 150" where a point is worth
  /// Rs 0.25 is earning 0.67%, not "4x rewards".
  final double pointValueInr;
  final String? pointCurrency;

  final double? baseRatePct;
  final BaseEarn? baseEarn;

  final List<CategoryRate> categoryRates;
  final List<SharedCap> sharedCaps;

  /// A final ceiling across every category on the card.
  final double? totalMonthlyCapInr;
  final double? maxAnnualCashbackInr;

  /// Categories that earn nothing at all on this card.
  final List<String> exclusions;

  /// Set when the card's rate depends on something about the user rather than
  /// the purchase — currently only Amazon Prime membership.
  final String? conditionalCondition;
  final String? conditionalNote;

  final String? lastChanged;
  final String? changeSummary;
  final String? lastVerified;

  /// Card-level fields the dataset author flagged as unchecked.
  final List<String> unverified;

  const CardRule({
    required this.id,
    required this.bank,
    required this.name,
    this.network = const [],
    this.annualFee,
    this.feeWaiverAnnualSpend,
    this.lifetimeFree = false,
    required this.rewardType,
    required this.pointValueInr,
    this.pointCurrency,
    this.baseRatePct,
    this.baseEarn,
    this.categoryRates = const [],
    this.sharedCaps = const [],
    this.totalMonthlyCapInr,
    this.maxAnnualCashbackInr,
    this.exclusions = const [],
    this.conditionalCondition,
    this.conditionalNote,
    this.lastChanged,
    this.changeSummary,
    this.lastVerified,
    this.unverified = const [],
  });

  /// "HDFC Bank Millennia" — what the user actually sees in a list.
  String get displayName => '$bank $name';

  /// The card's fallback percentage, whichever way the JSON expressed it.
  /// Returns null when the dataset genuinely does not say.
  double? get resolvedBaseRatePct {
    if (baseRatePct != null) return baseRatePct;
    if (baseEarn == null) return null;
    if (baseEarn!.effectivePct != null) return baseEarn!.effectivePct;
    final points = baseEarn!.points;
    final per = baseEarn!.perSpendInr;
    if (points != null && per != null && per > 0) {
      // e.g. 5 points per Rs 200, each point worth Rs 0.65
      //      -> 5 * 0.65 / 200 * 100 = 1.625%
      return points * pointValueInr / per * 100;
    }
    return null;
  }

  SharedCap? sharedCapFor(String group) {
    for (final cap in sharedCaps) {
      if (cap.group == group) return cap;
    }
    return null;
  }

  factory CardRule.fromJson(Map<String, dynamic> json) {
    final conditional = json['conditional_tier'] as Map<String, dynamic>?;
    return CardRule(
      id: json['id'] as String,
      bank: json['bank'] as String? ?? '',
      name: json['name'] as String? ?? '',
      network: _stringList(json['network']),
      annualFee: _toDouble(json['annual_fee']),
      feeWaiverAnnualSpend: _toDouble(json['fee_waiver_annual_spend']),
      lifetimeFree: json['lifetime_free'] as bool? ?? false,
      rewardType: json['reward_type'] as String? ?? 'cashback',
      // Defaulting to 1.0 is safe: for cashback cards a "point" is a rupee.
      pointValueInr: _toDouble(json['point_value_inr']) ?? 1.0,
      pointCurrency: json['point_currency'] as String?,
      baseRatePct: _toDouble(json['base_rate_pct']),
      baseEarn: json['base_earn'] == null
          ? null
          : BaseEarn.fromJson(json['base_earn'] as Map<String, dynamic>),
      categoryRates: (json['category_rates'] as List<dynamic>? ?? [])
          .map((e) => CategoryRate.fromJson(e as Map<String, dynamic>))
          .toList(),
      sharedCaps: (json['shared_caps'] as List<dynamic>? ?? [])
          .map((e) => SharedCap.fromJson(e as Map<String, dynamic>))
          .toList(),
      totalMonthlyCapInr: _toDouble(json['total_monthly_cap_inr']),
      maxAnnualCashbackInr: _toDouble(json['max_annual_cashback_inr']),
      exclusions: _stringList(json['exclusions']),
      conditionalCondition: conditional?['condition'] as String?,
      conditionalNote: conditional?['note'] as String?,
      lastChanged: json['last_changed'] as String?,
      changeSummary: json['change_summary'] as String?,
      lastVerified: json['last_verified'] as String?,
      unverified: _stringList(json['_verify']),
    );
  }
}

/// Reads a value that might be an int, a double, a null, or missing entirely.
/// JSON has one number type; Dart has two, so this smooths over the difference.
double? _toDouble(dynamic value) {
  if (value == null) return null;
  if (value is num) return value.toDouble();
  if (value is String) return double.tryParse(value);
  return null;
}

/// Reads a list of strings, tolerating a missing key or a null.
List<String> _stringList(dynamic value) {
  if (value is List) {
    return value.whereType<String>().toList();
  }
  return const [];
}
