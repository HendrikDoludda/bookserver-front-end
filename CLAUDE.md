# CLAUDE.md

Project guidance for Claude Code.

The **Flutter app** for the book / manga / comic home server — the client people browse and
read with. The server, its documentation and the working rules for both repositories live in
[bookserver_backend](../bookserver_backend); its CLAUDE.md is imported here:

@../bookserver_backend/CLAUDE.md

## In this repository

All of it applies here — how we work, the writing and code-comment rules, scope, tests,
planning, the verification gate, destructive commands, git — except its Stack and Rules learned,
which are the backend's. Where this file says something else, this file wins.

- **Learning.** The developer is new to Dart and Flutter as well: explain the Dart, Flutter or
  package concept behind each change, as rule 2 asks.
- **The API is the contract.** Routes: the backend's `src/routes/api_routes.rs`; bodies:
  `src/data_models/`; error keys and API rules: its `docs/ARCHITECTURE.md`. Read the handler
  and its structs before writing a call — never guess a JSON shape.
- **No server changes from here.** A task that needs one stops; the change becomes a [BE]
  task in the feature doc, built in the backend repository under its own plan.

## Where the docs live

Feature work is documented centrally in the backend repository; this repository's `docs/`
holds only what is about this code.

| In the imported rules | Here |
|---|---|
| `docs/features/`, `build-checklist.md`, `project-state.md`, the `-found.md` and `-checks.md` files | `../bookserver_backend/docs/` |
| `docs/ARCHITECTURE.md`, `commands.md`, `run-deploy/`, `setup.md` | this repository's `docs/` |

## Stack

Flutter 3.50 (stable) · Dart 3.14 · Material from the `material_ui` package
(`package:material_ui/material_ui.dart`, as the 3.50 template sets it up) · flutter_lints 6 ·
`package:http` 1.6 for every server call · flutter_secure_storage 11.2 for the session · pdfrx 2.13
for PDFs, with its own PDFium built into the app · for EPUBs: archive 4.7, xml 7.1, html 0.15,
csslib 1.0, flutter_widget_from_html_core 0.17 and path_provider 2.1.
Code lives in `lib/`, tests in `test/`; the platforms are the native folders that exist.

### Rules learned

Frontend rules only, in the backend's table format.

| Rule | Why it bites |
|---|---|
| Judge rendering performance on an Apple Silicon Mac or a phone, never on the Intel Mac | Impeller on Intel GPUs holds gigabytes of graphics memory and stalls frames up to 0.8 s; a day went into tuning pdfrx against it |
| Never queue work with `scheduleTask(…, Priority.idle)` | While anything animates, Flutter requeues the task with `Timer.run` in a busy loop; a widget test's fake clock then runs that loop forever and the test hangs |
