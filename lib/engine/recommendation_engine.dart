/// Works out which of the user's cards earns most on a given purchase.
///
/// The whole app exists to answer one question, and this file answers it.
/// Read it top to bottom: [recommend] is the entry point, and each private
/// method below it handles one of the awkward real-world behaviours that make
/// Indian credit card rewards hard to compare.
library;

import 'dart:math' as math;

import '../models/card.dart';
import '../models/rules.dart';
import 'recommendation.dart';

/// How much of a card's allowances the user has already used up this cycle.
///
/// Caps are the difference between a card looking good and actually being
/// good. Axis ACE pays 5% on utilities, but only until Rs 500 of cashback in a
/// month; after that it pays nothing extra. Without knowing what has already
/// been earned, a recommendation is a guess.
///
/// Everything here is optional. When the user has told us nothing we assume a
/// fresh cycle, which is the friendly default, and the UI says so.
class CardUsage {
  /// Total spend on this card so far in the current statement cycle.
  /// Only matters for cards whose rate depends on it — currently IDFC FIRST
  /// Select, which pays a much better rate above Rs 20,000 per cycle.
  final double spendThisCycleInr;

  /// Rupees of reward already earned against each cap, keyed by the cap ids
  /// produced by [_capKeyFor]. Missing keys mean "nothing used yet".
  final Map<String, double> capUsageInr;

  const CardUsage({
    this.spendThisCycleInr = 0,
    this.capUsageInr = const {},
  });

  double usedFor(String capKey) => capUsageInr[capKey] ?? 0;

  static const empty = CardUsage();
}

/// Everything the engine needs to know about the purchase and the user.
class SpendRequest {
  /// A category id from `rules.json`, e.g. `food_delivery`.
  final String category;

  /// The purchase amount in rupees.
  final double amountInr;

  /// Optional named merchant, lowercase, e.g. `swiggy`. Some rates only apply
  /// at specific merchants, so naming one can change the answer.
  final String? merchant;

  /// Amazon Pay ICICI pays 5% to Prime members and 3% to everyone else, so the
  /// app has to ask. This is the only user-level flag the dataset needs today.
  final bool amazonPrimeMember;

  /// Per-card cap and spend state, keyed by card id.
  final Map<String, CardUsage> usage;

  const SpendRequest({
    required this.category,
    required this.amountInr,
    this.merchant,
    this.amazonPrimeMember = false,
    this.usage = const {},
  });

  CardUsage usageFor(String cardId) => usage[cardId] ?? CardUsage.empty;
}

class RecommendationEngine {
  final Rules rules;

  const RecommendationEngine(this.rules);

  /// Ranks the given cards best-first for this purchase.
  ///
  /// Cards that earn nothing are still returned, at the bottom, with the
  /// reason why. Hiding them would leave the user wondering whether the app
  /// simply forgot about a card they own.
  List<Recommendation> recommend(
    List<CardRule> userCards,
    SpendRequest request,
  ) {
    final results =
        userCards.map((card) => evaluate(card, request)).toList();

    results.sort((a, b) {
      // Most rupees wins.
      final byRupees = b.rupees.compareTo(a.rupees);
      if (byRupees != 0) return byRupees;
      // Then prefer the card we are confident about over an "up to 10X" guess.
      if (a.uncertain != b.uncertain) return a.uncertain ? 1 : -1;
      return a.card.displayName.compareTo(b.card.displayName);
    });

    return results;
  }

