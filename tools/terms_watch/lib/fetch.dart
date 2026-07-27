/// Downloads a terms document.
///
/// Sounds trivial; is not. Several Indian banks put their public disclosure
/// documents behind bot protection that returns 403 or simply hangs. HDFC in
/// particular answered some requests and refused others within the same
/// minute, which reads like rate limiting rather than a policy against being
/// read at all.
///
/// So this file does three things beyond a plain GET:
///
/// * identifies itself with an ordinary browser User-Agent, because the
///   default Dart one gets refused outright;
/// * retries with growing pauses, since most refusals are temporary;
/// * reports failure honestly instead of returning empty content, because an
///   empty document would look exactly like "the issuer deleted everything"
///   and would fire a false alarm at every user of the app.
///
/// We fetch each document twice a month. That is gentler than a single person
/// refreshing the page.
library;

import 'dart:async';
import 'dart:io';

import 'package:http/http.dart' as http;

/// What came back from an attempt to download a document.
class FetchResult {
  final bool ok;
  final List<int> bytes;
  final String? contentType;
  final int? statusCode;

  /// Human-readable failure description, null when [ok].
  final String? error;

  const FetchResult({
    required this.ok,
    this.bytes = const [],
    this.contentType,
    this.statusCode,
    this.error,
  });

  /// True when the bytes are a PDF.
  ///
  /// Checked from the content type *and* the file's own first four bytes,
  /// never from the URL. ICICI serves a real PDF from a URL ending `.page`,
  /// and trusting the extension there would mean feeding HTML to a PDF reader.
  bool get isPdf {
    if (bytes.length >= 4 &&
        bytes[0] == 0x25 && // %
        bytes[1] == 0x50 && // P
        bytes[2] == 0x44 && // D
        bytes[3] == 0x46) {
      // F
      return true;
    }
    return contentType?.toLowerCase().contains('pdf') ?? false;
  }
}

/// A normal desktop Chrome User-Agent. Dart's default identifies itself as a
/// script and is refused by several of the issuer sites.
const _userAgent = 'Mozilla/5.0 (Windows NT 10.0; Win64; x64) '
    'AppleWebKit/537.36 (KHTML, like Gecko) Chrome/126.0.0.0 Safari/537.36';

const _headers = {
  'User-Agent': _userAgent,
  'Accept': 'text/html,application/xhtml+xml,application/pdf,*/*;q=0.8',
  'Accept-Language': 'en-US,en;q=0.9',
  'Upgrade-Insecure-Requests': '1',
};

/// Pauses between attempts. Short, then long, then longer — a blocked request
/// that is going to succeed usually does so within a minute.
const _backoff = [
  Duration(seconds: 2),
  Duration(seconds: 8),
  Duration(seconds: 30),
];

/// Downloads [url], retrying on failure, and falling back to curl.
///
/// Never throws: every failure mode comes back as a [FetchResult] with
/// `ok == false` and an explanation.
Future<FetchResult> fetchDocument(
  String url, {
  int attempts = 3,
  Duration timeout = const Duration(seconds: 60),
  http.Client? client,
  Future<void> Function(Duration)? sleep,
  bool allowCurlFallback = true,
}) async {
  final direct = await _fetchWithDart(
    url,
    attempts: attempts,
    timeout: timeout,
    client: client,
    sleep: sleep,
  );
  if (direct.ok || !allowCurlFallback) return direct;

  // Some issuers refuse Dart outright. ICICI answers curl and a browser with
  // a 200 and Dart with a 403 no matter what headers Dart sends, which points
  // at the TLS handshake rather than anything in the request. Retrying through
  // curl — an ordinary HTTP client, present on the CI runner and on Windows —
  // is enough to read those documents.
  if (!isCurlAvailable()) return direct;

  final viaCurl = await _fetchWithCurl(url, timeout: timeout);
  if (viaCurl.ok) return viaCurl;

  // Report whichever failure is more informative.
  return FetchResult(
    ok: false,
    statusCode: viaCurl.statusCode ?? direct.statusCode,
    error: '${direct.error} (curl also failed: ${viaCurl.error})',
  );
}

