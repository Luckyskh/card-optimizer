/// Turns a downloaded document into plain text.
///
/// PDFs go through `pdftotext`, part of the poppler-utils package. There is no
/// good pure-Dart PDF text reader, and shelling out to a mature C++ one beats
/// writing a bad parser. The GitHub Actions workflow installs it with a single
/// apt-get line.
///
/// HTML is handled here directly, since stripping tags is simple enough not to
/// warrant a dependency.
library;

import 'dart:convert';
import 'dart:io';

/// The outcome of trying to read a document's text.
class ExtractResult {
  final bool ok;
  final String text;
  final String? error;

  const ExtractResult({required this.ok, this.text = '', this.error});
}

/// True when `pdftotext` is installed and runnable.
///
/// Checked up front so the script can say "install poppler-utils" once rather
/// than failing on every PDF in the list.
bool isPdfToolAvailable() {
  try {
    final result = Process.runSync('pdftotext', ['-v']);
    // pdftotext prints its version banner to stderr and exits 0 or 99
    // depending on the build, so presence matters more than the exit code.
    return result.exitCode == 0 ||
        result.stderr.toString().toLowerCase().contains('pdftotext');
  } catch (_) {
    return false;
  }
}

/// Reads the text out of a PDF.
///
/// `-layout` keeps the original column arrangement, which matters because
/// reward tables in these documents lose all meaning when flattened into one
/// column — a rate and its cap would end up on separate lines.
Future<ExtractResult> extractPdfText(List<int> bytes) async {
  if (!isPdfToolAvailable()) {
    return const ExtractResult(
      ok: false,
      error: 'pdftotext is not installed. On Ubuntu run '
          '"sudo apt-get install poppler-utils"; on Windows install poppler '
          'and add its bin folder to PATH. GitHub Actions installs it for you.',
    );
  }

  final tempDir = await Directory.systemTemp.createTemp('terms_watch');
  final tempFile = File('${tempDir.path}/document.pdf');

  try {
    await tempFile.writeAsBytes(bytes);
    final result = await Process.run(
      'pdftotext',
      ['-layout', '-enc', 'UTF-8', tempFile.path, '-'],
      stdoutEncoding: utf8,
      stderrEncoding: utf8,
    );

    if (result.exitCode != 0) {
      return ExtractResult(
        ok: false,
        error: 'pdftotext exited ${result.exitCode}: ${result.stderr}',
      );
    }

    final text = result.stdout as String;
    if (text.trim().isEmpty) {
      // A scanned PDF with no text layer. Reporting this is better than
      // recording an empty snapshot, which would look like a huge change.
      return const ExtractResult(
        ok: false,
        error: 'the PDF contains no selectable text, so it is probably a '
            'scan. Comparing it would need OCR.',
      );
    }

    return ExtractResult(ok: true, text: text);
  } catch (e) {
    return ExtractResult(ok: false, error: 'could not read the PDF: $e');
  } finally {
    await tempDir.delete(recursive: true).catchError((_) => tempDir);
  }
}

/// Reads the visible text out of an HTML page.
///
/// Scripts, styles and navigation are removed first. Without that, a change to
/// an unrelated menu item or an analytics tag would register as a change to
/// the card's terms.
ExtractResult extractHtmlText(List<int> bytes) {
  try {
    // Bank pages are UTF-8 in practice; allowMalformed stops one stray byte
    // from failing the whole run.
    var html = utf8.decode(bytes, allowMalformed: true);

    html = _removeElement(html, 'script');
    html = _removeElement(html, 'style');
    html = _removeElement(html, 'noscript');
    html = _removeElement(html, 'svg');
    html = _removeElement(html, 'nav');
    html = _removeElement(html, 'header');
    html = _removeElement(html, 'footer');
    html = _removeComments(html);

    // Turn block-level tags into line breaks so the text keeps its shape.
    html = html.replaceAll(
      RegExp(r'<\s*(br|/p|/div|/li|/tr|/h[1-6]|/table)[^>]*>',
          caseSensitive: false),
      '\n',
    );

    // Then drop every remaining tag.
    final text = _decodeEntities(html.replaceAll(RegExp('<[^>]*>'), ' '));

    if (text.trim().isEmpty) {
      return const ExtractResult(
        ok: false,
        error: 'the page had no readable text',
      );
    }

    return ExtractResult(ok: true, text: text);
  } catch (e) {
    return ExtractResult(ok: false, error: 'could not read the page: $e');
  }
}

String _removeElement(String html, String tag) => html.replaceAll(
      RegExp('<$tag[^>]*>.*?</$tag>',
          caseSensitive: false, dotAll: true),
      ' ',
    );

String _removeComments(String html) =>
    html.replaceAll(RegExp(r'<!--.*?-->', dotAll: true), ' ');

/// Converts the handful of HTML entities that actually appear in these pages.
String _decodeEntities(String text) {
  const entities = {
    '&nbsp;': ' ',
    '&amp;': '&',
    '&lt;': '<',
    '&gt;': '>',
    '&quot;': '"',
    '&#39;': "'",
    '&apos;': "'",
    '&rsquo;': "'",
    '&lsquo;': "'",
    '&ldquo;': '"',
    '&rdquo;': '"',
    '&ndash;': '-',
    '&mdash;': '-',
    '&hellip;': '...',
    '&rupee;': '₹',
    '&#8377;': '₹',
  };

  var result = text;
  entities.forEach((entity, replacement) {
    result = result.replaceAll(entity, replacement);
  });

  // Numeric entities we did not list explicitly.
  result = result.replaceAllMapped(
    RegExp(r'&#(\d+);'),
    (match) {
      final code = int.tryParse(match.group(1)!);
      return code == null ? match.group(0)! : String.fromCharCode(code);
    },
  );

  return result;
}
