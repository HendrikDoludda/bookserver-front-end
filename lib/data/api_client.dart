import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:http/http.dart' as http;

/// The server refused with `{"error": key}`; the app shows the text `errors.<key>`.
class ApiException implements Exception {
  const ApiException(this.status, this.key);

  final int status;
  final String key;

  @override
  String toString() => 'ApiException($status, $key)';
}

/// The server didn't answer: no connection, a timeout, or a proxy that can't reach it.
class ConnectionException implements Exception {
  const ConnectionException(this.cause);

  final Object cause;

  @override
  String toString() => 'ConnectionException($cause)';
}

/// Sends requests to the server at [origin].
class ApiClient {
  ApiClient(this._http, this.origin, {this.timeout = defaultTimeout});

  // Long enough for a slow mobile connection, short enough that a server that's gone doesn't
  // leave a screen waiting.
  static const defaultTimeout = Duration(seconds: 15);

  final http.Client _http;
  final Uri origin;
  final Duration timeout;

  Future<String> getText(String path) async {
    final response = await _send('GET', path);
    return utf8.decode(response.bodyBytes);
  }

  /// The answer's body as it came, such as an image.
  Future<Uint8List> getBytes(String path, {String? bearer}) async {
    final response = await _send('GET', path, bearer: bearer);
    return response.bodyBytes;
  }

  Future<Object?> getJson(String path, {String? bearer}) =>
      _json('GET', path, bearer: bearer);

  Future<Object?> postJson(String path, {Object? body, String? bearer}) =>
      _json('POST', path, body: body, bearer: bearer);

  Future<Object?> putJson(String path, {Object? body, String? bearer}) =>
      _json('PUT', path, body: body, bearer: bearer);

  Future<Object?> patchJson(String path, {Object? body, String? bearer}) =>
      _json('PATCH', path, body: body, bearer: bearer);

  Future<Object?> deleteJson(String path, {String? bearer}) =>
      _json('DELETE', path, bearer: bearer);

  /// The answer to a GET for [path] that names [etag] in `If-None-Match`: a 304 while the copy
  /// [etag] names is still current, else the 2xx with its whole body. Any other status throws as
  /// [getJson] does.
  Future<http.Response> revalidate(String path, {String? etag}) async {
    final request = _request(
      'GET',
      path,
      acceptJson: true,
      headers: {'if-none-match': ?etag},
    );
    final response = await _guarded(() => _exchange(request).timeout(timeout));
    if (_succeeded(response.statusCode) || response.statusCode == 304) {
      return response;
    }
    throw _refusal(response);
  }

  /// Sends a GET for [path] with [headers], such as a `Range`, and answers once the answer's head
  /// has arrived, for a caller that reads the body itself. A 2xx or a 304 is an answer; any other
  /// status throws as [getJson] does. [timeout] covers the wait for the answer and each gap
  /// between two chunks of the body, which reports a lost connection as a [ConnectionException].
  Future<http.StreamedResponse> stream(
    String path, {
    String? bearer,
    Map<String, String> headers = const {},
  }) async {
    final request = _request('GET', path, bearer: bearer);
    for (final MapEntry(:key, :value) in headers.entries) {
      request.headers.putIfAbsent(key, () => value);
    }
    final response = await _guarded(() => _http.send(request).timeout(timeout));
    if (!_succeeded(response.statusCode) && response.statusCode != 304) {
      throw _refusal(
        await _guarded(
          () => http.Response.fromStream(response).timeout(timeout),
        ),
      );
    }
    return http.StreamedResponse(
      response.stream
          .timeout(timeout)
          .handleError(
            (Object error) => throw ConnectionException(error),
            test: _isConnectionFailure,
          ),
      response.statusCode,
      contentLength: response.contentLength,
      request: response.request,
      headers: response.headers,
      isRedirect: response.isRedirect,
      persistentConnection: response.persistentConnection,
      reasonPhrase: response.reasonPhrase,
    );
  }

