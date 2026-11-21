import 'package:bookserver/data/api_client.dart';

/// The signed-in user's own account.
class Account {
  const Account({required this.username, required this.isAdmin});

  final String username;

  /// Whether the user may manage the server: its libraries, series and folders.
  final bool isAdmin;
}

class AccountApi {
  AccountApi(this._client);

  final ApiClient _client;

  /// The signed-in user's own account, with their role.
  Future<Account> account(String sessionToken) async {
    final json = await _client.getJson('/api/v1/account', bearer: sessionToken);
    if (json case {
      'username': final String username,
      'role': final String role,
    }) {
      return Account(username: username, isAdmin: role == 'admin');
    }
    throw const FormatException('Not an account.');
  }
}