/// True when curl can be run.
bool isCurlAvailable() {
  try {
    final result = Process.runSync('curl', ['--version']);
    return result.exitCode == 0;
  } catch (_) {
    return false;
  }
}

/// Downloads through curl, writing the body to a temporary file so binary
/// PDFs survive intact.
Future<FetchResult> _fetchWithCurl(
  String url, {
  required Duration timeout,
}) async {
  final tempDir = await Directory.systemTemp.createTemp('terms_watch_curl');
  final bodyFile = File('${tempDir.path}/body');
  final headerFile = File('${tempDir.path}/headers');

  try {
    final result = await Process.run('curl', [
      '--silent',
      '--show-error',
      '--location', // follow redirects
      '--max-time', '${timeout.inSeconds}',
      '--user-agent', _userAgent,
      '--header', 'Accept-Language: en-US,en;q=0.9',
      '--output', bodyFile.path,
      '--dump-header', headerFile.path,
      '--write-out', '%{http_code}',
      url,
    ]);

    final status = int.tryParse((result.stdout as String).trim());

    if (result.exitCode != 0) {
      return FetchResult(
        ok: false,
        statusCode: status,
        error: 'curl exited ${result.exitCode}: '
            '${(result.stderr as String).trim()}',
      );
    }

    if (status != 200) {
      return FetchResult(ok: false, statusCode: status, error: 'HTTP $status');
    }

    final bytes = await bodyFile.readAsBytes();
    if (bytes.isEmpty) {
      return const FetchResult(
        ok: false,
        error: 'curl returned an empty response',
      );
    }

    return FetchResult(
      ok: true,
      bytes: bytes,
      contentType: _contentTypeFrom(headerFile),
      statusCode: status,
    );
  } catch (e) {
    return FetchResult(ok: false, error: 'curl failed: $e');
  } finally {
    await tempDir.delete(recursive: true).catchError((_) => tempDir);
  }
}

String? _contentTypeFrom(File headerFile) {
  if (!headerFile.existsSync()) return null;
  try {
    // With redirects there may be several header blocks; the last content-type
    // is the one describing the body we actually saved.
    String? found;
    for (final line in headerFile.readAsLinesSync()) {
      if (line.toLowerCase().startsWith('content-type:')) {
        found = line.substring(line.indexOf(':') + 1).trim();
      }
    }
    return found;
  } catch (_) {
    return null;
  }
}

Future<FetchResult> _fetchWithDart(
  String url, {
  required int attempts,
  required Duration timeout,
  http.Client? client,
  Future<void> Function(Duration)? sleep,
}) async {
  final ownedClient = client == null;
  final httpClient = client ?? http.Client();
  final pause = sleep ?? Future<void>.delayed;

  String? lastError;
  int? lastStatus;

  try {
    for (var attempt = 0; attempt < attempts; attempt++) {
      if (attempt > 0) {
        await pause(_backoff[(attempt - 1).clamp(0, _backoff.length - 1)]);
      }

      try {
        final response = await httpClient
            .get(Uri.parse(url), headers: _headers)
            .timeout(timeout);

        lastStatus = response.statusCode;

        if (response.statusCode == 200) {
          if (response.bodyBytes.isEmpty) {
            lastError = 'the server returned an empty response';
            continue;
          }
          return FetchResult(
            ok: true,
            bytes: response.bodyBytes,
            contentType: response.headers['content-type'],
            statusCode: response.statusCode,
          );
        }

        lastError = 'HTTP ${response.statusCode}';
        // A 404 means the document moved. Retrying will not help, and the
        // right fix is to update sources.json, so stop early and say so.
        if (response.statusCode == 404) {
          lastError = 'HTTP 404 - the document has moved, update sources.json';
          break;
        }
      } on TimeoutException {
        lastError = 'timed out after ${timeout.inSeconds}s';
      } on SocketException catch (e) {
        lastError = 'network error: ${e.message}';
      } on http.ClientException catch (e) {
        lastError = 'request failed: ${e.message}';
      } catch (e) {
        lastError = 'unexpected error: $e';
      }
    }
  } finally {
    if (ownedClient) httpClient.close();
  }

  return FetchResult(
    ok: false,
    statusCode: lastStatus,
    error: lastError ?? 'unknown failure',
  );
}
