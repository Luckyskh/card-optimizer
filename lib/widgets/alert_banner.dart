/// The strip that appears when an issuer has changed a card's terms.
library;

import 'package:flutter/material.dart';

import '../data/alerts_service.dart';

class AlertBanner extends StatelessWidget {
  final List<TermsAlert> alerts;
  final VoidCallback onDismiss;

  const AlertBanner({
    super.key,
    required this.alerts,
    required this.onDismiss,
  });

  @override
  Widget build(BuildContext context) {
    if (alerts.isEmpty) return const SizedBox.shrink();

    final theme = Theme.of(context);
    final cards = alerts.map((a) => a.cardName).toSet().toList();

    return Material(
      color: theme.colorScheme.tertiaryContainer,
      child: InkWell(
        onTap: () => _showDetails(context),
        child: Padding(
          padding: const EdgeInsets.fromLTRB(16, 12, 8, 12),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Icon(Icons.info_outline,
                  color: theme.colorScheme.onTertiaryContainer),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      cards.length == 1
                          ? '${cards.single}: the issuer changed its terms'
                          : '${cards.length} of your cards had their terms '
                              'changed',
                      style: theme.textTheme.bodyMedium?.copyWith(
                        fontWeight: FontWeight.w600,
                        color: theme.colorScheme.onTertiaryContainer,
                      ),
                    ),
                    const SizedBox(height: 2),
                    Text(
                      'The rates in this app may be out of date. Tap to see '
                      'what changed.',
                      style: theme.textTheme.bodySmall?.copyWith(
                        color: theme.colorScheme.onTertiaryContainer,
                      ),
                    ),
                  ],
                ),
              ),
              IconButton(
                icon: const Icon(Icons.close),
                tooltip: 'Dismiss',
                color: theme.colorScheme.onTertiaryContainer,
                onPressed: onDismiss,
              ),
            ],
          ),
        ),
      ),
    );
  }

  void _showDetails(BuildContext context) {
    showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      builder: (context) => DraggableScrollableSheet(
        expand: false,
        initialChildSize: 0.6,
        maxChildSize: 0.9,
        builder: (context, controller) => ListView(
          controller: controller,
          padding: const EdgeInsets.all(16),
          children: [
            Text(
              'Terms changes',
              style: Theme.of(context).textTheme.titleLarge,
            ),
            const SizedBox(height: 8),
            Text(
              'These are differences spotted in the issuers\' own published '
              'documents. They tell you something moved — they do not tell you '
              'the new rate. Check the linked document before relying on it.',
              style: Theme.of(context).textTheme.bodySmall,
            ),
            const Divider(height: 32),
            for (final alert in alerts) _AlertDetail(alert: alert),
          ],
        ),
      ),
    );
  }
}

class _AlertDetail extends StatelessWidget {
  final TermsAlert alert;

  const _AlertDetail({required this.alert});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return Padding(
      padding: const EdgeInsets.only(bottom: 24),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(alert.cardName, style: theme.textTheme.titleMedium),
          Text(
            '${alert.docLabel} • spotted ${alert.detectedOn}',
            style: theme.textTheme.bodySmall,
          ),
          const SizedBox(height: 8),
          Text(alert.summary, style: theme.textTheme.bodyMedium),
          if (alert.excerpts.isNotEmpty) ...[
            const SizedBox(height: 12),
            for (final excerpt in alert.excerpts.take(5))
              Container(
                width: double.infinity,
                margin: const EdgeInsets.only(bottom: 8),
                padding: const EdgeInsets.all(10),
                decoration: BoxDecoration(
                  color: theme.colorScheme.surfaceContainerHighest,
                  borderRadius: BorderRadius.circular(8),
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    if (excerpt.before.isNotEmpty)
                      Text('was: ${excerpt.before}',
                          style: theme.textTheme.bodySmall),
                    if (excerpt.after.isNotEmpty)
                      Text('now: ${excerpt.after}',
                          style: theme.textTheme.bodySmall?.copyWith(
                            fontWeight: FontWeight.w600,
                          )),
                  ],
                ),
              ),
          ],
          if (alert.sourceUrl.isNotEmpty)
            Text(
              alert.sourceUrl,
              style: theme.textTheme.bodySmall
                  ?.copyWith(color: theme.colorScheme.primary),
            ),
        ],
      ),
    );
  }
}
