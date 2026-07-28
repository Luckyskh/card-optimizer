/// "Where can I move my points, and is it worth it?"
///
/// Only shows the cards you actually hold — a list of every issuer's transfer
/// partners is a research document, not something you use. Enter a balance and
/// it works out what that becomes with each partner.
library;

import 'package:flutter/material.dart';

import '../data/rules_repository.dart';
import '../data/user_cards_store.dart';
import '../models/card.dart';
import '../models/rules.dart';
import '../widgets/card_art.dart';

class TransferPartnersScreen extends StatefulWidget {
  final RulesRepository rulesRepository;
  final UserCardsStore store;

  /// Lets the parent tell this screen to reload when the card list changes.
  final Listenable refreshSignal;

  const TransferPartnersScreen({
    super.key,
    required this.rulesRepository,
    required this.store,
    required this.refreshSignal,
  });

  @override
  State<TransferPartnersScreen> createState() =>
      _TransferPartnersScreenState();
}

class _TransferPartnersScreenState extends State<TransferPartnersScreen> {
  final _pointsController = TextEditingController(text: '10000');

  Rules? _rules;
  Set<String> _owned = {};

  @override
  void initState() {
    super.initState();
    widget.refreshSignal.addListener(_load);
    _load();
  }

  @override
  void dispose() {
    widget.refreshSignal.removeListener(_load);
    _pointsController.dispose();
    super.dispose();
  }

  Future<void> _load() async {
    final rules = await widget.rulesRepository.load();
    final owned = await widget.store.ownedCardIds();
    if (!mounted) return;
    setState(() {
      _rules = rules;
      _owned = owned;
    });
  }

  double get _points =>
      double.tryParse(_pointsController.text.replaceAll(',', '')) ?? 0;

  @override
  Widget build(BuildContext context) {
    final rules = _rules;
    if (rules == null) {
      return const Center(child: CircularProgressIndicator());
    }

    final mine = rules.cardsByIds(_owned);
    final transferable = mine
        .where((c) => c.transferPartners?.isEmpty == false)
        .toList();

    if (mine.isEmpty) {
      return const _Empty(
        title: 'Add your cards first',
        body: 'Open the My cards tab and tick the cards you have. This tab '
            'then shows where those cards\' points can be moved.',
      );
    }

    if (transferable.isEmpty) {
      return _Empty(
        title: 'None of your cards transfer points',
        body: 'Of the ${mine.length} card${mine.length == 1 ? '' : 's'} you '
            'have added, none has an airline or hotel transfer programme in '
            'the dataset. Cashback cards never do, and for points cards the '
            'partner list is often published separately from the card terms.',
      );
    }

    return ListView(
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 16, 16, 8),
          child: TextField(
            controller: _pointsController,
            keyboardType: TextInputType.number,
            decoration: const InputDecoration(
              labelText: 'Points or miles you hold',
              helperText: 'Shows what this becomes with each partner.',
              isDense: true,
            ),
            onChanged: (_) => setState(() {}),
          ),
        ),
        for (final card in transferable)
          _CardPartners(card: card, points: _points),
        const SizedBox(height: 24),
      ],
    );
  }
}

class _CardPartners extends StatelessWidget {
  final CardRule card;
  final double points;

  const _CardPartners({required this.card, required this.points});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final transfers = card.transferPartners!;

