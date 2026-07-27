/// "Which card should I use?" — the screen the whole app exists for.
///
/// The user picks a category and types an amount. The engine ranks their cards
/// by rupees earned, and every row can be expanded to see why it landed where
/// it did.
library;

import 'package:flutter/material.dart';

import '../data/rules_repository.dart';
import '../data/user_cards_store.dart';
import '../engine/recommendation.dart';
import '../engine/recommendation_engine.dart';
import '../models/rules.dart';

class RecommendScreen extends StatefulWidget {
  final RulesRepository rulesRepository;
  final UserCardsStore store;

  /// Card ids that currently have an unresolved terms-change alert, so those
  /// rows can be marked as possibly out of date.
  final Set<String> alertedCardIds;

  /// Lets the parent tell this screen to reload after the card list changes.
  final Listenable refreshSignal;

  const RecommendScreen({
    super.key,
    required this.rulesRepository,
    required this.store,
    required this.refreshSignal,
    this.alertedCardIds = const {},
  });

  @override
  State<RecommendScreen> createState() => _RecommendScreenState();
}

class _RecommendScreenState extends State<RecommendScreen> {
  final _amountController = TextEditingController(text: '1000');

  Rules? _rules;
  Set<String> _owned = {};
  bool _isPrime = false;
  Map<String, double> _cycleSpends = {};
  String _category = 'food_delivery';

  @override
  void initState() {
    super.initState();
    widget.refreshSignal.addListener(_load);
    _load();
  }

  @override
  void dispose() {
    widget.refreshSignal.removeListener(_load);
    _amountController.dispose();
    super.dispose();
  }

  Future<void> _load() async {
    final rules = await widget.rulesRepository.load();
    final owned = await widget.store.ownedCardIds();
    final prime = await widget.store.isAmazonPrimeMember();
    final spends = await widget.store.allCycleSpends(owned);
    if (!mounted) return;
    setState(() {
      _rules = rules;
      _owned = owned;
      _isPrime = prime;
      _cycleSpends = spends;
      if (!rules.categories.contains(_category) &&
          rules.categories.isNotEmpty) {
        _category = rules.categories.first;
      }
    });
  }

  double get _amount =>
      double.tryParse(_amountController.text.replaceAll(',', '')) ?? 0;

  List<Recommendation> _results(Rules rules) {
    final cards = rules.cardsByIds(_owned);
    if (cards.isEmpty) return const [];

    final engine = RecommendationEngine(rules);
    return engine.recommend(
      cards,
      SpendRequest(
        category: _category,
        amountInr: _amount,
        amazonPrimeMember: _isPrime,
        usage: {
          for (final entry in _cycleSpends.entries)
            entry.key: CardUsage(spendThisCycleInr: entry.value),
        },
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final rules = _rules;
    if (rules == null) {
      return const Center(child: CircularProgressIndicator());
    }

    if (_owned.isEmpty) {
      return const _EmptyState();
    }

    final results = _results(rules);

    return Column(
      children: [
        Padding(
          padding: const EdgeInsets.all(16),
          child: Row(
            children: [
              Expanded(
                flex: 3,
                child: DropdownButtonFormField<String>(
                  initialValue: _category,
                  isExpanded: true,
                  decoration: const InputDecoration(
                    labelText: 'Spending on',
                    isDense: true,
                  ),
                  items: [
                    for (final category in rules.categories)
                      DropdownMenuItem(
                        value: category,
                        child: Text(prettyCategory(category),
                            overflow: TextOverflow.ellipsis),
                      ),
                  ],
                  onChanged: (value) {
                    if (value != null) setState(() => _category = value);
                  },
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                flex: 2,
                child: TextField(
                  controller: _amountController,
                  keyboardType: TextInputType.number,
                  decoration: const InputDecoration(
                    labelText: 'Amount',
                    prefixText: '₹',
                    isDense: true,
                  ),
                  onChanged: (_) => setState(() {}),
                ),
              ),
            ],
          ),
        ),
        const Divider(height: 1),
        Expanded(
          child: ListView.separated(
            itemCount: results.length,
            separatorBuilder: (_, _) => const Divider(height: 1),
            itemBuilder: (context, index) => _ResultTile(
              result: results[index],
              isBest: index == 0 && results[index].rupees > 0,
              hasAlert: widget.alertedCardIds.contains(results[index].card.id),
            ),
          ),
        ),
      ],
    );
  }
}

class _ResultTile extends StatelessWidget {
  final Recommendation result;
  final bool isBest;
  final bool hasAlert;

  const _ResultTile({
    required this.result,
    required this.isBest,
    required this.hasAlert,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return ExpansionTile(
      leading: isBest
          ? Icon(Icons.emoji_events, color: theme.colorScheme.primary)
          : const SizedBox(width: 24),
      title: Row(
        children: [
          Expanded(child: Text(result.card.displayName)),
          if (hasAlert)
            Padding(
              padding: const EdgeInsets.only(right: 8),
              child: Tooltip(
                message: 'The issuer changed this card\'s terms recently',
                child: Icon(Icons.info_outline,
                    size: 18, color: theme.colorScheme.tertiary),
              ),
            ),
          Text(
            result.formattedRupees,
            style: theme.textTheme.titleMedium?.copyWith(
              fontWeight: FontWeight.w700,
              color: result.rupees > 0
                  ? theme.colorScheme.primary
                  : theme.disabledColor,
            ),
          ),
        ],
      ),
      subtitle: Text(
        result.excluded
            ? result.headline
            : '${result.headline} • ${result.formattedPct} effective',
        style: theme.textTheme.bodySmall,
      ),
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(24, 0, 16, 16),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              if (result.reasons.isEmpty)
                Text('Nothing unusual applies here.',
                    style: theme.textTheme.bodySmall),
              for (final reason in result.reasons)
                Padding(
                  padding: const EdgeInsets.only(bottom: 6),
                  child: Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      const Text('• '),
                      Expanded(
                        child:
                            Text(reason, style: theme.textTheme.bodySmall),
                      ),
                    ],
                  ),
                ),
            ],
          ),
        ),
      ],
    );
  }
}

class _EmptyState extends StatelessWidget {
  const _EmptyState();

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(32),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Icon(Icons.credit_card, size: 48),
            const SizedBox(height: 16),
            Text(
              'Add your cards first',
              style: Theme.of(context).textTheme.titleMedium,
            ),
            const SizedBox(height: 8),
            Text(
              'Open the My cards tab and tick the cards you have. Then come '
              'back here and the app will tell you which one to use.',
              textAlign: TextAlign.center,
              style: Theme.of(context).textTheme.bodySmall,
            ),
          ],
        ),
      ),
    );
  }
}
