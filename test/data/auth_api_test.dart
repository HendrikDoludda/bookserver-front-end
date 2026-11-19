import 'dart:convert';
import 'dart:io';

import 'package:bookserver/data/api_client.dart';
import 'package:bookserver/data/auth_api.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;

import '../support/fake_server.dart';

void main() {
  final origin = Uri.parse('https://books.example.ts.net');
  AuthApi apiFor(FakeServer server) =>
      AuthApi(ApiClient(server.client, origin));

  // 1700000000 is 2023-11-14 22:13:20 UTC; the refresh token runs 30 days longer.
  const sessionJson = {
    'session_token': 'session-1',
    'session_expires_at': 1700000000,
    'refresh_token': 'refresh-1',
    'refresh_expires_at': 1702592000,
    'device_id': '0b3c8f2e-6d0a-4c44-9f5e-2d8b8e1f7a10',
  };

  Future<LoginResult> logInAsAlice(AuthApi api, {String? deviceId}) =>
      api.logIn(
        usernameOrEmail: 'alice',
        password: 'correct horse battery',
        deviceName: 'macOS',
        platform: 'macos',
        deviceId: deviceId,
      );

  group('isBookserver', () {
    test('is true when /health answers pong', () async {
      for (final body in ['pong', 'pong\n']) {
        final server = FakeServer((_) async => http.Response(body, 200));
        expect(await apiFor(server).isBookserver(), isTrue, reason: body);
        expect(server.requests.single.method, 'GET');
        expect(server.requests.single.url.path, '/health');
      }
    });

    test('is false for any other answer', () async {
      for (final answer in [
        http.Response('OK', 200),
        http.Response('<html>', 404),
        jsonAnswer({'error': 'not_found'}, 404),
        http.Response('', 301),
      ]) {
        final server = FakeServer((_) async => answer);
        expect(
          await apiFor(server).isBookserver(),
          isFalse,
          reason: '${answer.statusCode} ${answer.body}',
        );
      }
    });

    test('throws a ConnectionException when nothing answers', () async {
      final server = FakeServer(
        (_) async => throw const SocketException('Connection refused'),
      );
      await expectLater(
        apiFor(server).isBookserver(),
        throwsA(isA<ConnectionException>()),
      );
    });
  });

  group('logIn', () {
    test('sends the login without a device id the first time', () async {
      final server = FakeServer(
        (_) async => jsonAnswer({'status': 'ok', ...sessionJson}),
      );

      await logInAsAlice(apiFor(server));

      final request = server.requests.single;
      expect(request.method, 'POST');
      expect(request.url.path, '/api/v1/auth/login');
      expect(jsonDecode(request.body), {
        'username_or_email': 'alice',
        'password': 'correct horse battery',
        'device_name': 'macOS',
        'platform': 'macos',
      });
    });

    test('sends back the device id the server gave', () async {
      final server = FakeServer(
        (_) async => jsonAnswer({'status': 'ok', ...sessionJson}),
      );

      await logInAsAlice(apiFor(server), deviceId: 'device-7');

      expect(jsonDecode(server.requests.single.body)['device_id'], 'device-7');
    });

    test('reads the tokens of an ok answer', () async {
      final server = FakeServer(
        (_) async => jsonAnswer({'status': 'ok', ...sessionJson}),
      );

      final result = await logInAsAlice(apiFor(server));

      final tokens = switch (result) {
        LoginOk(:final tokens) => tokens,
        _ => fail('expected LoginOk, got $result'),
      };
      expect(tokens.sessionToken, 'session-1');
      expect(tokens.sessionExpiresAt, DateTime.utc(2023, 11, 14, 22, 13, 20));
      expect(tokens.refreshToken, 'refresh-1');
      expect(tokens.refreshExpiresAt, DateTime.utc(2023, 12, 14, 22, 13, 20));
      expect(tokens.deviceId, sessionJson['device_id']);
    });

    test('reads a totp_required answer', () async {
      final server = FakeServer(
        (_) async => jsonAnswer({
          'status': 'totp_required',
          'challenge_token': 'challenge-1',
          'challenge_expires_at': 1700000000,
        }),
      );

      expect(
        await logInAsAlice(apiFor(server)),
        isA<LoginTotpRequired>()
            .having((r) => r.challengeToken, 'challengeToken', 'challenge-1')
            .having(
              (r) => r.challengeExpiresAt,
              'challengeExpiresAt',
              DateTime.utc(2023, 11, 14, 22, 13, 20),
            ),
      );
    });

    test('passes a refusal on as an ApiException', () async {
      final server = FakeServer(
        (_) async => jsonAnswer({'error': 'incorrect_credentials'}, 401),
      );
      await expectLater(
        logInAsAlice(apiFor(server)),
        throwsA(
          isA<ApiException>().having(
            (e) => e.key,
            'key',
            'incorrect_credentials',
          ),
        ),
      );
    });

    test('refuses an answer of another shape', () async {
      for (final body in <Object?>[
        {'status': 'ok'},
        {'status': 'later'},
        {'status': 'totp_required'},
        <Object?>[],
        null,
      ]) {
        final server = FakeServer((_) async => jsonAnswer(body));
        await expectLater(
          logInAsAlice(apiFor(server)),
          throwsFormatException,
          reason: '$body',
        );
      }
    });
  });

  group('logInWithCode', () {
    test('sends an authenticator code with the challenge token', () async {
      final server = FakeServer(
        (_) async => jsonAnswer({'status': 'ok', ...sessionJson}),
      );

      final tokens = await apiFor(server)
          .logInWithCode('challenge-1', '123456', recoveryCode: false);

      final request = server.requests.single;
      expect(request.method, 'POST');
      expect(request.url.path, '/api/v1/auth/login/totp');
      expect(request.headers['authorization'], 'Bearer challenge-1');
      expect(jsonDecode(request.body), {'code': '123456'});
      expect(tokens.sessionToken, 'session-1');
    });

    test('sends a recovery code to its own route', () async {
      final server = FakeServer(
        (_) async => jsonAnswer({'status': 'ok', ...sessionJson}),
      );

      await apiFor(
        server,
      ).logInWithCode('challenge-1', 'ABCD-EFGH-JKMN-PQRS', recoveryCode: true);

      final request = server.requests.single;
      expect(request.url.path, '/api/v1/auth/login/recovery_code');
      expect(request.headers['authorization'], 'Bearer challenge-1');
      expect(jsonDecode(request.body), {'code': 'ABCD-EFGH-JKMN-PQRS'});
    });

    test('passes a wrong code on as an ApiException', () async {
      final server = FakeServer(
        (_) async => jsonAnswer({'error': 'invalid_or_expired_code'}, 400),
      );
      await expectLater(
        apiFor(server)
            .logInWithCode('challenge-1', '000000', recoveryCode: false),
        throwsA(
          isA<ApiException>().having(
            (e) => e.key,
            'key',
            'invalid_or_expired_code',
          ),
        ),
      );
    });

    test('refuses an answer of another shape', () async {
      for (final answer in <Object?>[
        {
          'status': 'totp_required',
          'challenge_token': 'challenge-2',
          'challenge_expires_at': 1700000000,
        },
        [],
        sessionJson,
      ]) {
        final server = FakeServer((_) async => jsonAnswer(answer));
        await expectLater(
          apiFor(server)
              .logInWithCode('challenge-1', '123456', recoveryCode: false),
          throwsFormatException,
          reason: '$answer',
        );
      }
    });
  });

  group('signUp', () {
    Future<SignUpResult> signUpAlice(
      AuthApi api, {
      String? setupCode,
      String? locale,
    }) => api.signUp(
      email: 'alice@example.com',
      username: 'alice',
      password: 'correct horse battery',
      passwordRepeat: 'correct horse battery',
      deviceName: 'macOS',
      platform: 'macos',
      setupCode: setupCode,
      locale: locale,
    );

    test('sends the account, leaving out what it lacks', () async {
      final server = FakeServer(
        (_) async => jsonAnswer({'verification_required': true}, 202),
      );

      await signUpAlice(apiFor(server));

      final request = server.requests.single;
      expect(request.method, 'POST');
      expect(request.url.path, '/api/v1/auth/register');
      expect(request.headers.containsKey('authorization'), isFalse);
      expect(jsonDecode(request.body), {
        'email': 'alice@example.com',
        'username': 'alice',
        'password': 'correct horse battery',
        'password_repeat': 'correct horse battery',
        'device_name': 'macOS',
        'platform': 'macos',
      });
    });

    test('sends the setup code and the language when given', () async {
      final server = FakeServer(
        (_) async => jsonAnswer({'verification_required': true}, 202),
      );

      await signUpAlice(apiFor(server), setupCode: 'ABCD2345', locale: 'de');

      final body = jsonDecode(server.requests.single.body);
      expect(body['setup_code'], 'ABCD2345');
      expect(body['locale'], 'de');
    });

    test('an account ready at once comes with its session', () async {
      final server = FakeServer(
        (_) async => jsonAnswer({'status': 'ok', ...sessionJson}),
      );

      final result = await signUpAlice(apiFor(server));

      expect(
        result,
        isA<SignedUp>().having(
          (r) => r.tokens.sessionToken,
          'session',
          'session-1',
        ),
      );
    });

    test('an account that waits for its code says so', () async {
      final server = FakeServer(
        (_) async => jsonAnswer({'verification_required': true}, 202),
      );

      expect(await signUpAlice(apiFor(server)), isA<VerificationRequired>());
    });

    test('refuses an answer of another shape', () async {
      for (final answer in <Object?>[
        {'verification_required': false},
        {'status': 'totp_required'},
        [],
      ]) {
        final server = FakeServer((_) async => jsonAnswer(answer));
        await expectLater(
          signUpAlice(apiFor(server)),
          throwsFormatException,
          reason: '$answer',
        );
      }
    });

    test('passes a refusal on as an ApiException', () async {
      final server = FakeServer(
        (_) async => jsonAnswer({'error': 'invalid_setup_code'}, 403),
      );
      await expectLater(
        signUpAlice(apiFor(server)),
        throwsA(
          isA<ApiException>().having((e) => e.key, 'key', 'invalid_setup_code'),
        ),
      );
    });
  });

  group('verifyEmail', () {
    test('sends the login with the code and answers like login', () async {
      final server = FakeServer(
        (_) async => jsonAnswer({'status': 'ok', ...sessionJson}),
      );

      final result = await apiFor(server).verifyEmail(
        usernameOrEmail: 'alice@example.com',
        password: 'correct horse battery',
        code: 'ABCD2345',
        deviceName: 'macOS',
        platform: 'macos',
        deviceId: 'device-1',
      );

      final request = server.requests.single;
      expect(request.url.path, '/api/v1/auth/verify_email');
      expect(jsonDecode(request.body), {
        'username_or_email': 'alice@example.com',
        'password': 'correct horse battery',
        'code': 'ABCD2345',
        'device_name': 'macOS',
        'platform': 'macos',
        'device_id': 'device-1',
      });
      expect(result, isA<LoginOk>());
    });
  });

  test('resendVerification sends the name and takes the 202', () async {
    final server = FakeServer((_) async => http.Response('', 202));

    await apiFor(server).resendVerification('alice');

    final request = server.requests.single;
    expect(request.url.path, '/api/v1/auth/verify_email/resend');
    expect(jsonDecode(request.body), {'username_or_email': 'alice'});
  });

  group('refresh', () {
    test('sends the refresh token and reads the new tokens', () async {
      final server = FakeServer((_) async => jsonAnswer(sessionJson));

      final tokens = await apiFor(server).refresh('refresh-1');

      final request = server.requests.single;
      expect(request.method, 'POST');
      expect(request.url.path, '/api/v1/auth/refresh');
      expect(request.headers['authorization'], 'Bearer refresh-1');
      expect(request.bodyBytes, isEmpty);
      expect(tokens.sessionToken, 'session-1');
      expect(tokens.deviceId, sessionJson['device_id']);
    });

    test('passes a refused refresh on as a 401 ApiException', () async {
      final server = FakeServer(
        (_) async => jsonAnswer({'error': 'unauthorized'}, 401),
      );
      await expectLater(
        apiFor(server).refresh('refresh-1'),
        throwsA(isA<ApiException>().having((e) => e.status, 'status', 401)),
      );
    });
  });

  test('logOut sends the token and takes the 204', () async {
    final server = FakeServer((_) async => http.Response('', 204));

    await apiFor(server).logOut('refresh-1');

    final request = server.requests.single;
    expect(request.method, 'POST');
    expect(request.url.path, '/api/v1/auth/logout');
    expect(request.headers['authorization'], 'Bearer refresh-1');
  });
}