    return Card(
      margin: const EdgeInsets.fromLTRB(12, 4, 12, 8),
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                CardArt(card: card, width: 48),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(card.displayName,
                          style: theme.textTheme.titleMedium),
                      if (card.pointCurrency != null)
                        Text('Transfers ${card.pointCurrency}',
                            style: theme.textTheme.bodySmall),
                    ],
                  ),
                ),
              ],
            ),

            if (card.pointValueNote != null) ...[
              const SizedBox(height: 8),
              Text(card.pointValueNote!,
                  style: theme.textTheme.bodySmall
                      ?.copyWith(fontStyle: FontStyle.italic)),
            ],

            for (final group in transfers.groups) ...[
              const Divider(height: 20),
              _Group(group: group, points: points),
            ],

            if (transfers.removed.isNotEmpty) ...[
              const Divider(height: 20),
              Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Icon(Icons.remove_circle_outline,
                      size: 18, color: theme.colorScheme.error),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          'Removed${transfers.removedOn != null ? ' on ${transfers.removedOn}' : ''}',
                          style: theme.textTheme.bodyMedium?.copyWith(
                            fontWeight: FontWeight.w600,
                            color: theme.colorScheme.error,
                          ),
                        ),
                        Text(transfers.removed.join(' · '),
                            style: theme.textTheme.bodySmall),
                        const SizedBox(height: 4),
                        // Not decoration: a programme that has already lost
                        // partners is evidence about how safe the rest are.
                        Text(
                          'Partners can be withdrawn without notice. These '
                          'were.',
                          style: theme.textTheme.bodySmall
                              ?.copyWith(fontStyle: FontStyle.italic),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
            ],
          ],
        ),
      ),
    );
  }
}

class _Group extends StatelessWidget {
  final TransferGroup group;
  final double points;

  const _Group({required this.group, required this.points});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final multiplier = group.multiplier;

    // What the balance becomes, and what the annual ceiling allows.
    final converted = multiplier == null ? null : points * multiplier;
    final cap = group.annualCapMiles;
    final overCap = cap != null && converted != null && converted > cap;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            Expanded(
              child: Text(
                group.ratio == null
                    ? _pretty(group.name)
                    : '${_pretty(group.name)} · ${group.ratio}',
                style: theme.textTheme.titleSmall,
              ),
            ),
            if (converted != null)
              Text(
                '${_thousands(overCap ? cap : converted)} miles',
                style: theme.textTheme.titleSmall?.copyWith(
                  fontWeight: FontWeight.w700,
                  color: theme.colorScheme.primary,
                ),
              ),
          ],
        ),
        if (overCap)
          Padding(
            padding: const EdgeInsets.only(top: 2),
            child: Text(
              'Capped: ${_thousands(converted)} miles would exceed the '
              '${_thousands(cap)} a year this group allows.',
              style: theme.textTheme.bodySmall
                  ?.copyWith(color: theme.colorScheme.error),
            ),
          )
        else if (cap != null)
          Padding(
            padding: const EdgeInsets.only(top: 2),
            child: Text('Up to ${_thousands(cap)} miles a year',
                style: theme.textTheme.bodySmall),
          ),
        const SizedBox(height: 6),
        Wrap(
          spacing: 6,
          runSpacing: 6,
          children: [
            for (final partner in group.partners)
              Chip(
                label: Text(partner, style: theme.textTheme.bodySmall),
                visualDensity: VisualDensity.compact,
                materialTapTargetSize: MaterialTapTargetSize.shrinkWrap,
              ),
          ],
        ),
      ],
    );
  }

  static String _pretty(String groupName) {
    final cleaned = groupName.replaceAll('_', ' ');
    return cleaned.isEmpty
        ? cleaned
        : cleaned[0].toUpperCase() + cleaned.substring(1);
  }
}

/// Indian digit grouping: 1,20,000 rather than 120,000 — last three digits,
/// then pairs.
String _thousands(double value) {
  final whole = value.round().abs().toString();
  final sign = value < 0 ? '-' : '';
  if (whole.length <= 3) return '$sign$whole';

  final last3 = whole.substring(whole.length - 3);
  var rest = whole.substring(0, whole.length - 3);

  final pairs = <String>[];
  while (rest.length > 2) {
    pairs.insert(0, rest.substring(rest.length - 2));
    rest = rest.substring(0, rest.length - 2);
  }
  if (rest.isNotEmpty) pairs.insert(0, rest);

  return '$sign${pairs.join(',')},$last3';
}

class _Empty extends StatelessWidget {
  final String title;
  final String body;

  const _Empty({required this.title, required this.body});

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(32),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Icon(Icons.flight_takeoff, size: 48),
            const SizedBox(height: 16),
            Text(title, style: Theme.of(context).textTheme.titleMedium),
            const SizedBox(height: 8),
            Text(body,
                textAlign: TextAlign.center,
                style: Theme.of(context).textTheme.bodySmall),
          ],
        ),
      ),
    );
  }
}