  /// Works out what a single card earns. Public so tests can drive one card
  /// at a time.
  Recommendation evaluate(CardRule card, SpendRequest request) {
    final reasons = <String>[];

    // ---- 1. Is this category excluded? ----------------------------------
    // Some exclusions carry a threshold, so this has to know the amount.
    final excluded = card.isExcluded(request.category, request.amountInr);
    if (excluded != null) {
      final threshold =
          RegExp(r'_above_(\d+)$').firstMatch(excluded)?.group(1);
      return Recommendation(
        card: card,
        rupees: 0,
        effectivePct: 0,
        headline: 'Earns nothing here',
        excluded: true,
        reasons: [
          threshold == null
              ? '${prettyCategory(request.category)} is on this card\'s '
                  'exclusion list, so the spend earns no reward at all.'
              : '${prettyCategory(request.category)} earns nothing on this '
                  'card above ₹$threshold, and this purchase is over that.',
          ...?_surchargeReason(card, request),
        ],
      );
    }

    // ---- 2. Spend tiers, where the rate depends on the cycle ------------
    // Handled before ordinary rate selection because a tiered card can earn
    // two different rates on a single transaction.
    final tiered = _evaluateSpendTiers(card, request, reasons);
    if (tiered != null) return tiered;

    // ---- 3. Pick the rate row that applies ------------------------------
    final match = _selectRate(card, request);
    var rate = match.row;

    // ---- 4. Minimum transaction value -----------------------------------
    // A Rs 150 Swiggy order on a card with a Rs 249 minimum does not earn 5%.
    // It falls back to the card's ordinary rate, which may itself have a
    // minimum, in which case it earns nothing.
    if (rate != null &&
        rate.minTransactionInr != null &&
        request.amountInr < rate.minTransactionInr!) {
      reasons.add(
        'This purchase is below the ₹${_plain(rate.minTransactionInr!)} '
        'minimum needed for the '
        '${_ratePctOf(rate, card, request)?.toStringAsFixed(1) ?? 'accelerated'}% '
        'rate, so it drops to the ordinary rate.',
      );
      rate = _genericRowFor(card);
      if (rate != null &&
          rate.minTransactionInr != null &&
          request.amountInr < rate.minTransactionInr!) {
        return Recommendation(
          card: card,
          rupees: 0,
          effectivePct: 0,
          headline: 'Below this card\'s minimum',
          reasons: [
            ...reasons,
            'The ordinary rate also needs at least '
                '₹${_plain(rate.minTransactionInr!)}, so this purchase earns '
                'nothing on this card.',
          ],
        );
      }
    }

    // ---- 5. Turn whatever the JSON said into a plain percentage ---------
    var uncertain = false;
    double? pct = rate == null ? null : _ratePctOf(rate, card, request);

    if (pct == null) {
      // Either there is no matching row, or the row exists but names no
      // number — Regalia Gold's "up to 10X on SmartBuy" is the real example.
      // We fall back to the card's base rate and say plainly that the card
      // may do better, rather than inventing a figure for it.
      pct = card.resolvedBaseRatePct;
      if (rate != null && rate.multiplier != null) {
        uncertain = true;
        reasons.add(
          'This card advertises ${rate.multiplier} here, but the dataset has '
              'no firm rate for it, so the figure below uses the card\'s base '
              'rate and is likely an underestimate.',
        );
      }
    }

    if (pct == null) {
      return Recommendation(
        card: card,
        rupees: 0,
        effectivePct: 0,
        headline: 'No rate on record',
        uncertain: true,
        reasons: [
          ...reasons,
          'The dataset has no reward rate for this card in this category. '
              'Check the issuer\'s terms before relying on it.',
        ],
      );
    }

    // ---- 6. Work out the gross earning ----------------------------------
    // Points cards earn per completed slab, so they are calculated from the
    // slab rather than from the percentage. Cashback really is continuous.
    final slab = rate == null
        ? _basePointsRate(card)
        : (_pointsRateOf(rate, card) ??
            (rate.hasNoOwnRate ? _basePointsRate(card) : null));

    double gross;
    if (slab != null) {
      final slabs = (request.amountInr / slab.perSpendInr).floor();
      gross = slabs * slab.pointsPerSlab * card.pointValueInr;
    } else {
      gross = request.amountInr * pct / 100;
    }

    // ---- 7. Apply the caps ----------------------------------------------
    final capped = _applyCaps(card, rate, request, gross, reasons);

    // ---- 8. Describe the result -----------------------------------------
    if (rate?.note != null) reasons.add(rate!.note!);

    // Points earned, recomputed from the post-cap figure so a cap shows up in
    // the point count too rather than only in the rupees.
    final points = card.pointValueInr > 0 && card.rewardType != 'cashback'
        ? capped.earned / card.pointValueInr
        : null;

    if (points != null && card.pointCurrency != null) {
      if (slab != null) {
        reasons.add(
          '${slab.pointsPerSlab.round()} ${card.pointCurrency} per '
          '₹${_plain(slab.perSpendInr)} spent, and only on completed '
          '₹${_plain(slab.perSpendInr)} slabs — the remainder earns nothing.',
        );
      }
      reasons.add(
        '${card.pointCurrency} are valued here at '
        '₹${_plain(card.pointValueInr)} each, which is what makes this '
        'comparable with a cashback card.',
      );
    }
    for (final field in [...card.unverified, ...(rate?.unverified ?? [])]) {
      reasons.add('Unverified in the dataset: $field.');
    }

    // A fee on this kind of spend comes straight off what you earn. Netting it
    // here rather than mentioning it in passing is the difference between
    // "this card pays a little" and "this card costs you money".
    var net = capped.earned;
    final surcharge = card.surchargeFor(request.category, request.amountInr);
    if (surcharge?.feePct != null) {
      final fee = request.amountInr * surcharge!.feePct! / 100;
      net -= fee;
      reasons.add(
        'This card charges a ${_plain(surcharge.feePct!)}% fee on this kind of '
        'spend — ₹${_plain(fee)} here — which is netted off above. Its own '
        'wording: "${surcharge.trigger}".',
      );
    }

    final effective =
        request.amountInr > 0 ? net / request.amountInr * 100 : 0.0;

    return Recommendation(
      card: card,
      rupees: net,
      effectivePct: effective,
      headline: _headline(effective, rate, capped.wasCapped),
      reasons: reasons,
      capped: capped.wasCapped,
      uncertain: uncertain,
      pointsEarned: points,
      pointCurrency: card.pointCurrency,
    );
  }

