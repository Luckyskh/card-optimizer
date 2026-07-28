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
  ///
  /// Most entries are a plain category, but some carry a threshold —
  /// `wallet_load_above_5000` means the exclusion only bites above ₹5,000.
  /// Use [isExcluded] rather than testing this list directly, or the threshold
  /// form silently never matches and the card looks better than it is.
  final List<String> exclusions;

  /// Fees the card charges on particular kinds of spend, which offset or
  /// outweigh what it pays.
  final List<Surcharge> surcharges;

  /// Airline and hotel programmes this card's points can be moved to.
  final TransferPartners? transferPartners;

  /// Platforms with accelerated earning, as prose the engine cannot price.
  final AcceleratedPartners? acceleratedPartners;

  /// What one point is worth if transferred, where that differs from the
  /// ordinary redemption value.
  final String? pointValueNote;

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
    this.surcharges = const [],
    this.transferPartners,
    this.acceleratedPartners,
    this.pointValueNote,
    this.conditionalCondition,
    this.conditionalNote,
    this.lastChanged,
    this.changeSummary,
    this.lastVerified,
    this.unverified = const [],
  });

  /// "HDFC Bank Millennia" — what the user actually sees in a list.
  String get displayName => '$bank $name';

  /// Whether this purchase earns nothing at all.
  ///
  /// Handles both plain exclusions and the threshold form. Amazon Pay ICICI
  /// lists `wallet_load_above_5000`: a Rs 3,000 load still earns, a Rs 8,000
  /// one does not. Comparing the raw string against the category would match
  /// neither, so the card would appear to earn on a load that in fact pays
  /// nothing and costs a fee.
  ///
  /// Returns the matching exclusion so the reason shown can quote it.
  String? isExcluded(String category, double amountInr) {
    for (final entry in exclusions) {
      if (entry == category) return entry;

      final threshold = RegExp('^${RegExp.escape(category)}_above_(\\d+)\$')
          .firstMatch(entry);
      if (threshold != null) {
        final limit = double.tryParse(threshold.group(1)!);
        if (limit != null && amountInr > limit) return entry;
      }
    }
    return null;
  }

  /// Any fee this purchase attracts, or null.
  Surcharge? surchargeFor(String category, double amountInr) {
    for (final surcharge in surcharges) {
      if (surcharge.applies(category, amountInr)) return surcharge;
    }
    return null;
  }

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
      surcharges: (json['fees_and_surcharges'] as List<dynamic>? ?? [])
          .whereType<Map<String, dynamic>>()
          .map(Surcharge.fromJson)
          .toList(),
      transferPartners: json['transfer_partners'] == null
          ? null
          : TransferPartners.fromJson(
              json['transfer_partners'] as Map<String, dynamic>),
      acceleratedPartners: AcceleratedPartners.fromJson(
          json['accelerated_partners'] as Map<String, dynamic>?),
      pointValueNote: json['point_value_note'] as String?,
      conditionalCondition: conditional?['condition'] as String?,
      conditionalNote: conditional?['note'] as String?,
      lastChanged: json['last_changed'] as String?,
      changeSummary: json['change_summary'] as String?,
      lastVerified: json['last_verified'] as String?,
      unverified: _stringList(json['_verify']),
    );
  }
}

/// Platforms where a card earns at an accelerated rate, as free text.
///
/// This comes from the supplied spreadsheets — "HDFC SmartBuy (MakeMyTrip,
/// Cleartrip, Amazon)" with a rate like "Up to 10X Reward Points". The
/// platforms are prose, not category ids, so the engine cannot price them;
/// they are shown to the user as a hint that the card can do better than the
/// figure on screen, which is more honest than either hiding them or guessing
/// a number.
class AcceleratedPartners {
  final String platforms;
  final String rate;

  const AcceleratedPartners({required this.platforms, required this.rate});

  static AcceleratedPartners? fromJson(Map<String, dynamic>? json) {
    if (json == null) return null;
    final platforms = json['platforms'] as String?;
    final rate = json['rate'] as String?;
    if (platforms == null || platforms.isEmpty) return null;
    return AcceleratedPartners(platforms: platforms, rate: rate ?? '');
  }
}

/// One tier of transfer partners — a set of programmes that share a ratio and
/// an annual ceiling.
///
/// Issuers group partners rather than listing a ratio per airline, and the
/// groups have different caps, so "how many miles can I actually move" depends
/// on which group the partner sits in.
class TransferGroup {
  /// `group_a`, `group_b` — the issuer's own naming.
  final String name;

