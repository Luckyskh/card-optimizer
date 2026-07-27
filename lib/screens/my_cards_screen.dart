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
        // Grouped by issuing bank, and collapsed by default. A bank you hold
        // a card from opens automatically, so returning to this screen shows
        // your own cards without any tapping.
        for (final entry in rules.cardsByBank.entries)
          _BankGroup(
            bank: entry.key,
            cards: entry.value,
            owned: _owned,
            store: widget.store,
            onToggle: _toggle,
          ),
        const SizedBox(height: 24),
      ],
    );
  }
}

/// One collapsible bank, with its cards inside.
class _BankGroup extends StatelessWidget {
  final String bank;
  final List<CardRule> cards;
  final Set<String> owned;
  final UserCardsStore store;
  final void Function(CardRule, bool) onToggle;

  const _BankGroup({
    required this.bank,
    required this.cards,
    required this.owned,
    required this.store,
    required this.onToggle,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final held = cards.where((c) => owned.contains(c.id)).length;

    return ExpansionTile(
      // Opening the banks you already hold means the common case - coming back
      // to check or change something - needs no tapping at all.
      initiallyExpanded: held > 0,
      title: Text(bank, style: theme.textTheme.titleMedium),
      subtitle: Text(
        held > 0
            ? '$held of ${cards.length} added'
            : '${cards.length} card${cards.length == 1 ? '' : 's'}',
        style: theme.textTheme.bodySmall?.copyWith(
          color: held > 0 ? theme.colorScheme.primary : null,
        ),
      ),
      // A stack of the bank's card art, so you can recognise the bank without
      // reading the name.
      leading: SizedBox(
        width: 44,
        height: 36,
        child: Stack(
          children: [
            for (var i = cards.length.clamp(0, 3) - 1; i >= 0; i--)
              Positioned(
                left: i * 5.0,
                top: i * 3.0,
                child: CardArt(card: cards[i], width: 32),
              ),
          ],
        ),
      ),
      children: [
        for (final card in cards)
          _CardTile(
            card: card,
            selected: owned.contains(card.id),
            store: store,
            onToggle: (value) => onToggle(card, value),
          ),
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