  // -----------------------------------------------------------------------
  // Rate selection
  // -----------------------------------------------------------------------

  /// Chooses which `category_rates` row applies to this purchase.
  ///
  /// Rows are scored by how specifically they match, because cards list rows
  /// from most to least specific and several rows can match at once. Amazon
  /// Pay ICICI, for instance, has three separate `other` rows.
  ///
  /// Where two rows match equally well we deliberately take the **lower**
  /// rate. The higher one usually carries an unstated condition (a partner
  /// merchant list we cannot check), and it is better to under-promise than to
  /// tell someone they will earn 2% when they will earn 1%.
  _RateMatch _selectRate(CardRule card, SpendRequest request) {
    final merchant = request.merchant?.toLowerCase();

    CategoryRate? best;
    var bestScore = -1.0;

    for (final row in card.categoryRates) {
      final score = _scoreRow(row, request.category, merchant);
      if (score < 0) continue;

      if (score > bestScore) {
        best = row;
        bestScore = score;
      } else if (score == bestScore && best != null) {
        // Equal specificity: keep the more conservative row.
        final a = _ratePctOf(best, card, request);
        final b = _ratePctOf(row, card, request);
        if (a != null && b != null && b < a) best = row;
        // A row with no rate of its own never displaces one that has a rate.
        if (a == null && b != null) best = row;
      }
    }

    return _RateMatch(best, bestScore);
  }

  /// Higher is more specific. Negative means the row does not apply at all.
  double _scoreRow(CategoryRate row, String category, String? merchant) {
    final categoryMatches = row.category == category;
    final isCatchAll = row.category == 'other';

    if (row.merchants.isNotEmpty) {
      // A row limited to named merchants only applies when we know the
      // merchant and it is on the list.
      if (merchant == null || !row.merchants.contains(merchant)) return -1;

      // Deliberately checked before the category gate below. When a row names
      // merchants, that list is the binding condition and the row's category
      // label is often just where the issuer filed it. HDFC Millennia's "10
      // partner merchants" row is tagged other_ecommerce but includes Swiggy,
      // Uber and BookMyShow; gating on category would mean a Swiggy order
      // never saw the 5%.
      return categoryMatches ? 3 : 2.5;
    }

    if (!categoryMatches && !isCatchAll) return -1;

    return categoryMatches ? 2 : 1;
  }

  /// The card's plain catch-all row, used when a minimum knocks out the
  /// accelerated rate.
  CategoryRate? _genericRowFor(CardRule card) {
    CategoryRate? found;
    for (final row in card.categoryRates) {
      if (row.category == 'other' && row.merchants.isEmpty) {
        // Later rows in the JSON are the more generic ones.
        found = row;
      }
    }
    return found;
  }