  /// Streams the answer to [path] into [target], telling [onProgress] the bytes received so far
  /// and the total the server announced, if it did. [timeout] covers the wait for the answer and
  /// each gap between two chunks, never the whole download. A download that fails leaves no file
  /// at [target].
  Future<void> download(
    String path,
    File target, {
    String? bearer,
    void Function(int received, int? total)? onProgress,
  }) async {
    final request = _request('GET', path, bearer: bearer);
    StreamIterator<List<int>>? chunks;
    RandomAccessFile? file;
    try {
      final response = await _guarded(
        () => _http.send(request).timeout(timeout),
      );
      if (!_succeeded(response.statusCode)) {
        throw _refusal(
          await _guarded(
            () => http.Response.fromStream(response).timeout(timeout),
          ),
        );
      }
      // Only the reads from the server are guarded: a file that can't be written, such as on a
      // full disk, is no connection problem.
      final opened = file = await target.open(mode: FileMode.write);
      final body = chunks = StreamIterator(response.stream.timeout(timeout));
      var received = 0;
      while (await _guarded(body.moveNext)) {
        await opened.writeFrom(body.current);
        received += body.current.length;
        onProgress?.call(received, response.contentLength);
      }
      await opened.close();
    } on Object {
      await chunks?.cancel();
      await _discard(file, target);
      rethrow;
    }
  }

  Future<Object?> _json(
    String method,
    String path, {
    Object? body,
    String? bearer,
  }) async {
    final response = await _send(
      method,
      path,
      body: body,
      bearer: bearer,
      acceptJson: true,
    );
    if (response.bodyBytes.isEmpty) {
      return null;
    }
    return jsonDecode(utf8.decode(response.bodyBytes));
  }

  Future<http.Response> _send(
    String method,
    String path, {
    Object? body,
    String? bearer,
    bool acceptJson = false,
  }) async {
    final request = _request(
      method,
      path,
      body: body,
      bearer: bearer,
      acceptJson: acceptJson,
    );
    final response = await _guarded(() => _exchange(request).timeout(timeout));
    if (_succeeded(response.statusCode)) {
      return response;
    }
    throw _refusal(response);
  }

  http.Request _request(
    String method,
    String path, {
    Object? body,
    String? bearer,
    bool acceptJson = false,
    Map<String, String> headers = const {},
  }) {
    final request = http.Request(method, origin.resolve(path))
      // The server never redirects: a redirect means something else answered, such as a Wi-Fi
      // login page.
      ..followRedirects = false
      ..headers.addAll(headers);
    if (acceptJson) {
      request.headers['accept'] = 'application/json';
    }
    if (bearer != null) {
      request.headers['authorization'] = 'Bearer $bearer';
    }
    if (body != null) {
      request.headers['content-type'] = 'application/json';
      request.bodyBytes = utf8.encode(jsonEncode(body));
    }
    return request;
  }

  Future<http.Response> _exchange(http.Request request) async =>
      http.Response.fromStream(await _http.send(request));
}

/// Runs [exchange], turning a failed connection or a timeout into a [ConnectionException].
Future<T> _guarded<T>(Future<T> Function() exchange) async {
  try {
    return await exchange();
  } on Object catch (error) {
    if (_isConnectionFailure(error)) {
      throw ConnectionException(error);
    }
    rethrow;
  }
}

/// A lost connection or a timeout, the way `package:http` and `dart:io` report them.
bool _isConnectionFailure(Object? error) =>
    error is http.ClientException ||
    error is IOException ||
    error is TimeoutException;

bool _succeeded(int status) => status >= 200 && status < 300;

/// Throws away a download that failed: its open file, and whatever of it reached the disk.
Future<void> _discard(RandomAccessFile? file, File target) async {
  try {
    await file?.close();
  } on Exception {
    // The download has failed already; closing its file can only fail for the same reason.
  }
  try {
    await target.delete();
  } on FileSystemException {
    // Nothing reached the disk.
  }
}

Exception _refusal(http.Response response) {
  final key = _errorKey(response.bodyBytes);
  if (key != null) {
    return ApiException(response.statusCode, key);
  }
  // A proxy in front of the server, like `tailscale serve`, answers these without a key when the
  // server behind it is down.
  if (const {502, 503, 504}.contains(response.statusCode)) {
    return ConnectionException('HTTP ${response.statusCode} from a proxy');
  }
  return FormatException('HTTP ${response.statusCode} without an error key');
}

String? _errorKey(List<int> body) {
  try {
    if (jsonDecode(utf8.decode(body)) case {'error': String key}) {
      return key;
    }
  } on FormatException {
    // Not JSON, so no key.
  }
  return null;
}
