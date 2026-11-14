# Architecture

## Where things live
- `lib/main.dart` — start-up: loads the built-in English and the stored connection, then runs the app.
- `lib/app.dart` — the root: the catalog and the theme above every screen, and the screen for the session's stage.
- `lib/data/` — talking to the server and keeping the session, no widgets: `server_address.dart` (what counts as a server address), `api_client.dart` (every request), one file per API area (`auth_api.dart`, `libraries_api.dart`), and the session — `session.dart` (the stored record), `session_store.dart` (where it's kept) and `session_controller.dart` (its stages and rules).
- `lib/i18n/catalog.dart` — the catalog, `CatalogScope` and `context.t()`.
- `lib/ui/` — the screens (`server_screen.dart`, `login_screen.dart`, `home_screen.dart`), the layout of a one-form screen (`form_page.dart`), the text a failure shows (`error_text.dart`), and the design tokens (`theme.dart`).
- `assets/translations/en.json` — the built-in English: the server's answer to `GET /api/v1/locales/en/translations`, refreshed with the command in [commands.md](commands.md).
- Code in `lib/` is imported by package — `package:bookserver/…` — never by a relative path.

## State
- State lives in `ChangeNotifier`s that screens listen to; services reach screens through constructors — no state-management package.

## API
- Every server call goes through `ApiClient` (`package:http`); request and answer bodies are JSON, read as UTF-8.
- A call answers its result or throws one of three: `ApiException` (`{"error": key}` and its status), `ConnectionException` (no connection, a timeout, or a proxy's 502–504 without a key) or `FormatException` (any other answer).
- Redirects are never followed.
- Tokens travel only in the `Authorization: Bearer` header — never in a URL — and are never printed or logged; neither are passwords.
- A server address is an origin — scheme, host and port, nothing else (`parseServerAddress`).

## Session
- The server's origin, the device id and the session tokens are one record in secure storage (`SessionStore`); a new server replaces the record.
- Every call that needs a session goes through `SessionController.authorized`; nothing else reads tokens.
- One refresh at a time: a call that needs one while another runs waits for it.
- Only a refused refresh, a second 401 or signing out ends a session; a network failure keeps it.
- Release builds accept only `https://` server addresses; `kDebugMode` decides.

## UI
- Components read design tokens — `lib/ui/theme.dart` and the theme's colour scheme — never literal colours or sizes.
- Every visible string goes through `context.t("namespace.key")` against the backend's translation catalog.
- Services and controllers throw typed exceptions, never text; a screen shows a failure as the text `errorTextKey` picks.
- Screens catch `Exception`s only: an `Error` is a bug and stays loud.

## Tests
- `test/` mirrors `lib/`: `lib/i18n/catalog.dart` is tested in `test/i18n/catalog_test.dart`; shared fakes live in `test/support/`.
- The server is faked with `FakeServer` (`test/support/fake_server.dart`), built on `package:http`'s `MockClient` — no mocking library.
- Secure storage is faked with `MemorySessionStore`; `SecureSessionStore` itself is tested over `FlutterSecureStorage.setMockInitialValues`.
- Code that depends on the time takes a clock (`DateTime Function()`), so tests never wait.
- Screen tests start the whole app as `main()` does, over the fakes (`pumpApp` in `test/support/screens.dart`), and find texts through the catalog, never as literals.
- Every catalog key written in `lib/` has a built-in English text; `test/i18n/keys_in_code_test.dart` fails otherwise.
