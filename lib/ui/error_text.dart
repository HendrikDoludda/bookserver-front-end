import 'package:bookserver/data/api_client.dart';
import 'package:bookserver/data/server_address.dart';
import 'package:bookserver/data/session_controller.dart';
import 'package:bookserver/i18n/catalog.dart';

/// The text key that tells the user what went wrong. A server key the catalog doesn't have, or
/// any other failure, gets the general `connection.unexpected_answer`.
String errorTextKey(Exception error, Catalog catalog) {
  final key = switch (error) {
    ApiException(key: final serverKey) => 'errors.$serverKey',
    ConnectionException() => 'connection.unreachable',
    SessionEndedException() => 'errors.unauthorized',
    AddressException(problem: AddressProblem.invalid) =>
      'server.invalid_address',
    AddressException(problem: AddressProblem.insecure) =>
      'server.insecure_address',
    AddressException(problem: AddressProblem.notABookserver) =>
      'server.not_a_bookserver',
    _ => 'connection.unexpected_answer',
  };
  return catalog.has(key) ? key : 'connection.unexpected_answer';
}
