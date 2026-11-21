import 'dart:async';

import 'package:bookserver/data/account_api.dart';
import 'package:bookserver/data/session_controller.dart';
import 'package:flutter/foundation.dart';

/// Whether the signed-in user is an admin, asked from the server whenever a session starts. Until
/// the answer arrives, and while no one is signed in, the user counts as no admin.
class AccountController extends ChangeNotifier {
  AccountController({required this._session});

  final SessionController _session;

  /// The server signed in to when the account was last asked for; null while no one is.
  Uri? _followed;
  var _asks = 0;
  var _isAdmin = false;

  bool get isAdmin => _isAdmin;

  /// Asks for the account if someone is signed in, and again whenever the sign-in changes.
  void load() {
    _session.addListener(_follow);
    _follow();
  }

  @override
  void dispose() {
    _session.removeListener(_follow);
    // Overtakes an ask still waiting for the server, which would notify after the disposal.
    _asks++;
    super.dispose();
  }

  void _follow() {
    final server = switch (_session.stage) {
      LoggedIn(:final server) => server,
      NeedsServer() || LoggedOut() => null,
    };
    if (server == _followed) {
      return;
    }
    _followed = server;
    unawaited(_ask(server));
  }

  /// Asks the server whether the user is an admin. An ask a newer one overtook drops its answer,
  /// and a failure leaves the user counting as no admin until the next sign-in.
  Future<void> _ask(Uri? server) async {
    final ask = ++_asks;
    _show(false);
    if (server == null) {
      return;
    }
    try {
      final account = await _session.authorized(
        (api, token) => AccountApi(api).account(token),
      );
      if (ask == _asks) {
        _show(account.isAdmin);
      }
    } on Exception {
      // The admin screens stay hidden; the server would refuse a non-admin anyway.
    }
  }

  void _show(bool isAdmin) {
    if (isAdmin != _isAdmin) {
      _isAdmin = isAdmin;
      notifyListeners();
    }
  }
}