  /// The unrestricted rows that govern a category: its own rows if it has any,
  /// otherwise the card's catch-all `other` rows.
  ///
  /// The fallback matters because IDFC FIRST Select records its whole spend
  /// tier structure under `other`, so a groceries purchase — which has no row
  /// of its own — is still governed by those tiers.
  List<CategoryRate> _genericRowsFor(CardRule card, String category) {
    final own = card.categoryRates
        .where((r) => r.category == category && r.merchants.isEmpty)
        .toList();
    if (own.isNotEmpty) return own;
    return card.categoryRates
        .where((r) => r.category == 'other' && r.merchants.isEmpty)
        .toList();
  }

  /// How a row pays in points, if it does.
  ///
  /// Points are not earned continuously. "5 points per Rs 200" means you earn
  /// on each completed Rs 200 — a Rs 350 purchase earns 5 points, not 8.75 —
  /// so the engine needs the slab size, not just the percentage it works out
  /// to. Returns null for cashback rows, which really are continuous.
  ///
  /// Worth verifying per issuer: a few accumulate the remainder across a
  /// statement rather than discarding it per transaction. Discarding is the
  /// common behaviour and the conservative one.
  _PointsRate? _pointsRateOf(CategoryRate row, CardRule card) {
    if (row.pointsPer200 != null) {
      return _PointsRate(row.pointsPer200!, 200);
    }
    if (row.milesPer100 != null) {
      return _PointsRate(row.milesPer100!, 100);
    }
    return null;
  }

  /// The card's own base earn expressed as a slab, when it has one.
  _PointsRate? _basePointsRate(CardRule card) {
    final base = card.baseEarn;
    if (base?.points != null &&
        base?.perSpendInr != null &&
        base!.perSpendInr! > 0) {
      return _PointsRate(base.points!, base.perSpendInr!);
    }
    return null;
  }

  /// Converts a row's rate into a plain percentage, whichever of the four
  /// possible shapes the JSON used.
  double? _ratePctOf(CategoryRate row, CardRule card, SpendRequest request) {
    if (row.ratePctPrime != null || row.ratePctNonPrime != null) {
      return request.amazonPrimeMember ? row.ratePctPrime : row.ratePctNonPrime;
    }
    if (row.ratePct != null) return row.ratePct;

    // "N points per Rs 200", each point worth pointValueInr rupees.
    if (row.pointsPer200 != null) {
      return row.pointsPer200! * card.pointValueInr / 200 * 100;
    }
    // "N miles per Rs 100".
    if (row.milesPer100 != null) {
      return row.milesPer100! * card.pointValueInr / 100 * 100;
    }
    // Last resort: a precomputed figure sitting in the dataset.
    return row.effectivePct;
  }

  // -----------------------------------------------------------------------
  // Spend tiers
  // -----------------------------------------------------------------------

