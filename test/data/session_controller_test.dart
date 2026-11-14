import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:bookserver/data/api_client.dart';
import 'package:bookserver/data/auth_api.dart';
import 'package:bookserver/data/libraries_api.dart';
import 'package:bookserver/data/server_address.dart';
import 'package:bookserver/data/session.dart';
import 'package:bookserver/data/session_controller.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';

import '../support/fake_server.dart';
import '../support/memory_session_store.dart';

const _address = 'https://books.example.ts.net';
final _origin = Uri.parse(_address);
const _deviceId = '0b3c8f2e-6d0a-4c44-9f5e-2d8b8e1f7a10';

void main() {
  late DateTime now;
  late _BookServer server;
  late MemorySessionStore store;

  setUp(() {
    now = DateTime.utc(2026, 11, 14, 12);
    server = _BookServer(() => now);
    store = MemorySessionStore();
  });

  SessionController controller({bool allowHttp = true, http.Client? client}) =>
      SessionController(
        store: store,
        client: client ?? server.client,
        clock: () => now,
        allowHttp: allowHttp,
        platform: 'macos',
      );

  /// Signed in as alice at 12:00, so the first session token runs out at 12:15.
  Future<SessionController> signedIn() async {
    final session = controller();
    await session.useServer(_address);
    await session.logIn('alice', 'correct horse battery');
    server.requests.clear();
    return session;
  }

  void setClockTo(Duration beforeTheFirstTokenRunsOut) => now = DateTime.utc(
    2026,
    11,
    14,
    12,
    15,
  ).subtract(beforeTheFirstTokenRunsOut);

  Future<List<Library>> libraries(SessionController session) =>
      session.authorized((api, token) => LibrariesApi(api).list(token));

  group('load', () {
    test('without a stored connection asks for a server', () async {
      final session = controller();
      await session.load();
      expect(session.stage, isA<NeedsServer>());
    });

    test('with a server but no session asks to sign in', () async {
      store.connection = StoredConnection(server: _origin, deviceId: _deviceId);
      final session = controller();

      await session.load();

      expect(
        session.stage,
        isA<LoggedOut>()
            .having((s) => s.server, 'server', _origin)
            .having((s) => s.endedKey, 'endedKey', isNull),
      );
    });

    test('with a session is signed in', () async {
      store.connection = StoredConnection(
        server: _origin,
        deviceId: _deviceId,
        tokens: SessionTokens(
          sessionToken: 'session-1',
          sessionExpiresAt: now.add(const Duration(minutes: 15)),
          refreshToken: 'refresh-1',
          refreshExpiresAt: now.add(const Duration(days: 30)),
          deviceId: _deviceId,
        ),
      );
      final session = controller();

      await session.load();

      expect(
        session.stage,
        isA<LoggedIn>().having((s) => s.server, 'server', _origin),
      );
    });

    test('tells its listeners', () async {
      final session = controller();
      var told = 0;
      session.addListener(() => told++);

      await session.load();

      expect(told, 1);
    });
  });

  group('useServer', () {
    test('keeps the address of a book server and asks to sign in', () async {
      final session = controller();

      await session.useServer(' books.example.ts.net ');

      expect(
        session.stage,
        isA<LoggedOut>().having((s) => s.server, 'server', _origin),
      );
      expect(store.connection?.server, _origin);
      expect(store.connection?.deviceId, isNull);
      expect(
        server.requests.single.url.toString(),
        'https://books.example.ts.net/health',
      );
    });

    test("replaces the old server's record, its device id included", () async {
      store.connection = StoredConnection(
        server: Uri.parse('https://old.example.ts.net'),
        deviceId: 'old-device',
      );
      final session = controller();
      await session.load();

      await session.useServer(_address);

      expect(store.connection?.server, _origin);
      expect(store.connection?.deviceId, isNull);
    });

    test('refuses an invalid address without asking the network', () async {
      final session = controller();

      await expectLater(
        session.useServer('not a server'),
        throwsA(_addressProblem(AddressProblem.invalid)),
      );

      expect(server.requests, isEmpty);
      expect(store.connection, isNull);
      expect(session.stage, isA<NeedsServer>());
    });

    test('refuses http:// in a release build', () async {
      await expectLater(
        controller(allowHttp: false).useServer('http://localhost:8080'),
        throwsA(_addressProblem(AddressProblem.insecure)),
      );
    });

    test('refuses an address where no book server answers', () async {
      final elsewhere = FakeServer(
        (_) async => http.Response('Not found', 404),
      );

      await expectLater(
        controller(client: elsewhere.client).useServer(_address),
        throwsA(_addressProblem(AddressProblem.notABookserver)),
      );

      expect(store.connection, isNull);
    });

    test('passes on that nothing answers', () async {
      server.offline = true;
      final session = controller();

      await expectLater(
        session.useServer(_address),
        throwsA(isA<ConnectionException>()),
      );

      expect(store.connection, isNull);
      expect(session.stage, isA<NeedsServer>());
    });
  });

  group('logIn', () {
    test('keeps the tokens and the device id, and is signed in', () async {
      final session = controller();
      await session.useServer(_address);

      final result = await session.logIn('alice', 'correct horse battery');

      expect(result, isA<LoginOk>());
      expect(
        session.stage,
        isA<LoggedIn>().having((s) => s.server, 'server', _origin),
      );
      expect(store.connection?.tokens?.sessionToken, 'session-1');
      expect(store.connection?.deviceId, _deviceId);
      expect(jsonDecode(server.requests.last.body), {
        'username_or_email': 'alice',
        'password': 'correct horse battery',
        'device_name': 'macOS',
        'platform': 'macos',
      });
    });

    test('sends back the device id at the next login', () async {
      final session = await signedIn();
      await session.logOut();

      await session.logIn('alice', 'correct horse battery');

      final login = server.requests.lastWhere(
        (request) => request.url.path == '/api/v1/auth/login',
      );
      expect(jsonDecode(login.body)['device_id'], _deviceId);
    });

    test('keeps nothing when the account needs a second factor', () async {
      server.loginAnswer = jsonAnswer({
        'status': 'totp_required',
        'challenge_token': 'challenge-1',
        'challenge_expires_at': 1700000000,
      });
      final session = controller();
      await session.useServer(_address);

      final result = await session.logIn('alice', 'correct horse battery');

      expect(result, isA<LoginTotpRequired>());
      expect(store.connection?.tokens, isNull);
      expect(session.stage, isA<LoggedOut>());
    });

    test('keeps nothing when the server refuses', () async {
      server.loginAnswer = jsonAnswer({'error': 'incorrect_credentials'}, 401);
      final session = controller();
      await session.useServer(_address);

      await expectLater(
        session.logIn('alice', 'wrong password'),
        throwsA(isA<ApiException>()),
      );

      expect(store.connection?.tokens, isNull);
      expect(session.stage, isA<LoggedOut>());
    });
  });

  group('logOut', () {
    test(
      'signs out here and tells the server with the refresh token',
      () async {
        final session = await signedIn();

        await session.logOut();

        expect(
          session.stage,
          isA<LoggedOut>().having((s) => s.endedKey, 'endedKey', isNull),
        );
        expect(store.connection?.tokens, isNull);
        expect(store.connection?.server, _origin);
        expect(store.connection?.deviceId, _deviceId);
        expect(server.bearersOf('/api/v1/auth/logout'), ['refresh-1']);
        expect(server.liveSession, isNull);
      },
    );

    test("still signs out here when the server can't be reached", () async {
      final session = await signedIn();
      server.offline = true;

      await session.logOut();

      expect(session.stage, isA<LoggedOut>());
      expect(store.connection?.tokens, isNull);
    });
  });

  test('forgetServer deletes the record and asks for a server', () async {
    final session = controller();
    await session.useServer(_address);

    await session.forgetServer();

    expect(store.connection, isNull);
    expect(session.stage, isA<NeedsServer>());
  });

  group('authorized', () {
    test(
      'calls with the session token while more than a minute is left',
      () async {
        final session = await signedIn();
        setClockTo(const Duration(seconds: 61));

        await libraries(session);

        expect(server.countOf('/api/v1/auth/refresh'), 0);
        expect(server.bearersOf('/api/v1/libraries'), ['session-1']);
      },
    );

    test('refreshes first when less than a minute is left', () async {
      final session = await signedIn();
      setClockTo(const Duration(seconds: 59));

      await libraries(session);

      expect(server.bearersOf('/api/v1/auth/refresh'), ['refresh-1']);
      expect(server.bearersOf('/api/v1/libraries'), ['session-2']);
      expect(store.connection?.tokens?.sessionToken, 'session-2');
    });

    test('refreshes once after a 401 and calls again', () async {
      final session = await signedIn();
      server.liveSession = 'forgotten';

      await libraries(session);

      expect(server.countOf('/api/v1/auth/refresh'), 1);
      expect(server.bearersOf('/api/v1/libraries'), ['session-1', 'session-2']);
    });

    test('passes any other refusal on without refreshing', () async {
      final session = await signedIn();

      await expectLater(
        session.authorized<void>(
          (api, token) async => throw const ApiException(403, 'forbidden'),
        ),
        throwsA(isA<ApiException>().having((e) => e.status, 'status', 403)),
      );

      expect(server.countOf('/api/v1/auth/refresh'), 0);
      expect(session.stage, isA<LoggedIn>());
    });

    test('a second 401 ends the session', () async {
      final session = await signedIn();
      server.refuseSessionTokens = true;

      await expectLater(
        libraries(session),
        throwsA(isA<SessionEndedException>()),
      );

      expect(
        session.stage,
        isA<LoggedOut>().having(
          (s) => s.endedKey,
          'endedKey',
          'errors.unauthorized',
        ),
      );
      expect(store.connection?.tokens, isNull);
      expect(store.connection?.deviceId, _deviceId);
      expect(server.countOf('/api/v1/auth/refresh'), 1);
    });

    test('a refused refresh ends the session', () async {
      final session = await signedIn();
      server.liveRefresh = 'revoked';
      setClockTo(const Duration(seconds: 30));

      await expectLater(
        libraries(session),
        throwsA(isA<SessionEndedException>()),
      );

      expect(
        session.stage,
        isA<LoggedOut>().having(
          (s) => s.endedKey,
          'endedKey',
          'errors.unauthorized',
        ),
      );
      expect(store.connection?.tokens, isNull);
      expect(server.countOf('/api/v1/libraries'), 0);
    });

    test("a refresh that can't reach the server keeps the session", () async {
      final session = await signedIn();
      server.offline = true;
      setClockTo(const Duration(seconds: 30));

      await expectLater(
        libraries(session),
        throwsA(isA<ConnectionException>()),
      );

      expect(session.stage, isA<LoggedIn>());
      expect(store.connection?.tokens?.sessionToken, 'session-1');
    });

    test('parallel calls share one refresh', () async {
      final session = await signedIn();
      setClockTo(const Duration(seconds: 30));

      await Future.wait([
        libraries(session),
        libraries(session),
        libraries(session),
      ]);

      expect(server.countOf('/api/v1/auth/refresh'), 1);
      expect(server.bearersOf('/api/v1/libraries'), [
        'session-2',
        'session-2',
        'session-2',
      ]);
    });

    test('a 401 on a token another call already replaced retries without a second refresh', () async {
      final session = await signedIn();
      server.liveSession = 'forgotten';
      final secondCallMayHearBack = Completer<void>();
      var librariesRequests = 0;
      server.beforeLibraries = () async {
        librariesRequests++;
        if (librariesRequests == 2) {
          await secondCallMayHearBack.future;
        }
      };

      final first = libraries(session);
      final second = libraries(session);
      await first;
      secondCallMayHearBack.complete();
      await second;

      expect(server.countOf('/api/v1/auth/refresh'), 1);
      expect(server.bearersOf('/api/v1/libraries'), [
        'session-1',
        'session-1',
        'session-2',
        'session-2',
      ]);
    });

    test('a refresh answered after sign-out keeps nothing and ends the renewed session', () async {
      final session = await signedIn();
      server.refreshAnswers = Completer<void>();
      setClockTo(const Duration(seconds: 30));

      final call = libraries(session);
      await server.refreshRotated.future;
      await session.logOut();
      server.refreshAnswers!.complete();

      await expectLater(call, throwsA(isA<SessionEndedException>()));
      expect(
        session.stage,
        isA<LoggedOut>().having((s) => s.endedKey, 'endedKey', isNull),
      );
      expect(store.connection?.tokens, isNull);
      expect(server.bearersOf('/api/v1/auth/logout'), [
        'refresh-1',
        'refresh-2',
      ]);
      expect(server.liveSession, isNull);
    });

    test(
      'a refresh refused after sign-out does not say the session ended',
      () async {
        final session = await signedIn();
        server.refreshArrives = Completer<void>();
        setClockTo(const Duration(seconds: 30));

        final call = libraries(session);
        await server.refreshReceived.future;
        await session.logOut();
        server.refreshArrives!.complete();

        await expectLater(call, throwsA(isA<SessionEndedException>()));
        expect(
          session.stage,
          isA<LoggedOut>().having((s) => s.endedKey, 'endedKey', isNull),
        );
      },
    );

    test('without a session nothing is sent', () async {
      final session = controller();
      await session.useServer(_address);
      server.requests.clear();

      await expectLater(
        libraries(session),
        throwsA(isA<SessionEndedException>()),
      );

      expect(server.requests, isEmpty);
    });
  });
}

