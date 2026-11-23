import 'package:bookserver/data/server_address.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('takes as the origin', () {
    const cases = {
      'books.example.ts.net': 'https://books.example.ts.net',
      '  https://Books.Example.TS.net/  ': 'https://books.example.ts.net',
      'https://books.example.ts.net:8443': 'https://books.example.ts.net:8443',
      'https://books.example.ts.net:443': 'https://books.example.ts.net',
      'localhost:8080': 'https://localhost:8080',
      'http://localhost:8080': 'http://localhost:8080',
      'http://10.0.2.2:8080': 'http://10.0.2.2:8080',
      'HTTP://192.168.1.20:8080': 'http://192.168.1.20:8080',
      '[::1]:8080': 'https://[::1]:8080',
    };
    cases.forEach((typed, origin) {
      test('"$typed" as $origin', () {
        expect(parseServerAddress(typed, allowHttp: true).toString(), origin);
      });
    });
  });

  test('refuses an address that is not an origin', () {
    for (final typed in [
      '',
      '   ',
      'https://',
      'https://:8080',
      'ftp://books.example.ts.net',
      'https://books.example.ts.net/api',
      'https://books.example.ts.net/?page=2',
      'https://books.example.ts.net/#top',
      'https://user:secret@books.example.ts.net',
      'my server',
      'bücher.example.ts.net',
      'https://books.example.ts.net:0',
      'https://books.example.ts.net:99999',
    ]) {
      expect(
        () => parseServerAddress(typed, allowHttp: true),
        throwsA(_problem(AddressProblem.invalid)),
        reason: typed,
      );
    }
  });

  test('refuses http:// to another device unless it is allowed', () {
    for (final typed in [
      'http://192.168.1.20:8080',
      'HTTP://192.168.1.20',
      'http://books.example.ts.net',
      'http://10.0.2.2:8080',
      'http://localhost.example.com:8080',
      'http://127.0.0.1.nip.io:8080',
    ]) {
      expect(
        () => parseServerAddress(typed, allowHttp: false),
        throwsA(_problem(AddressProblem.insecure)),
        reason: typed,
      );
    }
    expect(
      parseServerAddress('books.example.ts.net', allowHttp: false).scheme,
      'https',
    );
  });

  group('takes http:// to this device even when it is not allowed', () {
    const cases = {
      'http://localhost:8080': 'http://localhost:8080',
      'HTTP://LocalHost:8080': 'http://localhost:8080',
      'http://localhost': 'http://localhost',
      'http://127.0.0.1:8080': 'http://127.0.0.1:8080',
      'http://[::1]:8080': 'http://[::1]:8080',
    };
    cases.forEach((typed, origin) {
      test('"$typed" as $origin', () {
        expect(parseServerAddress(typed, allowHttp: false).toString(), origin);
      });
    });
  });

  test('a broken http:// address is invalid, not insecure', () {
    expect(
      () => parseServerAddress('http://', allowHttp: false),
      throwsA(_problem(AddressProblem.invalid)),
    );
  });
}

Matcher _problem(AddressProblem problem) =>
    isA<AddressException>().having((e) => e.problem, 'problem', problem);
