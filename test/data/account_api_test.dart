import 'package:bookserver/data/account_api.dart';
import 'package:bookserver/data/api_client.dart';
import 'package:flutter_test/flutter_test.dart';

import '../support/fake_server.dart';

void main() {
  final origin = Uri.parse('https://books.example.ts.net');
  AccountApi apiFor(FakeServer server) =>
      AccountApi(ApiClient(server.client, origin));

  Map<String, Object?> account(String role) => {
    'id': 1,
    'username': 'alice',
    'email': 'alice@example.com',
    'email_verified': true,
    'role': role,
    'created_at': 1700000000,
    'last_login': null,
  };

  test('reads the account with its session, and an admin as one', () async {
    final server = FakeServer((_) async => jsonAnswer(account('admin')));

    final answer = await apiFor(server).account('session-1');

    expect(answer.username, 'alice');
    expect(answer.isAdmin, isTrue);
    final request = server.requests.single;
    expect(request.method, 'GET');
    expect(request.url.path, '/api/v1/account');
    expect(request.headers['authorization'], 'Bearer session-1');
  });

  test('any other role, an unknown one included, is no admin', () async {
    for (final role in ['member', 'owner']) {
      final server = FakeServer((_) async => jsonAnswer(account(role)));

      expect((await apiFor(server).account('session-1')).isAdmin, isFalse);
    }
  });

  test('refuses an answer without a username or a role', () async {
    for (final answer in <Object?>[
      <String, Object?>{'username': 'alice'},
      <String, Object?>{'role': 'admin'},
      {'username': 'alice', 'role': 1},
      ['admin'],
    ]) {
      final server = FakeServer((_) async => jsonAnswer(answer));
      await expectLater(
        apiFor(server).account('session-1'),
        throwsFormatException,
        reason: '$answer',
      );
    }
  });
}
