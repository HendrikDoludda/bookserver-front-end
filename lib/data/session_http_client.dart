import 'package:bookserver/data/session_controller.dart';
import 'package:http/http.dart' as http;

/// An HTTP client for a package that sends its own requests, such as pdfrx: each request goes
/// through [SessionController.authorized], so it carries a live session token, renewed when the
/// server refuses it.
class SessionHttpClient extends http.BaseClient {
  SessionHttpClient(this._session);

  final SessionController _session;

  @override
  Future<http.StreamedResponse> send(http.BaseRequest request) =>
      _session.authorized((api, sessionToken) {
        // The session token goes to the session's own server and nowhere else.
        if (request.method != 'GET' ||
            request.url.origin != api.origin.origin) {
          throw ArgumentError.value(
            '${request.method} ${request.url}',
            'request',
            'Only a GET to ${api.origin} is sent',
          );
        }
        return api.stream(
          request.url.hasQuery
              ? '${request.url.path}?${request.url.query}'
              : request.url.path,
          bearer: sessionToken,
          headers: request.headers,
        );
      });
}
