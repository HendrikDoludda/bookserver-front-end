import 'package:bookserver/data/api_client.dart';
import 'package:bookserver/data/settings_api.dart';
import 'package:flutter_test/flutter_test.dart';

import '../support/fake_server.dart';

void main() {
  final origin = Uri.parse('https://books.example.ts.net');
  SettingsApi apiFor(FakeServer server) =>
      SettingsApi(ApiClient(server.client, origin));

  test('reads the language the user chose, with their session', () async {
    final server = FakeServer((_) async => jsonAnswer({'locale': 'de'}));

    expect(await apiFor(server).language('session-1'), 'de');

    final request = server.requests.single;
    expect(request.method, 'GET');
    expect(request.url.path, '/api/v1/account/settings');
    expect(request.headers['authorization'], 'Bearer session-1');
  });

  test("answers null while the user hasn't chosen one", () async {
    final server = FakeServer((_) async => jsonAnswer({'locale': null}));

    expect(await apiFor(server).language('session-1'), isNull);
  });

  test('refuses an answer without the setting', () async {
    for (final answer in <Object?>[
      <String, Object?>{},
      {'locale': 3},
      ['de'],
    ]) {
      final server = FakeServer((_) async => jsonAnswer(answer));
      await expectLater(
        apiFor(server).language('session-1'),
        throwsFormatException,
        reason: '$answer',
      );
    }
  });
}
