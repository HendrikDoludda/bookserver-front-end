import 'dart:async';

import 'package:bookserver/data/browse_api.dart';
import 'package:bookserver/data/session_controller.dart';

/// Saves a reader's place in the book [bookId]: once it rests for [rest], at once the first time
/// the book's end is on screen, and what still waits when the reader closes.
class ProgressSaver {
  ProgressSaver({
    required this.session,
    required this.bookId,
    required Place opening,
    required this._restarting,
    this.rest = const Duration(seconds: 2),
  }) : _last = opening;

  final SessionController session;
  final int bookId;
  final Duration rest;

  /// The place on screen: the reader's own report of the place it opened at is no move.
  Place _last;

  /// The book was finished and opened at its start: its first move reads it again, and unmarks it.
  bool _restarting;

  var _ended = false;
  Place? _waiting;
  Timer? _timer;

  /// The reader moved to [position] of [total]: saved once it rests there.
  void moved(int position, int total) {
    final place = (position: position, total: total);
    if (place == _last) {
      return;
    }
    _last = _waiting = place;
    _timer?.cancel();
    _timer = Timer(rest, _flush);
  }

  /// The book's end is on screen at [position] of [total]: the first time, saved at once and
  /// marked finished; after that, a move.
  void ended(int position, int total) {
    if (_ended) {
      moved(position, total);
      return;
    }
    _ended = true;
    _restarting = false;
    _timer?.cancel();
    _waiting = null;
    _last = (position: position, total: total);
    unawaited(_send(_last, finished: true));
  }

  /// A page reader shows page [index] of [count]: the last page is the book's end.
  void pageShown(int index, int count) =>
      index == count - 1 ? ended(index, count) : moved(index, count);

  /// Sends a place still waiting, at once: the reader closes.
  void close() {
    _timer?.cancel();
    _flush();
  }

  void _flush() {
    final place = _waiting;
    if (place == null) {
      return;
    }
    _waiting = null;
    final unmark = _restarting;
    _restarting = false;
    unawaited(_send(place, finished: unmark ? false : null));
  }

  Future<void> _send(Place place, {bool? finished}) async {
    try {
      await session.authorized(
        (api, sessionToken) => BrowseApi(
          api,
        ).saveProgress(bookId, sessionToken, place: place, finished: finished),
      );
    } on Exception {
      // Dropped: the reader has nothing to show for it, and the next save carries the newer place.
    }
  }
}
