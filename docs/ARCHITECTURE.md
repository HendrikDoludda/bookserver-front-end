# Architecture

## Where things live
- `lib/main.dart` — start-up: loads the built-in English, then runs the app.
- `lib/app.dart` — the root: the catalog and the theme above every screen.
- `lib/i18n/catalog.dart` — the catalog, `CatalogScope` and `context.t()`.
- `lib/ui/` — the screens; `theme.dart` holds the design tokens.
- `assets/translations/en.json` — the built-in English: the server's answer to `GET /api/v1/locales/en/translations`, refreshed with the command in [commands.md](commands.md).
- Imports name the package — `package:bookserver/…` — never a relative path.

## UI
- Components read design tokens — `lib/ui/theme.dart` and the theme's colour scheme — never literal colours or sizes.
- Every visible string goes through `context.t("namespace.key")` against the backend's translation catalog.

## Tests
- `test/` mirrors `lib/`: `lib/i18n/catalog.dart` is tested in `test/i18n/catalog_test.dart`.
- Every catalog key written in `lib/` has a built-in English text; `test/i18n/keys_in_code_test.dart` fails otherwise.
