import 'dart:convert';

import 'package:bookserver/data/api_client.dart';
import 'package:bookserver/data/two_factor_api.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;

import '../support/fake_server.dart';

void main() {
  final origin = Uri.parse('https://books.example.ts.net');
  TwoFactorApi apiFor(FakeServer server) =>
      TwoFactorApi(ApiClient(server.client, origin));

  void expectRequest(
    FakeServer server,
    String method,
    String path, [
    Object? body,
  ]) {
    final request = server.requests.single;
    expect(request.method, method);
    expect(request.url.path, path);
    expect(request.headers['authorization'], 'Bearer session-1');
    if (body != null) {
      expect(jsonDecode(request.body), body);
    }
  }

  const codes = ['AAAA-BBBB-CCCC-DDDD', 'EEEE-FFFF-GGGG-HHHH'];

  test('status reads whether it is on and the codes left', () async {
    final server = FakeServer(
      (_) async => jsonAnswer({'enabled': true, 'recovery_codes_left': 7}),
    );

    final status = await apiFor(server).status('session-1');

    expect((status.enabled, status.recoveryCodesLeft), (true, 7));
    expectRequest(server, 'GET', '/api/v1/account/totp');
  });

  test('start reads the link and the key', () async {
    final server = FakeServer(
      (_) async => jsonAnswer({
        'otpauth_url': 'otpauth://totp/Bookserver:alice?secret=ABC',
        'secret_base32': 'ABC',
      }),
    );

    final setup = await apiFor(server).start('session-1');

    expect(setup.otpauthUrl, 'otpauth://totp/Bookserver:alice?secret=ABC');
    expect(setup.secret, 'ABC');
    expectRequest(server, 'POST', '/api/v1/account/totp');
  });

  test(
    'confirm sends the code and the password, and reads the codes',
    () async {
      final server = FakeServer(
        (_) async => jsonAnswer({'recovery_codes': codes}),
      );

      final read = await apiFor(server)
          .confirm('session-1', code: '123456', password: 'pw');

      expect(read, codes);
      expectRequest(server, 'POST', '/api/v1/account/totp/confirm', {
        'code': '123456',
        'password': 'pw',
      });
    },
  );

  test('renewRecoveryCodes sends the password and a code', () async {
    final server = FakeServer(
      (_) async => jsonAnswer({'recovery_codes': codes}),
    );

    final read = await apiFor(server)
        .renewRecoveryCodes('session-1', password: 'pw', code: '123456');

    expect(read, codes);
    expectRequest(server, 'POST', '/api/v1/account/totp/recovery_codes', {
      'password': 'pw',
      'code': '123456',
    });
  });

  test('disable sends the password and a code, and takes the 204', () async {
    final server = FakeServer((_) async => http.Response('', 204));

    await apiFor(server)
        .disable('session-1', password: 'pw', code: 'AAAA-BBBB-CCCC-DDDD');

    expectRequest(server, 'POST', '/api/v1/account/totp/disable', {
      'password': 'pw',
      'code': 'AAAA-BBBB-CCCC-DDDD',
    });
  });

  test('refuses answers of another shape', () async {
    Future<void> refuses(
      Object? answer,
      Future<Object?> Function(TwoFactorApi api) call,
    ) async {
      final server = FakeServer((_) async => jsonAnswer(answer));
      await expectLater(
        call(apiFor(server)),
        throwsFormatException,
        reason: '$answer',
      );
    }

    await refuses({'enabled': 'yes'}, (api) => api.status('session-1'));
    await refuses({'otpauth_url': 3}, (api) => api.start('session-1'));
    for (final answer in [
      {
        'recovery_codes': [1, 2],
      },
      {'recovery_codes': 'AAAA'},
      <String, Object?>{},
    ]) {
      await refuses(
        answer,
        (api) => api.confirm('session-1', code: '1', password: 'pw'),
      );
    }
  });

  test('passes a refusal on as an ApiException', () async {
    final server = FakeServer(
      (_) async => jsonAnswer({'error': 'incorrect_password'}, 400),
    );
    await expectLater(
      apiFor(server).confirm('session-1', code: '123456', password: 'wrong'),
      throwsA(
        isA<ApiException>().having((e) => e.key, 'key', 'incorrect_password'),
      ),
    );
  });
}
