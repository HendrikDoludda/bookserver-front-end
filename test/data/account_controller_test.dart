import 'dart:async';

import 'package:bookserver/data/account_controller.dart';
import 'package:bookserver/data/session.dart';
import 'package:bookserver/data/session_controller.dart';
import 'package:bookserver/data/session_store.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;

import '../support/fake_server.dart';
import '../support/memory_session_store.dart';
import '../support/screens.dart';

void main() {
  /// The account `GET /api/v1/account` answers, with [role].
  http.Response account(String role) => jsonAnswer({
    'id': 1,
    'username': 'alice',
    'email': 'alice@example.com',
    'email_verified': true,
    'role': role,
    'created_at': 1700000000,
    'last_login': null,
  });

  /// A server that signs in and out, and answers the account with [answer].
  FakeServer accountServer(Future<http.Response> Function() answer) =>
      FakeServer(
        (request) async => switch (request.url.path) {
          '/api/v1/auth/login' => jsonAnswer({'status': 'ok', ...tokensJson()}),
          '/api/v1/auth/logout' => http.Response('', 204),
          '/api/v1/account' => answer(),
          _ => notFound(),
        },
      );

  Future<SessionController> sessionOn(
    FakeServer server,
    SessionStore store,
  ) async {
    final session = SessionController(
      store: store,
      client: server.client,
      platform: 'macos',
    );
    await session.load();
    return session;
  }

  AccountController following(SessionController session) {
    final account = AccountController(session: session);
    addTearDown(account.dispose);
    account.load();
    return account;
  }

  int accountRequests(FakeServer server) => server.requests
      .where((request) => request.url.path == '/api/v1/account')
      .length;

  MemorySessionStore signedOutStore() =>
      MemorySessionStore()..connection = StoredConnection(server: testOrigin);

  test(
    'signed in, it asks once, with the session, and an admin counts as one',
    () async {
      final server = accountServer(() async => account('admin'));
      final session = await sessionOn(server, signedInStore());

      final controller = following(session);
      expect(controller.isAdmin, isFalse, reason: 'no admin before the answer');
      await pumpEventQueue();

      expect(controller.isAdmin, isTrue);
      final request = server.requests.single;
      expect(request.url.path, '/api/v1/account');
      expect(request.headers['authorization'], 'Bearer session-1');
    },
  );

  test('a member is no admin', () async {
    final server = accountServer(() async => account('member'));
    final session = await sessionOn(server, signedInStore());

    final controller = following(session);
    await pumpEventQueue();

    expect(controller.isAdmin, isFalse);
    expect(accountRequests(server), 1);
  });

  test(
    'signed out nothing is asked; signing in asks and tells its listeners',
    () async {
      final server = accountServer(() async => account('admin'));
      final session = await sessionOn(server, signedOutStore());
      final controller = following(session);
      var told = 0;
      controller.addListener(() => told++);
      await pumpEventQueue();
      expect(server.requests, isEmpty);

      await session.logIn('alice', 'correct horse battery');
      await pumpEventQueue();

      expect(controller.isAdmin, isTrue);
      expect(accountRequests(server), 1);
      expect(told, 1);
    },
  );

  test(
    'signing out makes the user no admin; signing in again asks again',
    () async {
      var role = 'admin';
      final server = accountServer(() async => account(role));
      final session = await sessionOn(server, signedInStore());
      final controller = following(session);
      await pumpEventQueue();
      expect(controller.isAdmin, isTrue);

      await session.logOut();
      expect(controller.isAdmin, isFalse);

      role = 'member';
      await session.logIn('bob', 'correct horse battery');
      await pumpEventQueue();
      expect(controller.isAdmin, isFalse);
      expect(accountRequests(server), 2);
    },
  );

  test('a failed ask leaves the user no admin', () async {
    for (final failure in [
      () async => jsonAnswer({'error': 'internal_error'}, 500),
      () async => jsonAnswer({'username': 'alice'}),
      () async => throw http.ClientException('offline'),
    ]) {
      final server = accountServer(failure);
      final session = await sessionOn(server, signedInStore());

      final controller = following(session);
      await pumpEventQueue();

      expect(controller.isAdmin, isFalse);
    }
  });

  test('an answer that a sign-out overtook is dropped', () async {
    final late = Completer<http.Response>();
    final server = accountServer(() => late.future);
    final session = await sessionOn(server, signedInStore());
    final controller = following(session);
    await pumpEventQueue();

    await session.logOut();
    late.complete(account('admin'));
    await pumpEventQueue();

    expect(controller.isAdmin, isFalse);
  });
}
