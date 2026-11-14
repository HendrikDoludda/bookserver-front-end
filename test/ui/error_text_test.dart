import 'package:bookserver/data/api_client.dart';
import 'package:bookserver/data/server_address.dart';
import 'package:bookserver/data/session_controller.dart';
import 'package:bookserver/i18n/catalog.dart';
import 'package:bookserver/ui/error_text.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late Catalog english;
  setUpAll(() async {
    english = await Catalog.loadBuiltInEnglish();
  });

  test('every failure gets the text key that explains it', () {
    final cases = <Exception, String>{
      const ApiException(401, 'incorrect_credentials'):
          'errors.incorrect_credentials',
      const ApiException(429, 'too_many_attempts'): 'errors.too_many_attempts',
      const ConnectionException('offline'): 'connection.unreachable',
      const SessionEndedException(): 'errors.unauthorized',
      const AddressException(AddressProblem.invalid): 'server.invalid_address',
      const AddressException(AddressProblem.insecure):
          'server.insecure_address',
      const AddressException(AddressProblem.notABookserver):
          'server.not_a_bookserver',
    };
    cases.forEach((error, key) {
      expect(errorTextKey(error, english), key, reason: '$error');
    });
  });

  test('anything else gets the general one', () {
    for (final error in <Exception>[
      const ApiException(400, 'a_key_this_app_does_not_know'),
      const FormatException('HTTP 404 without an error key'),
      PlatformException(code: 'unreadable'),
    ]) {
      expect(
        errorTextKey(error, english),
        'connection.unexpected_answer',
        reason: '$error',
      );
    }
  });
}
