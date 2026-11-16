import 'dart:convert';

import 'package:http/http.dart' as http;
import 'package:http/testing.dart';

/// Stands in for the server: answers each request with [answer] and keeps every request it got.
class FakeServer {
  FakeServer(this.answer);

  final Future<http.Response> Function(http.Request request) answer;
  final requests = <http.Request>[];

  late final http.Client client = MockClient((request) {
    requests.add(request);
    return answer(request);
  });
}

/// Stands in for the server with answers whose body arrives in chunks, as a download's does.
class StreamingFakeServer {
  StreamingFakeServer(this.answer);

  final Future<http.StreamedResponse> Function(http.BaseRequest request) answer;
  final requests = <http.BaseRequest>[];

  late final http.Client client = MockClient.streaming((request, _) {
    requests.add(request);
    return answer(request);
  });
}

/// A JSON answer as the server sends one: `application/json` without a charset.
http.Response jsonAnswer(Object? body, [int status = 200]) => http.Response(
  jsonEncode(body),
  status,
  headers: {'content-type': 'application/json'},
);
