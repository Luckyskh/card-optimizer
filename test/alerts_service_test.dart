/// Tests for the app's handling of `alerts.json`.
///
/// The rule this file exists to protect: **a problem fetching alerts must
/// never break the app**. The reward maths is entirely offline, and a GitHub
/// outage, a typo in the JSON, or a plane journey must not change that.
library;

import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:card_optimizer/data/alerts_service.dart';

/// A realistic file, matching what `check_terms.dart` actually writes.
final validAlerts = json.encode({
  'generated_on': '2026-08-01T03:12:00Z',
  'rules_version': 1,
  'alerts': [
    {
      'id': '2026-08-01-hdfc-swiggy-swiggy-ornge-hdfc',
      'card_id': 'swiggy-ornge-hdfc',
      'card_name': 'HDFC Bank Swiggy ORNGE',
      'doc_label': 'Swiggy HDFC Bank card page',
      'detected_on': '2026-08-01',
      'summary': '2 changed lines mentioning rates, caps or fees',
      'source_url': 'https://example.test/swiggy',
      'excerpts': [
        {
          'before': '10% cashback on Swiggy food order',
          'after': '6% cashback on Swiggy food order',
        }
      ],
    }
  ],
});

/// A service pointed at a fake server rather than the real GitHub URL.
AlertsService serviceReturning(String body, {int status = 200}) {
  return AlertsService(
    url: 'https://example.test/alerts.json',
    client: MockClient((_) async => http.Response(body, status)),
  );
}

void main() {
  setUp(() => SharedPreferences.setMockInitialValues({}));

  group('parsing', () {
    test('a well-formed file produces alerts', () {
      final alerts = AlertsService.parseAlerts(validAlerts);

      expect(alerts, hasLength(1));
      expect(alerts.single.cardId, 'swiggy-ornge-hdfc');
      expect(alerts.single.excerpts.single.after, contains('6%'));
    });

    test('malformed JSON produces no alerts instead of throwing', () {
      expect(AlertsService.parseAlerts('{not json at all'), isEmpty);
    });

    test('a file with no alerts key produces no alerts', () {
      expect(AlertsService.parseAlerts('{"generated_on": "x"}'), isEmpty);
    });

    test('entries missing an id are dropped', () {
      final body = json.encode({
        'alerts': [
          {'card_id': 'a'},
          {'id': 'keep-me', 'card_id': 'b'},
        ]
      });

      final alerts = AlertsService.parseAlerts(body);
      expect(alerts, hasLength(1));
      expect(alerts.single.id, 'keep-me');
    });
  });

  group('failure never breaks the app', () {
    test('a server error yields an empty list, not an exception', () async {
      final service = serviceReturning('nope', status: 500);
      expect(await service.fetch(), isEmpty);
    });

    test('a network failure yields an empty list', () async {
      final service = AlertsService(
        url: 'https://example.test/alerts.json',
        client: MockClient((_) async => throw const SocketishFailure()),
      );
      expect(await service.fetch(), isEmpty);
    });

    test('an unconfigured URL skips the network entirely', () async {
      // Guards the fork case: someone copies the project, has not pointed
      // alerts.json at their own repo yet, and should get silence rather than
      // a stream of failed requests.
      var called = false;
      final service = AlertsService(
        url: 'https://raw.githubusercontent.com/OWNER/REPO/main/alerts.json',
        client: MockClient((_) async {
          called = true;
          return http.Response(validAlerts, 200);
        }),
      );

      expect(service.isConfigured, isFalse);
      expect(await service.fetch(), isEmpty);
      expect(called, isFalse);
    });

    test('the shipped default URL is configured', () async {
      // If this fails, the app has been published without a working alerts
      // address and no user would ever hear about a devaluation.
      expect(AlertsService().isConfigured, isTrue);
      expect(AlertsService.defaultAlertsUrl, startsWith('https://'));
      expect(AlertsService.defaultAlertsUrl, endsWith('/alerts.json'));
    });
  });

  group('seen alerts', () {
    test('an alert is unseen until it is marked', () async {
      final service = serviceReturning(validAlerts);
      const id = '2026-08-01-hdfc-swiggy-swiggy-ornge-hdfc';

      expect(await service.seenIds(), isEmpty);

      await service.markSeen(id);
      expect(await service.seenIds(), contains(id));
    });

    test('marking all seen empties the unseen list', () async {
      final service = serviceReturning(validAlerts);

      final before = await service.unseen();
      expect(before, hasLength(1));

      await service.markAllSeen(before.map((a) => a.id));
      expect(await service.unseen(), isEmpty);
    });
  });
}

/// Stands in for a dropped connection.
class SocketishFailure implements Exception {
  const SocketishFailure();
}