Matcher _addressProblem(AddressProblem problem) =>
    isA<AddressException>().having((e) => e.problem, 'problem', problem);

/// A book server with the real one's session rules: every login and refresh issues the next
/// pair of tokens, and only the newest pair works. Its switches and gates set up the
/// situations a test needs.
class _BookServer {
  _BookServer(this._clock);

  final DateTime Function() _clock;
  final requests = <http.Request>[];
  late final http.Client client = MockClient(_answer);

  String? liveSession;
  String? liveRefresh;
  var _issued = 0;

  bool offline = false;
  bool refuseSessionTokens = false;
  http.Response? loginAnswer;
  Future<void> Function()? beforeLibraries;

  /// Holds a refresh before the server looks at it.
  Completer<void>? refreshArrives;

  /// Holds a refresh's answer after the server has already issued the new tokens.
  Completer<void>? refreshAnswers;
  final refreshReceived = Completer<void>();
  final refreshRotated = Completer<void>();

  int countOf(String path) => bearersOf(path).length;

  List<String?> bearersOf(String path) => [
    for (final request in requests)
      if (request.url.path == path) _bearer(request),
  ];

  Future<http.Response> _answer(http.Request request) async {
    requests.add(request);
    if (offline) {
      throw const SocketException('Network is unreachable');
    }
    switch (request.url.path) {
      case '/health':
        return http.Response('pong', 200);
      case '/api/v1/auth/login':
        return loginAnswer ?? jsonAnswer({'status': 'ok', ..._issue()});
      case '/api/v1/auth/refresh':
        if (!refreshReceived.isCompleted) {
          refreshReceived.complete();
        }
        await refreshArrives?.future;
        if (_bearer(request) != liveRefresh) {
          return jsonAnswer({'error': 'unauthorized'}, 401);
        }
        final tokens = _issue();
        if (!refreshRotated.isCompleted) {
          refreshRotated.complete();
        }
        await refreshAnswers?.future;
        return jsonAnswer(tokens);
      case '/api/v1/auth/logout':
        final token = _bearer(request);
        if (token == liveSession || token == liveRefresh) {
          liveSession = null;
          liveRefresh = null;
        }
        return http.Response('', 204);
      case '/api/v1/libraries':
        await beforeLibraries?.call();
        if (refuseSessionTokens || _bearer(request) != liveSession) {
          return jsonAnswer({'error': 'unauthorized'}, 401);
        }
        return jsonAnswer([]);
      default:
        return jsonAnswer({'error': 'not_found'}, 404);
    }
  }

  Map<String, Object?> _issue() {
    _issued++;
    liveSession = 'session-$_issued';
    liveRefresh = 'refresh-$_issued';
    final issuedAt = _clock();
    return {
      'session_token': liveSession,
      'session_expires_at': _seconds(issuedAt.add(const Duration(minutes: 15))),
      'refresh_token': liveRefresh,
      'refresh_expires_at': _seconds(issuedAt.add(const Duration(days: 30))),
      'device_id': _deviceId,
    };
  }
}

String? _bearer(http.Request request) =>
    request.headers['authorization']?.replaceFirst('Bearer ', '');

int _seconds(DateTime time) => time.millisecondsSinceEpoch ~/ 1000;