  /// "1:2" means one card point becomes two partner miles. Kept as the
  /// dataset's own string rather than parsed into a number, because these are
  /// occasionally not simple ratios and rewriting one would change its meaning.
  final String? ratio;

  final double? annualCapMiles;
  final List<String> partners;

  const TransferGroup({
    required this.name,
    this.ratio,
    this.annualCapMiles,
    this.partners = const [],
  });

  /// The multiplier in "1:2", when it is that simple. Null otherwise, and the
  /// screen then shows the ratio without doing arithmetic on it.
  double? get multiplier {
    final match = RegExp(r'^\s*(\d+(?:\.\d+)?)\s*:\s*(\d+(?:\.\d+)?)\s*$')
        .firstMatch(ratio ?? '');
    if (match == null) return null;
    final from = double.tryParse(match.group(1)!);
    final to = double.tryParse(match.group(2)!);
    if (from == null || to == null || from == 0) return null;
    return to / from;
  }

  factory TransferGroup.fromJson(String name, Map<String, dynamic> json) =>
      TransferGroup(
        name: name,
        ratio: json['ratio'] as String?,
        annualCapMiles: _toDouble(json['annual_cap_miles']),
        partners: _stringList(json['partners']),
      );
}

/// Where a card's points can be moved, and what has been taken away.
class TransferPartners {
  final List<TransferGroup> groups;

  /// Partners the issuer has dropped. Worth keeping visible: Axis removed
  /// Accor, Marriott and Qatar from Atlas overnight in April 2026, and a
  /// programme that has already lost three partners is telling you something
  /// about how safe the remaining ones are.
  final List<String> removed;
  final String? removedOn;

  const TransferPartners({
    this.groups = const [],
    this.removed = const [],
    this.removedOn,
  });

  bool get isEmpty => groups.isEmpty && removed.isEmpty;

  factory TransferPartners.fromJson(Map<String, dynamic> json) {
    final groups = <TransferGroup>[];
    json.forEach((key, value) {
      if (value is Map<String, dynamic> && value.containsKey('partners')) {
        groups.add(TransferGroup.fromJson(key, value));
      }
    });
    return TransferPartners(
      groups: groups,
      removed: _stringList(json['removed']),
      removedOn: json['removed_on'] as String?,
    );
  }
}

/// A fee charged on a particular kind of spend.
///
/// These are the reason a card can be actively bad for a purchase rather than
/// merely unrewarding. Amazon Pay ICICI charges 1% on wallet loads of Rs 5,000
/// or more, so a Rs 8,000 load costs Rs 80 and earns nothing — showing it as a
/// small positive would be the wrong sign, not just an imprecise number.
class Surcharge {
  /// The dataset's own wording, e.g. "wallet_load >= 5000". Shown to the user
  /// verbatim, because paraphrasing a fee rule risks changing its meaning.
  final String trigger;

  final double? feePct;
  final String? effectiveFrom;

  /// The category and threshold parsed out of [trigger], where that was
  /// possible. Null when the wording is too free-form to read safely — in
  /// which case the fee is disclosed but never applied to the maths.
  final String? category;
  final double? aboveInr;

  const Surcharge({
    required this.trigger,
    this.feePct,
    this.effectiveFrom,
    this.category,
    this.aboveInr,
  });

  bool applies(String forCategory, double amountInr) {
    if (category == null || feePct == null) return false;
    if (category != forCategory) return false;
    if (aboveInr != null && amountInr < aboveInr!) return false;
    return true;
  }

  factory Surcharge.fromJson(Map<String, dynamic> json) {
    final trigger = json['trigger'] as String? ?? '';

    // Only two shapes are parsed, both unambiguous:
    //   "wallet_load >= 5000"
    //   "utilities above 25000 per cycle"
    // Anything else - "skill_based_gaming", "transport MCC spends above
    // 50000" - is left unparsed rather than guessed at, so it is shown to the
    // user but never silently changes a number.
    final match = RegExp(r'^([a-z_]+)\s*(?:>=|above)\s*([\d,]+)',
            caseSensitive: false)
        .firstMatch(trigger.trim());

    return Surcharge(
      trigger: trigger,
      feePct: _toDouble(json['fee_pct']),
      effectiveFrom: json['effective_from'] as String?,
      category: match?.group(1)?.toLowerCase(),
      aboveInr: match == null
          ? null
          : double.tryParse(match.group(2)!.replaceAll(',', '')),
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
