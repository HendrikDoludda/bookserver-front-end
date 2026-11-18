# Architecture

## Where things live
- `lib/main.dart` — start-up: loads the built-in English and the stored connection, then runs the app.
- `lib/app.dart` — the root: the catalog and the theme above every screen, the screen for the session's stage, and the navigator the other screens are pushed onto.
- `lib/data/` — talking to the server and keeping the session, no widgets: `server_address.dart` (what counts as a server address), `api_client.dart` (every request), one file per API area (`auth_api.dart`, `browse_api.dart`), and the session — `session.dart` (the stored record), `session_store.dart` (where it's kept), `session_controller.dart` (its stages and rules) and `session_http_client.dart` (the session as an `http.Client`, for a package that sends its own requests); and `epub_book.dart`, an EPUB's chapters — split into blocks of HTML — and files, read from its archive, and `epub_layout.dart`, a fixed-layout page as data — its size, background and placed lines of text, from its XHTML and the book's CSS.
- `lib/i18n/catalog.dart` — the catalog, `CatalogScope` and `context.t()`.
- `lib/ui/` — the screens (`server_screen.dart`, `login_screen.dart`, `home_screen.dart`, `series_screen.dart`, `books_screen.dart`), the frame of a screen that shows a list from the server (`list_screen.dart`), a message in the middle of a screen (`notice.dart`), the layout of a one-form screen (`form_page.dart`), the text a failure shows (`error_text.dart`), images from the server (`server_image.dart`) and from inside an EPUB (`epub_image.dart`), the covers made of them (`cover.dart`) and the cards and grid that show them (`cover_grid.dart`), and the design tokens (`theme.dart`).
- `lib/ui/readers/` — opening a book in the reader for its format (`open_book.dart`) and the readers: `page_reader.dart` for CBZ and image-folder books, `pdf_reader.dart` for PDFs, `epub_reader.dart` for EPUBs; and the page turning a reader shows its pages in (`page_turner.dart`).
- `assets/translations/en.json` — the built-in English: the server's answer to `GET /api/v1/locales/en/translations`, refreshed with the command in [commands.md](commands.md).
- Code in `lib/` is imported by package — `package:bookserver/…` — never by a relative path.

## State
- State lives in `ChangeNotifier`s that screens listen to; services reach screens through constructors — no state-management package.

## API
- Every server call goes through `ApiClient` (`package:http`); request and answer bodies are JSON, read as UTF-8.
- A call answers its result or throws one of three: `ApiException` (`{"error": key}` and its status), `ConnectionException` (no connection, a timeout, or a proxy's 502–504 without a key) or `FormatException` (any other answer). A download also throws `FileSystemException` when its file can't be written.
- A download streams into its file: the timeout covers the wait for the answer and each gap between two chunks, never the whole download, and a download that fails leaves no file.
- `ApiClient.stream` hands back an answer before its body, for a caller that reads the body itself; there a 304 is an answer, not a failure.
- A package that sends its own requests, such as pdfrx, gets a `SessionHttpClient`, never a token: every request goes through `SessionController.authorized`, and only GETs to the session's own server go out.
- Redirects are never followed.
- Tokens travel only in the `Authorization: Bearer` header — never in a URL — and are never printed or logged; neither are passwords.
- A server address is an origin — scheme, host and port, nothing else (`parseServerAddress`).

## Session
- The server's origin, the device id and the session tokens are one record in secure storage (`SessionStore`); a new server replaces the record.
- Every call that needs a session goes through `SessionController.authorized`; nothing else reads tokens.
- One refresh at a time: a call that needs one while another runs waits for it.
- Only a refused refresh, a second 401 or signing out ends a session; a network failure keeps it.
- Release builds use only `https://` server addresses, typed or stored; `kDebugMode` decides.

## Navigation
- A screen opens with `Navigator.push` and a `MaterialPageRoute` on the app's one navigator; no router package.
- When the session's stage leaves `LoggedIn`, `BookserverApp` pops every screen above the first, so nothing that needed the session stays on screen.

## UI
- A list from the server is shown by a `ListScreen`: progress while it loads, the failure with Reload under it, a notice when it's empty, and Reload in the app bar unless the screen turns it off.
- A book opens through `openBook`, the one place that picks the reader for a format; a format without one says so.
- A reader that shows one page at a time turns them in a `PageTurner` — swipe, arrow keys, one zoom for every page, "Page X of Y" — and decodes a page's pictures at the width the turner hands it.
- A PDF is read in byte ranges by pdfrx, never downloaded whole: its pages load progressively and are measured on demand, and pdfrx's block cache (`pdfrx.cache`) is deleted before a PDF opens and after its reader closes.
- An EPUB is downloaded whole into a fresh temp file, which its reader deletes when it closes.
- A flowing EPUB is a list of its blocks — paragraphs, headings, lists — one item each, built in the frame it appears; never one item per chapter.
- An EPUB's pictures, fonts and styles come only from the book itself; a book never makes the app load anything from anywhere else.
- Libraries, series and books are `CoverCard`s in a `CoverGrid`: a cover with its name under it, in as many columns as the width takes, none wider than `Covers.maxTileWidth`.
- Components read design tokens — `lib/ui/theme.dart` and the theme's colour scheme — never literal colours or sizes.
- Every visible string goes through `context.t("namespace.key")` against the backend's translation catalog; values go into its `{placeholders}` — `context.t('browse.volume', {'number': 3})` — never by joining strings.
- An image from the server — a cover, a page — loads through `ServerImage`, never `Image.network`: its request goes through `SessionController.authorized`, and the image cache keeps it under the server and the path.
- Services and controllers throw typed exceptions, never text; a screen shows a failure as the text `errorTextKey` picks.
- Screens catch `Exception`s only: an `Error` is a bug and stays loud.

## Tests
- `test/` mirrors `lib/`: `lib/i18n/catalog.dart` is tested in `test/i18n/catalog_test.dart`; shared fakes live in `test/support/`.
- The server is faked with `FakeServer` (`test/support/fake_server.dart`), built on `package:http`'s `MockClient` — no mocking library; `StreamingFakeServer` for an answer whose body arrives in chunks.
- Secure storage is faked with `MemorySessionStore`; `SecureSessionStore` itself is tested over `FlutterSecureStorage.setMockInitialValues`.
- Code that depends on the time takes a clock (`DateTime Function()`), so tests never wait.
- Screen tests start the whole app as `main()` does, over the fakes (`pumpApp` in `test/support/screens.dart`), and find texts through the catalog, never as literals.
- A widget test answers every request it leaves waiting before it ends: `ApiClient`'s timeout timer must not outlive the test.
- An image test decodes real PNG bytes (`onePixelPng`, `test/support/images.dart`); a widget that loads one is pumped inside `tester.runAsync`, where the decoding can finish.
- Every catalog key written in `lib/` has a built-in English text; `test/i18n/keys_in_code_test.dart` fails otherwise.
- A test taps a card through `cardNamed`: the card's ink layer lies over its name, which never gets the tap itself.
- While a list or a page is still loading, `pumpAndSettle` never returns, since the loading bar or spinner keeps moving; `finishTransition` lets a pushed screen arrive instead.
- A reader test opens its book with `openBook` on the home screen's context, as a tap on the book's card does.
- `flutter test` has no PDFium: a test that opens a PDF sets a `FakePdfEngine` (`test/support/fake_pdf_engine.dart`) as `PdfrxEntryFunctions.instance` and points `Pdfrx.cacheDirectoryPath` at a temp folder; the viewer's settings are tested through `pdfViewerParams`, its rendering by hand.
- `flutter test` has no platform folders: a test that needs one sets a `FakePathProvider` (`test/support/fake_path_provider.dart`) as `PathProviderPlatform.instance`.
- File work — writing a download, reading an archive, decoding a picture — finishes only inside `tester.runAsync`; a test that waits for it pumps there until its text shows (`runUntil` in the EPUB reader's tests). Test EPUBs are built in the test (`test/support/epubs.dart`).