  /// Handles cards whose rate improves once you have spent enough this cycle.
  ///
  /// IDFC FIRST Select pays 3 points per Rs 200 on the first Rs 20,000 of a
  /// statement cycle and 10 points per Rs 200 after that. A single purchase
  /// can straddle the boundary, so we split it and earn both rates.
  ///
  /// The threshold is read out of the row's English label, because that is
  /// where `rules.json` records it today. If the wording ever changes this
  /// returns null and adds a visible warning rather than quietly picking one
  /// tier — a silent wrong answer would be worse than an obvious gap.
  Recommendation? _evaluateSpendTiers(
    CardRule card,
    SpendRequest request,
    List<String> reasons,
  ) {
    final rows = _genericRowsFor(card, request.category);
    if (rows.length < 2) return null;

    CategoryRate? lower;
    CategoryRate? upper;
    double? threshold;

    for (final row in rows) {
      final label = row.label?.toLowerCase();
      if (label == null) continue;
      final amount = _rupeesInText(label);
      if (amount == null) continue;

      if (label.contains('up to')) {
        lower = row;
        threshold ??= amount;
      } else if (label.contains('above')) {
        upper = row;
        threshold ??= amount;
      }
    }

    if (lower == null || upper == null || threshold == null) {
      // Several rows matched but they are not a spend-tier pair. The usual
      // cause is a card that pays a better rate at unnamed partner merchants —
      // Amazon Pay ICICI pays 2% at its partners and 1% everywhere else, and
      // the dataset does not list who the partners are. We cannot check, so
      // [_selectRate] quotes the lower rate and we mention the higher one here.
      final rates = rows
          .map((r) => _ratePctOf(r, card, request))
          .whereType<double>()
          .toList()
        ..sort();
      if (rates.length > 1 && rates.first != rates.last) {
        reasons.add(
          'The figure below uses this card\'s ordinary '
          '${rates.first.toStringAsFixed(rates.first % 1 == 0 ? 0 : 2)}% rate. '
          'It pays up to '
          '${rates.last.toStringAsFixed(rates.last % 1 == 0 ? 0 : 2)}% at '
          'selected partner merchants, which the app cannot identify.',
        );
      }
      return null;
    }

    final lowerPct = _ratePctOf(lower, card, request);
    final upperPct = _ratePctOf(upper, card, request);
    if (lowerPct == null || upperPct == null) return null;

    final alreadySpent = request.usageFor(card.id).spendThisCycleInr;
    final headroom = math.max(0.0, threshold - alreadySpent);
    final atLowerRate = math.min(request.amountInr, headroom);
    final atUpperRate = request.amountInr - atLowerRate;

    // Each portion earns on its own completed slabs, same as anywhere else.
    final lowerSlab = _pointsRateOf(lower, card);
    final upperSlab = _pointsRateOf(upper, card);

    double earned;
    if (lowerSlab != null && upperSlab != null) {
      final lowerPoints =
          (atLowerRate / lowerSlab.perSpendInr).floor() * lowerSlab.pointsPerSlab;
      final upperPoints =
          (atUpperRate / upperSlab.perSpendInr).floor() * upperSlab.pointsPerSlab;
      earned = (lowerPoints + upperPoints) * card.pointValueInr;
    } else {
      earned = atLowerRate * lowerPct / 100 + atUpperRate * upperPct / 100;
    }

    final effective =
        request.amountInr > 0 ? earned / request.amountInr * 100 : 0.0;

    if (atLowerRate > 0 && atUpperRate > 0) {
      reasons.add(
        'This purchase straddles the ₹${_plain(threshold)} cycle threshold: '
        '₹${_plain(atLowerRate)} earns ${lowerPct.toStringAsFixed(2)}% and the '
        'remaining ₹${_plain(atUpperRate)} earns '
        '${upperPct.toStringAsFixed(2)}%.',
      );
    } else if (atUpperRate > 0) {
      reasons.add(
        'You have already spent ₹${_plain(alreadySpent)} this cycle, so this '
        'purchase earns the higher ${upperPct.toStringAsFixed(2)}% rate.',
      );
    } else {
      reasons.add(
        'Spending past ₹${_plain(threshold)} this cycle would lift the rate to '
        '${upperPct.toStringAsFixed(2)}%.',
      );
    }

    if (card.pointCurrency != null) {
      reasons.add(
        '${card.pointCurrency} are valued here at '
        '₹${_plain(card.pointValueInr)} each, which is what makes this '
        'comparable with a cashback card.',
      );
    }

    return Recommendation(
      card: card,
      rupees: earned,
      effectivePct: effective,
      headline: '${effective.toStringAsFixed(2)}% at your current cycle spend',
      reasons: reasons,
      pointsEarned: card.pointValueInr > 0 && card.rewardType != 'cashback'
          ? earned / card.pointValueInr
          : null,
      pointCurrency: card.pointCurrency,
    );
  }

  // -----------------------------------------------------------------------
  // Caps
  // -----------------------------------------------------------------------

  /// Trims the earned amount down to whatever cap allowance is left.
  ///
  /// Assumption worth checking against the issuer documents: spend beyond a
  /// cap earns **nothing extra**, rather than dropping to the base rate. That
  /// is how most of these cards behave, but it is not universal.
  _CapResult _applyCaps(
    CardRule card,
    CategoryRate? rate,
    SpendRequest request,
    double gross,
    List<String> reasons,
  ) {
    var earned = gross;
    var wasCapped = false;
    final usage = request.usageFor(card.id);

    // The category's own cap, or the group ceiling it shares with others.
    if (rate != null) {
      final cap = _capAmountFor(card, rate);
      if (cap != null) {
        final key = _capKeyFor(card, rate);
        final remaining = math.max(0.0, cap.rupees - usage.usedFor(key));
        if (earned > remaining) {
          earned = remaining;
          wasCapped = true;
          reasons.add(
            cap.sharedWith == null
                ? 'Capped: this category allows ₹${_plain(cap.rupees)} of '
                    'reward per ${cap.period}, and ₹${_plain(usage.usedFor(key))} '
                    'is already used.'
                : 'Capped: this rate shares a single ₹${_plain(cap.rupees)} '
                    'per-${cap.period} ceiling with the card\'s other '
                    'accelerated categories, and ₹${_plain(usage.usedFor(key))} '
                    'is already used.',
          );
        }
      }
    }

    // A final ceiling across the whole card.
    final total = card.totalMonthlyCapInr;
    if (total != null) {
      final remaining = math.max(0.0, total - usage.usedFor(_totalCapKey));
      if (earned > remaining) {
        earned = remaining;
        wasCapped = true;
        reasons.add(
          'Capped: the card allows ₹${_plain(total)} of reward per month '
          'across every category.',
        );
      }
    }

    return _CapResult(earned, wasCapped);
  }

