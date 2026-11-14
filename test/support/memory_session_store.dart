import 'package:bookserver/data/session.dart';
import 'package:bookserver/data/session_store.dart';

/// Keeps the connection in memory, where a test can set and read it.
class MemorySessionStore implements SessionStore {
  StoredConnection? connection;

  @override
  Future<StoredConnection?> read() async => connection;

  @override
  Future<void> write(StoredConnection connection) async =>
      this.connection = connection;

  @override
  Future<void> delete() async => connection = null;
}
