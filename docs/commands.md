# Commands

| Command | What it does | Destructive |
|---|---|---|
| `flutter pub get` | Fetch the packages `pubspec.yaml` names, at the versions in `pubspec.lock` | no |
| `flutter pub add <package>` | Add a dependency from [pub.dev](https://pub.dev) | no |
| `flutter test` | Run the automated tests | no |
| `flutter analyze` | Static analysis with the lint rules in `analysis_options.yaml` | no |
| `dart format lib test` | Format the code | no |
| `python3 -c "import json, urllib.request; texts = json.load(urllib.request.urlopen('http://localhost:8080/api/v1/locales/en/translations')); open('assets/translations/en.json', 'w', encoding='utf-8').write(json.dumps(texts, indent=2, sort_keys=True, ensure_ascii=False) + '\n')"` | Refresh the built-in English from the local server, once the backend's English texts changed and the server restarted; a failed fetch leaves the file as it was | no |
| `flutter upgrade` | Update the Flutter SDK — deliberately, since every build then uses the new version | no |
