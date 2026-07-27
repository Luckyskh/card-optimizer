/// Tests for the two pieces that decide whether a user gets notified.
///
/// The first group is the important one. If normalisation is too eager the
/// monitor misses real devaluations; if it is too timid it cries wolf every
/// fortnight and people stop reading the alerts. Both failures are quiet, so
/// they need tests.
library;

import 'package:test/test.dart';

import 'package:terms_watch/diff.dart';
import 'package:terms_watch/extract.dart';
import 'package:terms_watch/normalize.dart';

void main() {
  group('normalisation ignores noise', () {
    test('a new "last updated" date alone does not count as a change', () {
      const before = '''
Most Important Terms and Conditions
Last updated on Jul 2nd, 2026
5% cashback on all online spends, capped at Rs 2,000 per month.
''';
      const after = '''
Most Important Terms and Conditions
Last updated on Aug 16th, 2026
5% cashback on all online spends, capped at Rs 2,000 per month.
''';

      expect(normalize(before), normalize(after),
          reason: 'a reprint with a new date must not alert anyone');
    });

    test('a new version stamp alone does not count as a change', () {
      const before = 'MITC 12 PAGES Ver. 1.76\nAnnual fee Rs 999.';
      const after = 'MITC 12 PAGES Ver. 1.81\nAnnual fee Rs 999.';

      expect(normalize(before), normalize(after));
    });

    test('page numbers and re-wrapped whitespace are ignored', () {
      const before = 'Fees   and    charges\n1\nAnnual fee Rs 999.\nPage 2 of 9';
      const after = 'Fees and charges\n2\nAnnual fee Rs 999.\nPage 3 of 9';

      expect(normalize(before), normalize(after));
    });

    test('a date inside an actual term is kept, not masked', () {
      // This is the line the monitor exists to catch. If dates were stripped
      // everywhere, this change would be invisible.
      const before = 'Cap cut to Rs 5,000 with effect from 1 Apr 2026.';
      const after = 'Cap cut to Rs 2,000 with effect from 1 Apr 2026.';

      expect(normalize(before), isNot(normalize(after)));
      expect(normalize(before), contains('1 Apr 2026'));
    });
  });

  group('normalisation keeps real changes', () {
    test('a changed cap is a change', () {
      const before = '5% cashback capped at Rs 5,000 per month.';
      const after = '5% cashback capped at Rs 2,000 per month.';

      expect(normalize(before), isNot(normalize(after)));
    });

    test('a removed benefit is a change', () {
      const before = 'Complimentary domestic lounge access, 4 visits a year.';
      const after = '';

      expect(normalize(before), isNot(normalize(after)));
    });
  });

  group('diffing picks out what matters', () {
    test('a cap cut is paired into a single before/after', () {
      final result = diffLines(
        ['5% cashback capped at Rs 5,000 per month.', 'Unrelated line.'],
        ['5% cashback capped at Rs 2,000 per month.', 'Unrelated line.'],
      );

      expect(result.material, hasLength(1));
      expect(result.material.single.isEdit, isTrue);
      expect(result.material.single.before, contains('5,000'));
      expect(result.material.single.after, contains('2,000'));
    });

    test('a newly added cap clause pairs with the line it was added to', () {
      // The commonest devaluation shape, and the one a plain word-overlap
      // score gets wrong: every word of the old line survives, so the two
      // should read as one edit rather than a deletion and an addition.
      final result = diffLines(
        ['5% Cashback on online spends'],
        ['5% Cashback on online spends, capped at Rs 500 per month'],
      );

      expect(result.material, hasLength(1));
      expect(result.material.single.isEdit, isTrue);
      expect(result.material.single.after, contains('capped'));
    });

    test('short boilerplate is not paired with any longer line', () {
      final result = diffLines(
        ['Terms apply'],
        ['Terms apply to the 5% cashback offer, capped at Rs 500 per month'],
      );

      // Two separate entries, because "Terms apply" is too short to anchor a
      // confident before/after.
      expect(result.all.where((e) => e.isEdit), isEmpty);
    });

    test('a changed phone number is reported but not treated as material', () {
      final result = diffLines(
        ['Call us on 1800 200 1234 for assistance.'],
        ['Call us on 1800 200 9999 for assistance.'],
      );

      expect(result.hasChanges, isTrue);
      expect(result.material, isEmpty,
          reason: 'a support number is not a devaluation');
    });

    test('a notice-page announcement is material', () {
      // The exact shape of an SBI customer notice. Nothing here mentions a
      // rupee amount, so the numeric test does not catch it - the wording has
      // to.
      final result = diffLines(
        [],
        ['Effective 1 Jul 2026, the Reward Points Programme on PhonePe SBI '
            'Credit Card PURPLE will be revised.'],
      );

      expect(result.material, hasLength(1));
    });

    test('an improvement is flagged, not just a cut', () {
      // A raised cap means the app is now understating what the card pays,
      // which is worth telling someone about.
      //
      // These two lines are reported separately rather than as one edit:
      // "capped at" to "cap enhanced to" rewrites too much of the sentence to
      // pair confidently. That is the intended trade-off - showing both lines
      // is honest, whereas pairing loosely enough to catch this would start
      // pairing genuinely unrelated sentences.
      final result = diffLines(
        ['Monthly cashback capped at Rs 500.'],
        ['Monthly cashback cap enhanced to Rs 1,000.'],
      );

      expect(result.material, hasLength(2));
      expect(
        result.material.any((e) => '${e.before}${e.after}'.contains('1,000')),
        isTrue,
      );
    });

    test('an identical document produces no changes at all', () {
      final lines = ['Annual fee Rs 999.', 'Base rate 1%.'];
      expect(diffLines(lines, lines).hasChanges, isFalse);
    });

    test('a removed lounge benefit is material', () {
      final result = diffLines(
        ['Complimentary domestic lounge access, 4 visits a year.'],
        [],
      );

      expect(result.material, hasLength(1));
      expect(result.material.single.after, isEmpty);
    });

    test('the summary counts material lines, not every line', () {
      final result = diffLines(
        ['Rate is 5%.', 'Our address is 12 Old Street.'],
        ['Rate is 3%.', 'Our address is 44 New Street.'],
      );

      expect(result.summary, contains('1 changed line'));
    });
  });

  group('HTML extraction', () {
    test('scripts, styles and navigation are dropped', () {
      final html = '''
<html>
  <head><style>.a { color: red; }</style></head>
  <body>
    <nav><a href="/x">Menu item that changes often</a></nav>
    <script>var tracking = Date.now();</script>
    <p>5% cashback capped at Rs 2,000 per month.</p>
    <footer>Copyright 2026</footer>
  </body>
</html>
''';

      final result = extractHtmlText(html.codeUnits);

      expect(result.ok, isTrue);
      expect(result.text, contains('5% cashback'));
      expect(result.text, isNot(contains('tracking')));
      expect(result.text, isNot(contains('Menu item')));
      expect(result.text, isNot(contains('color: red')));
    });

    test('rupee and ampersand entities are decoded', () {
      final result = extractHtmlText(
          '<p>Fee &#8377;999 &amp; taxes</p>'.codeUnits);

      expect(result.text, contains('₹999'));
      expect(result.text, contains('& taxes'));
    });

    test('an empty page is reported as a failure, not as empty text', () {
      // Important: returning "" here would look like the issuer deleted the
      // entire document and would fire an alarm at every user.
      final result = extractHtmlText('<html><body></body></html>'.codeUnits);

      expect(result.ok, isFalse);
      expect(result.error, isNotNull);
    });
  });
}
