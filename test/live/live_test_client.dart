/// Shared HTTP helper for live-bridge tests (`test/live`): real `HttpClient`
/// against `127.0.0.1` (no socket mocks), explicit tokens, verbatim headers.
library;

import 'dart:convert' show utf8;
import 'dart:io' show HttpClient, HttpOverrides;

/// Minimal response snapshot for assertions.
final class LiveResponse {
  const LiveResponse({
    required this.statusCode,
    required this.headers,
    required this.body,
  });

  final int statusCode;
  final Map<String, String> headers;
  final String body;
}

/// Pass-through overrides restoring the real client inside the test zone.
///
/// `TestWidgetsFlutterBinding` installs a global mock answering 400 to every
/// request; a zoned override takes precedence over it (documented on the
/// mock itself), and the inherited `createHttpClient` builds the real client.
final class _UnmockedOverrides extends HttpOverrides {}

/// Creates a REAL [HttpClient], bypassing the test-binding mock.
HttpClient _realClient() => HttpOverrides.runZoned(
      () => HttpClient(),
      createHttpClient: (context) =>
          _UnmockedOverrides().createHttpClient(context),
    );

/// Issues one HTTP request with an optional verbatim `Authorization` header.
///
/// Pass [authorization] as the full header value (e.g. `'Bearer T'`) or null
/// to omit the header entirely.

Future<LiveResponse> liveRequest(
  Uri uri, {
  String method = 'GET',
  String? authorization,
}) async {
  final client = _realClient();
  try {
    final request = await client.openUrl(method, uri);
    if (authorization != null) {
      request.headers.set('authorization', authorization);
    }
    final response = await request.close();
    final body = await response.transform(utf8.decoder).join();
    final headers = <String, String>{};
    response.headers.forEach((name, values) {
      headers[name] = values.join(', ');
    });
    return LiveResponse(
      statusCode: response.statusCode,
      headers: headers,
      body: body,
    );
  } finally {
    client.close();
  }
}

/// Builds `http://127.0.0.1:<port><path>` URIs for a serving handle.
Uri liveUri(int port, String path, [Map<String, String>? query]) => Uri(
      scheme: 'http',
      host: '127.0.0.1',
      port: port,
      path: path,
      queryParameters: query,
    );
