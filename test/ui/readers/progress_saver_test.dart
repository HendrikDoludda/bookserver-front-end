import 'dart:convert';

import 'package:bookserver/data/browse_api.dart';
import 'package:bookserver/ui/readers/progress_saver.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;

import '../../support/fake_server.dart';
import '../../support/screens.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  const rest = Duration(seconds: 2);

  /// The bodies of the saves [server] got, in order.
  List<Object?> saves(FakeServer server) => [
    for (final request in server.requests)
      if (request.url.path == '/api/v1/books/7/progress')
        jsonDecode(request.body),
  ];

  /// A saver for book 7, opened at [opening], with a server that answers every save with
  /// [answer] — 200 by default.
  Future<(FakeServer, ProgressSaver)> saverFor({
    Place opening = (position: 0, total: 10),
    bool restarting = false,
    http.Response Function()? answer,
  }) async {
    final server = FakeServer(
      (_) async =>
          answer?.call() ??
          jsonAnswer({'position': 0, 'total': 10, 'finished': false}),
    );
    final saver = ProgressSaver(
      session: await signedInSession(server),
      bookId: 7,
      opening: opening,
      restarting: restarting,
    );
    return (server, saver);
  }

  testWidgets('a place is saved once it rests, the last of several moves', (
    tester,
  ) async {
    final (server, saver) = await saverFor();

    saver.moved(1, 10);
    await tester.pump(const Duration(seconds: 1));
    saver.moved(2, 10);
    await tester.pump(const Duration(seconds: 1));
    expect(saves(server), isEmpty, reason: 'still moving');
    await tester.pump(const Duration(seconds: 1));

    expect(saves(server), [
      {'position': 2, 'total': 10},
    ]);
  });

  testWidgets('the place the reader opened at is no move', (tester) async {
    final (server, saver) = await saverFor(opening: (position: 3, total: 10));

    saver.moved(3, 10);
    await tester.pump(rest * 2);

    expect(saves(server), isEmpty);
  });

  testWidgets('the end is saved at once and finished, the first time only', (
    tester,
  ) async {
    final (server, saver) = await saverFor();

    saver.ended(9, 10);
    await tester.pump();
    expect(saves(server), [
      {'position': 9, 'total': 10, 'finished': true},
    ]);

    saver.moved(5, 10);
    saver.ended(9, 10);
    await tester.pump(rest);

    expect(saves(server), [
      {'position': 9, 'total': 10, 'finished': true},
      {'position': 9, 'total': 10},
    ], reason: 'the end again is a move');
  });

  testWidgets('a page reader reaches the end on its last page', (tester) async {
    final (server, saver) = await saverFor();

    saver.pageShown(3, 10);
    saver.pageShown(9, 10);
    await tester.pump(rest);

    expect(saves(server), [
      {'position': 9, 'total': 10, 'finished': true},
    ], reason: 'the end drops the move still waiting');
  });

  testWidgets('a finished book is unmarked by its first move only', (
    tester,
  ) async {
    final (server, saver) = await saverFor(restarting: true);

    saver.moved(1, 10);
    await tester.pump(rest);
    saver.moved(2, 10);
    await tester.pump(rest);

    expect(saves(server), [
      {'position': 1, 'total': 10, 'finished': false},
      {'position': 2, 'total': 10},
    ]);
  });

  testWidgets(
    'closing sends what waits at once, and nothing when nothing does',
    (tester) async {
      final (server, saver) = await saverFor();
      final (quiet, idle) = await saverFor();

      saver.moved(4, 10);
      saver.close();
      idle.close();
      await tester.pump();
      expect(saves(server), [
        {'position': 4, 'total': 10},
      ]);
      await tester.pump(rest * 2);

      expect(saves(server), hasLength(1), reason: 'the timer went with it');
      expect(saves(quiet), isEmpty);
    },
  );

  testWidgets('a refused save is dropped, and the next one still goes', (
    tester,
  ) async {
    var refused = true;
    final (server, saver) = await saverFor(
      answer: () => refused
          ? jsonAnswer({'error': 'internal_error'}, 500)
          : jsonAnswer({'position': 2, 'total': 10, 'finished': false}),
    );

    saver.moved(1, 10);
    await tester.pump(rest);
    refused = false;
    saver.moved(2, 10);
    await tester.pump(rest);

    expect(saves(server), [
      {'position': 1, 'total': 10},
      {'position': 2, 'total': 10},
    ]);
  });
}
