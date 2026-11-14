import 'dart:async';
import 'dart:convert';
import 'dart:io';

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
  ApiClient(
    this._http,
    this.origin, {
    // Long enough for a slow mobile connection, short enough that a server that's gone doesn't
    // leave a screen waiting.
    this.timeout = const Duration(seconds: 15),
  });

  final http.Client _http;
  final Uri origin;
  final Duration timeout;

  Future<String> getText(String path) async {
    final response = await _send('GET', path);
    return utf8.decode(response.bodyBytes);
  }

  Future<Object?> getJson(String path, {String? bearer}) =>
      _json('GET', path, bearer: bearer);

  Future<Object?> postJson(String path, {Object? body, String? bearer}) =>
      _json('POST', path, body: body, bearer: bearer);

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
    final request = http.Request(method, origin.resolve(path))
      // The server never redirects: a redirect means something else answered, such as a Wi-Fi
      // login page.
      ..followRedirects = false;
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

    final http.Response response;
    try {
      response = await _exchange(request).timeout(timeout);
    } on http.ClientException catch (error) {
      throw ConnectionException(error);
    } on IOException catch (error) {
      throw ConnectionException(error);
    } on TimeoutException catch (error) {
      throw ConnectionException(error);
    }
    if (response.statusCode >= 200 && response.statusCode < 300) {
      return response;
    }
    throw _refusal(response);
  }

  Future<http.Response> _exchange(http.Request request) async =>
      http.Response.fromStream(await _http.send(request));
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
