# Architecture

## Where things live
- `lib/main.dart` — start-up: loads the built-in English, the stored connection and the kept catalog, sets the catalog following the session, then runs the app.
- `lib/app.dart` — the root: `CatalogController`'s catalog, Material's locale for it (`materialLocaleOf`) and the theme above every screen, the screen for the session's stage, and the navigator the other screens are pushed onto.
- `lib/data/` — talking to the server and keeping the session, no widgets: `server_address.dart` (what counts as a server address), `api_client.dart` (every request), one file per API area (`auth_api.dart`, `browse_api.dart`, `locales_api.dart` — the languages on offer and their texts, `settings_api.dart` — the user's own settings, `two_factor_api.dart` — their two-factor authentication), `catalog_store.dart` (the last catalog from the server, kept between launches), `preferences.dart` (what this device keeps for whoever uses it: the hand that holds it), `json_file.dart` (a JSON file in the app's support folder, written whole or not at all), and the session — `session.dart` (the stored record), `session_store.dart` (where it's kept), `session_controller.dart` (its stages and rules) and `session_http_client.dart` (the session as an `http.Client`, for a package that sends its own requests); and `epub_book.dart`, an EPUB's chapters — split into blocks of HTML — and files, read from its archive, and `epub_layout.dart`, a fixed-layout page as data — its size, background and placed lines of text, from its XHTML and the book's CSS.
- `lib/i18n/catalog.dart` — the catalog in its language with a fallback for the keys it lacks, `CatalogScope`, `context.t()` and `context.plural()`; `catalog_controller.dart` — which language the app shows (`pickLanguage`) and its catalog from the server (`CatalogController`).
- `lib/ui/` — the screens (`server_screen.dart`, `login_screen.dart`, `login_code_screen.dart`, `sign_up_screen.dart`, `verify_email_screen.dart`, `forgot_password_screen.dart`, `reset_password_screen.dart`, `home_screen.dart`, `settings_screen.dart`, `two_factor_setup_screen.dart`, `recovery_codes_screen.dart`, `code_and_password_screen.dart`, `series_screen.dart`, `books_screen.dart`), the frame of a screen that shows a list from the server (`list_screen.dart`), the signed-in user's menu (`user_menu.dart`), the libraries to switch to from inside one (`library_sidebar.dart`), a message in the middle of a screen (`notice.dart`), the layout of a one-form screen, with Back when it was pushed (`form_page.dart`), the text a failure shows (`error_text.dart`), images from the server (`server_image.dart`) and from inside an EPUB (`epub_image.dart`), a QR code (`qr_code.dart`), the covers made of them (`cover.dart`) and the cards and grid that show them (`cover_grid.dart`), whether the app runs on a phone or tablet (`platform.dart`), the device's preferences for the widgets below (`preferences_scope.dart`), and the design tokens (`theme.dart`).
- `lib/ui/readers/` — opening a book in the reader for its format (`open_book.dart`) and the readers: `page_reader.dart` for CBZ and image-folder books, `pdf_reader.dart` for PDFs, `epub_reader.dart` for EPUBs, `fixed_layout_page.dart` for a fixed-layout EPUB's pages; the frame every reader shows its book in, with its bars (`reader_frame.dart`); the page turning a reader shows its pages in (`page_turner.dart`); what a tap on a page does by where it lands (`tap_zones.dart`); and the button in a reader's bar that switches the reading mode and saves it for the series (`reading_mode_button.dart`).
- `assets/translations/en.json` — the built-in English: the server's answer to `GET /api/v1/locales/en/translations`, refreshed with the command in [commands.md](commands.md).
- Code in `lib/` is imported by package — `package:bookserver/…` — never by a relative path.

## State
- State lives in `ChangeNotifier`s that screens listen to; services reach screens through constructors — no state-management package.
- What the device keeps for whoever uses it is one `PreferencesController`, which `PreferencesScope` gives every widget; it lives in `preferences.json` in the app's support folder, outside the session record, so it outlasts signing out and changing servers.

## API
- Every server call goes through `ApiClient` (`package:http`); request and answer bodies are JSON, read as UTF-8.
- A call answers its result or throws one of three: `ApiException` (`{"error": key}` and its status), `ConnectionException` (no connection, a timeout, or a proxy's 502–504 without a key) or `FormatException` (any other answer). A download also throws `FileSystemException` when its file can't be written.
- A download streams into its file: the timeout covers the wait for the answer and each gap between two chunks, never the whole download, and a download that fails leaves no file.
- `ApiClient.stream` hands back an answer before its body, for a caller that reads the body itself; there a 304 is an answer, not a failure.
- `ApiClient.revalidate` names an ETag in `If-None-Match` and answers the whole body; there too a 304 is an answer.
- A package that sends its own requests, such as pdfrx, gets a `SessionHttpClient`, never a token: every request goes through `SessionController.authorized`, and only GETs to the session's own server go out.
- Redirects are never followed.
- Tokens travel only in the `Authorization: Bearer` header — never in a URL — and are never printed or logged; neither are passwords.
- A password or a code lives only in the state of the screen that asks for it, and goes from there straight into a request; nothing stores one.
- A server address is an origin — scheme, host and port, nothing else (`parseServerAddress`).

## Session
- The server's origin, the device id and the session tokens are one record in secure storage (`SessionStore`); a new server replaces the record.
- Every call that needs a session goes through `SessionController.authorized`; nothing else reads tokens.
- One refresh at a time: a call that needs one while another runs waits for it.
- Only a refused refresh, a second 401 or signing out ends a session; a network failure keeps it.
- Release builds use only `https://` server addresses, typed or stored; `kDebugMode` decides.

## Catalog
- The catalog on screen is `CatalogController`'s: the built-in English, or the copy kept from the session's server, until the server's catalog in the picked language arrives. It picks again whenever the session's server or sign-in changes; nothing waits for the server.
- The language is the user's setting while the server offers it, else the device's languages in order — the same language and region, else the language, else a code of that language — else the server's default (`pickLanguage`).
- A catalog from the server falls back key by key to the built-in English.
- Sign-up sends the language of the server's catalog on screen (`serverLanguage`), never the built-in English's, which the server may not offer.
- A language saved in the settings shows at once: the settings screen saves it, then calls `pickAgain`.
- In the language list each language is written in itself, and "Device language" in the language choosing it shows (`deviceLanguage`, `catalogIn`), so someone who can't read the screen still finds the way back.
- The last catalog from the server is kept as `catalog.json` in the app's support folder — plain JSON, nothing in it is secret — written whole or not at all, one write at a time. A fetch in its server and language sends its ETag as `If-None-Match`; a 304 keeps it.
- Material's own texts — the Back tooltip, the Cut/Copy/Paste menu — and the text direction follow the catalog's language where `material_ui` has texts for it, else English (`materialLocaleOf`).
- A failed pick — no connection, a refusal, a broken answer, an ended session, a full disk — keeps the catalog on screen; a pick a newer one overtook drops its answer.

## Navigation
- A screen opens with `Navigator.push` and a `MaterialPageRoute` on the app's one navigator; no router package.
- When the session's stage changes kind — `NeedsServer`, `LoggedOut`, `LoggedIn` — `BookserverApp` pops every screen above the first, so nothing pushed for the stage before stays on screen.
- Recovery codes are shown on a screen only Done leaves: no Back, and the system's Back is blocked.
- Turning two-factor off signs out here at once, with a notice for the login screen (`logOut(noticeKey:)`), since the server ends every session of the user.
- On a phone, the two-factor setup offers to open its `otpauth://` link in the authenticator app (`url_launcher`): a phone can't scan its own screen.
- The account flows before a session — the code step, sign-up, the password reset — are pushed from the login screen. A login answering `email_not_verified`, like a sign-up answering 202, opens the verification screen with the name and password just typed. A password reset pops back to the login screen with the address it used, which fills in the name.

## UI
- A list from the server is shown by a `ListScreen`: progress while it loads, the failure with Reload under it, a notice when it's empty, and Reload in the app bar unless the screen turns it off.
- Every browse screen has the user menu (`UserMenu`: Settings, Sign out) last in its top bar.
- A `ListScreen`'s `sidebar` sits beside the list from `Breakpoints.sidebarBeside` wide and is a drawer below it, opened only by its button next to Back — a drag from the left edge goes back on iOS.
- Inside a library, the screens get the libraries the grid loaded; the sidebar asks the server for nothing.
- A book opens through `openBook`, the one place that picks the reader for a format; a format without one says so.
- A reader shows its book in a `ReaderFrame`: Back, the title and the reader's controls in bars that lie over the pages — all in one bar at the top on a desktop, the controls in a bar at the bottom on a phone or tablet, gathered on the thumb's side — shown when the book opens, hidden once its pages move, toggled by a tap in the middle of a page that nothing on it takes; "Page X of Y" sits under the pages.
- Phones and tablets are iOS and Android (`isPhoneOrTablet`); every other platform is a desktop.
- Controls follow the thumb by physical side, never by text direction: a floating action button sits in the bottom corner on the side of the hand the device's preferences name.
- A reader that shows one page at a time turns them in a `PageTurner` — swipe, arrow keys, a tap on either edge, one zoom for every page — which reports the page it lands on and decodes a page's pictures at the width it hands the page.
- A book's pages run by its reading mode alone, never by the text direction: page order, swipes, arrow keys and tap zones are physical sides, as the thumb's controls are.
- A tap on a page goes through `tapZoneAt`: the outer thirds turn the pages — right to left, the left one goes forward — and the middle third shows and hides the bars.
- A reader that has reading modes asks `GET /books/{id}` for its mode while it loads its pages, and reads a mode the app doesn't know as its own default. A mode chosen shows at once and is then saved for the book's series (`ReadingModeButton`); a failed save keeps it on screen and says so.
- A PDF is read in byte ranges by pdfrx, never downloaded whole: its pages load progressively and are measured on demand, and pdfrx's block cache (`pdfrx.cache`) is deleted before a PDF opens and after its reader closes.
- An EPUB is downloaded whole into a fresh temp file, which its reader deletes when it closes.
- A fixed-layout EPUB is read page by page in a `PageTurner`, in the direction its spine's `page-progression-direction` states: each page drawn at the size the book gives it and scaled to fit, parsed only while the pages hold still (`PageTurnerState.moving`), its fonts loaded once per app run under `book<id>-<family>`.
- A flowing EPUB is a list of its blocks — paragraphs, headings, lists — one item each, built in the frame it appears; never one item per chapter. The list's length is guessed from the blocks' text, never left to Flutter's average of the blocks on screen.
- An EPUB's pictures, fonts and styles come only from the book itself; a book never makes the app load anything from anywhere else.
- Libraries, series and books are `CoverCard`s in a `CoverGrid`: a cover with its name under it, in as many columns as the width takes, none wider than `Covers.maxTileWidth`. Libraries and series show their count in a `detail` line under the name; a grid whose cards have one is built `withDetail`, which gives every card room for that line.
- Components read design tokens — `lib/ui/theme.dart` and the theme's colour scheme — never literal colours or sizes. The one exception is the QR code: black on white in both themes, since scanners read dark modules on a light ground.
- Every visible string goes through `context.t("namespace.key")` against the backend's translation catalog; values go into its `{placeholders}` — `context.t('browse.volume', {'number': 3})` — never by joining strings.
- A text with a count goes through `context.plural('namespace.key', count)`: one key per plural form (`key.one`, `key.other` …), picked by the catalog language's plural rules (`intl`), `.other` when a form is missing; `{count}` is in every form.
- An image from the server — a cover, a page — loads through `ServerImage`, never `Image.network`: its request goes through `SessionController.authorized`, and the image cache keeps it under the server and the path — a load or a decode that failed it drops, so the next request asks the server again.
- Services and controllers throw typed exceptions, never text; a screen shows a failure as the text `errorTextKey` picks.
- Screens catch `Exception`s only: an `Error` is a bug and stays loud.

## Builds
- An Android release build is signed with the release key `android/key.properties` names; the file and the keystore stay outside git, and without the file a release build stops. One universal APK, for every phone.
- Each platform's release build and how it reaches a device is in its run doc: [android](run-deploy/android.md), [ios](run-deploy/ios.md), [macos](run-deploy/macos.md), [windows](run-deploy/windows.md), [linux](run-deploy/linux.md).
- iOS builds sign with the developer's free personal Apple team that the project names, and only on a Mac whose Xcode has that account; macOS builds sign ad hoc until 73's signing tasks.
- Windows builds on a Windows PC. Linux builds in Docker (`docker/linux.Dockerfile`), on any machine, and only the bundle leaves the container; its ignore file keeps the Mac's build output and every signing secret out of the image.

## Tests
- `test/` mirrors `lib/`: `lib/i18n/catalog.dart` is tested in `test/i18n/catalog_test.dart`; shared fakes live in `test/support/`.
- The server is faked with `FakeServer` (`test/support/fake_server.dart`), built on `package:http`'s `MockClient` — no mocking library; `StreamingFakeServer` for an answer whose body arrives in chunks.
- Secure storage is faked with `MemorySessionStore`; `SecureSessionStore` itself is tested over `FlutterSecureStorage.setMockInitialValues`.
- The kept catalog is faked with `MemoryCatalogStore`; `FileCatalogStore` itself is tested on a temp folder.
- The device's preferences are faked with `MemoryPreferencesStore`: `pumpApp` and `pumpScreen` give every test the defaults unless it passes a `PreferencesController` of its own.
- Code that depends on the time takes a clock (`DateTime Function()`), so tests never wait.
- Screen tests start the whole app as `main()` does, over the fakes (`pumpApp` in `test/support/screens.dart`), and find texts through the catalog, never as literals. The catalog stays the one given unless the test passes `followCatalog: true` and answers the catalog's requests, so the other tests' requests stay their own.
- A widget test answers every request it leaves waiting before it ends: `ApiClient`'s timeout timer must not outlive the test.
- An image test decodes real PNG bytes (`onePixelPng`, `test/support/images.dart`); a widget that loads one is pumped inside `tester.runAsync`, where the decoding can finish.
- Every catalog key written in `lib/` has a built-in English text — a plural key its `.other` form; `test/i18n/keys_in_code_test.dart` fails otherwise.
- A test taps a card through `cardNamed`: the card's ink layer lies over its name, which never gets the tap itself.
- While a list or a page is still loading, `pumpAndSettle` never returns, since the loading bar or spinner keeps moving; `finishTransition` lets a pushed screen arrive instead.
- A reader test opens its book with `openBook` on the home screen's context, as a tap on the book's card does.
- Text on a scaled page is tapped at its box's `localToGlobal`, never with `tapOnText`, which leaves out the scale.
- `flutter test` has no PDFium: a test that opens a PDF sets a `FakePdfEngine` (`test/support/fake_pdf_engine.dart`) as `PdfrxEntryFunctions.instance` and points `Pdfrx.cacheDirectoryPath` at a temp folder; the viewer's settings are tested through `pdfViewerParams`, its rendering by hand.
- `flutter test` has no platform folders: a test that needs one sets a `FakePathProvider` (`test/support/fake_path_provider.dart`) as `PathProviderPlatform.instance`.
- File work — writing a download, reading an archive, decoding a picture — finishes only inside `tester.runAsync`; a test that waits for it pumps there until its text shows (`runUntil` in the EPUB reader's tests). Test EPUBs are built in the test (`test/support/epubs.dart`).