  /// Works out the cap that applies to a row, converting point caps into
  /// rupees so everything can be compared on one scale.
  _Cap? _capAmountFor(CardRule card, CategoryRate rate) {
    final group = rate.sharedCapGroup;
    if (group != null) {
      final shared = card.sharedCapFor(group);
      if (shared?.monthlyCapInr != null) {
        return _Cap(shared!.monthlyCapInr!, 'month', group);
      }
      if (shared?.quarterlyCapInr != null) {
        return _Cap(shared!.quarterlyCapInr!, 'quarter', group);
      }
    }
    if (rate.monthlyCapInr != null) {
      return _Cap(rate.monthlyCapInr!, 'month', null);
    }
    if (rate.quarterlyCapInr != null) {
      return _Cap(rate.quarterlyCapInr!, 'quarter', null);
    }
    if (rate.monthlyCapPoints != null) {
      // A cap of 2,000 points on a card whose points are worth Rs 1 each is a
      // Rs 2,000 cap. Converting here keeps every cap in the same units.
      return _Cap(rate.monthlyCapPoints! * card.pointValueInr, 'month', null);
    }
    return null;
  }

  /// The key under which usage against a given cap is tracked.
  static String _capKeyFor(CardRule card, CategoryRate rate) {
    final group = rate.sharedCapGroup;
    if (group != null) return 'shared:$group';
    return 'cat:${rate.category}';
  }

  static const _totalCapKey = 'total';

  String _headline(double pct, CategoryRate? rate, bool capped) {
    final label = rate?.label;
    final base = '${pct.toStringAsFixed(pct % 1 == 0 ? 0 : 2)}% back';
    if (capped) return '$base, but you have hit the cap';
    if (label != null) return '$base — $label';
    return base;
  }
}

/// The fee note for an excluded purchase, if there is one.
///
/// An excluded category earning nothing is one thing; earning nothing *and*
/// being charged for the privilege is worth saying out loud.
List<String>? _surchargeReason(CardRule card, SpendRequest request) {
  final surcharge =
      card.surchargeFor(request.category, request.amountInr);
  if (surcharge?.feePct == null) return null;
  final fee = request.amountInr * surcharge!.feePct! / 100;
  return [
    'Worse than nothing: this card also charges '
        '${_plain(surcharge.feePct!)}% on this spend, about ₹${_plain(fee)}.',
  ];
}

/// "N points per Rs X spent", kept as a slab rather than a percentage so the
/// engine can round down to completed slabs the way issuers actually do.
class _PointsRate {
  final double pointsPerSlab;
  final double perSpendInr;
  const _PointsRate(this.pointsPerSlab, this.perSpendInr);
}

/// Pulls the first rupee figure out of a label like
/// "Spends up to Rs 20,000 per statement cycle" and returns 20000.
double? _rupeesInText(String text) {
  final match = RegExp(r'(?:rs\.?|₹)\s*([\d,]+)').firstMatch(text);
  if (match == null) return null;
  return double.tryParse(match.group(1)!.replaceAll(',', ''));
}

/// Formats a number the way a person would write it: 500 not 500.0,
/// 0.25 not 0.250000001.
String _plain(double value) {
  if (value == value.roundToDouble()) return value.round().toString();
  return value.toStringAsFixed(2);
}

class _RateMatch {
  final CategoryRate? row;
  final double score;
  const _RateMatch(this.row, this.score);
}

class _Cap {
  final double rupees;
  final String period;
  final String? sharedWith;
  const _Cap(this.rupees, this.period, this.sharedWith);
}

class _CapResult {
  final double earned;
  final bool wasCapped;
  const _CapResult(this.earned, this.wasCapped);
}
