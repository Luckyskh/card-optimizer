/// "Which cards do you have?" — the setup screen.
///
/// The user ticks the cards they own from a list of names. That is the only
/// thing the app ever needs to know about their cards.
library;

import 'package:flutter/material.dart';

import '../data/rules_repository.dart';
import '../data/user_cards_store.dart';
import '../models/card.dart';
import '../models/rules.dart';
import '../widgets/card_art.dart';

class MyCardsScreen extends StatefulWidget {
  final RulesRepository rulesRepository;
  final UserCardsStore store;

  /// Called whenever the selection changes, so the recommendation screen can
  /// refresh itself.
  final VoidCallback onChanged;

  const MyCardsScreen({
    super.key,
    required this.rulesRepository,
    required this.store,
    required this.onChanged,
  });

  @override
  State<MyCardsScreen> createState() => _MyCardsScreenState();
}

class _MyCardsScreenState extends State<MyCardsScreen> {
  Rules? _rules;
  Set<String> _owned = {};
  bool _isPrime = false;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    final rules = await widget.rulesRepository.load();
    final owned = await widget.store.ownedCardIds();
    final prime = await widget.store.isAmazonPrimeMember();
    if (!mounted) return;
    setState(() {
      _rules = rules;
      _owned = owned;
      _isPrime = prime;
    });
  }

  Future<void> _toggle(CardRule card, bool selected) async {
    if (selected) {
      await widget.store.addCard(card.id);
    } else {
      await widget.store.removeCard(card.id);
    }
    final owned = await widget.store.ownedCardIds();
    if (!mounted) return;
    setState(() => _owned = owned);
    widget.onChanged();
  }

  @override
  Widget build(BuildContext context) {
    final rules = _rules;
    if (rules == null) {
      return const Center(child: CircularProgressIndicator());
    }

    return ListView(
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 16, 16, 8),
          child: Text(
            'Tick the cards you have. The app only stores the card\'s name — '
            'never a card number, expiry date or CVV.',
            style: Theme.of(context).textTheme.bodySmall,
          ),
        ),
        SwitchListTile(
          title: const Text('I have Amazon Prime'),
          subtitle: const Text(
            'Amazon Pay ICICI pays 5% to Prime members and 3% to everyone '
            'else, so this changes the answer.',
          ),
          value: _isPrime,
          onChanged: (value) async {
            await widget.store.setAmazonPrimeMember(value);
            if (!mounted) return;
            setState(() => _isPrime = value);
            widget.onChanged();
          },
        ),
        const Divider(),
        for (final card in rules.cards)
          _CardTile(
            card: card,
            selected: _owned.contains(card.id),
            store: widget.store,
            onToggle: (value) => _toggle(card, value),
          ),
        const SizedBox(height: 24),
      ],
    );
  }
}

class _CardTile extends StatelessWidget {
  final CardRule card;
  final bool selected;
  final UserCardsStore store;
  final ValueChanged<bool> onToggle;

  const _CardTile({
    required this.card,
    required this.selected,
    required this.store,
    required this.onToggle,
  });

  @override
  Widget build(BuildContext context) {
    final fee = card.lifetimeFree || card.annualFee == 0
        ? 'No annual fee'
        : 'Annual fee ₹${card.annualFee?.round()}';

    return Column(
      children: [
        CheckboxListTile(
          value: selected,
          onChanged: (value) => onToggle(value ?? false),
          // The checkbox moves to the trailing edge so the card picture can
          // lead the row, which makes a long list far easier to scan.
          controlAffinity: ListTileControlAffinity.trailing,
          secondary: CardArt(card: card, width: 56),
          title: Text(card.displayName),
          subtitle: Text(
            '$fee • ${card.rewardType}'
            '${card.lastChanged != null ? ' • terms last changed ${card.lastChanged}' : ''}',
          ),
        ),
        // Cycle spend only changes the answer for cards with spend tiers, so
        // we only ask for it on those cards rather than cluttering every row.
        if (selected && _hasSpendTiers(card))
          Padding(
            padding: const EdgeInsets.fromLTRB(72, 0, 16, 12),
            child: _CycleSpendField(card: card, store: store),
          ),
      ],
    );
  }

  /// True when the card pays a different rate once you have spent enough in
  /// the current statement cycle.
  static bool _hasSpendTiers(CardRule card) {
    final labels = card.categoryRates
        .map((r) => r.label?.toLowerCase() ?? '')
        .where((l) => l.isNotEmpty);
    return labels.any((l) => l.contains('up to')) &&
        labels.any((l) => l.contains('above'));
  }
}

class _CycleSpendField extends StatefulWidget {
  final CardRule card;
  final UserCardsStore store;

  const _CycleSpendField({required this.card, required this.store});

  @override
  State<_CycleSpendField> createState() => _CycleSpendFieldState();
}

class _CycleSpendFieldState extends State<_CycleSpendField> {
  final _controller = TextEditingController();

  @override
  void initState() {
    super.initState();
    widget.store.cycleSpend(widget.card.id).then((value) {
      if (!mounted || value <= 0) return;
      _controller.text = value.round().toString();
    });
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return TextField(
      controller: _controller,
      keyboardType: TextInputType.number,
      decoration: const InputDecoration(
        labelText: 'Spent so far this statement cycle',
        helperText: 'This card pays more once you pass a spending threshold.',
        prefixText: '₹',
        isDense: true,
      ),
      onChanged: (value) {
        final amount = double.tryParse(value.replaceAll(',', '')) ?? 0;
        widget.store.setCycleSpend(widget.card.id, amount);
      },
    );
  }
}
