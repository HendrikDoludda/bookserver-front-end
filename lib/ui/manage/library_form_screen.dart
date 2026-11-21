import 'package:bookserver/data/manage_api.dart';
import 'package:bookserver/data/session_controller.dart';
import 'package:bookserver/i18n/catalog.dart';
import 'package:bookserver/ui/error_text.dart';
import 'package:bookserver/ui/manage/confirm_delete.dart';
import 'package:bookserver/ui/notice.dart';
import 'package:bookserver/ui/theme.dart';
import 'package:material_ui/material_ui.dart';

/// A library's name, type, description and series: for [library], or for a new one when it is
/// null. Saving or deleting closes the form with `true`.
class LibraryFormScreen extends StatefulWidget {
  const LibraryFormScreen({super.key, required this.session, this.library});

  final SessionController session;

  /// The library to edit; null for a new one.
  final ManagedLibrary? library;

  @override
  State<LibraryFormScreen> createState() => _LibraryFormScreenState();
}

class _LibraryFormScreenState extends State<LibraryFormScreen> {
  late final _name = TextEditingController(text: widget.library?.name);
  late final _description = TextEditingController(
    text: widget.library?.description,
  );
  late var _type = widget.library?.type ?? LibraryType.books;

  /// The library as the server holds it: the one being edited, or the one this form created
  /// before a later call failed — so saving again changes it instead of creating a second one.
  late var _saved = widget.library;

  var _loading = true;
  String? _loadErrorKey;

  /// Every series, those in no library first: they are the ones waiting for one.
  var _series = const <ManagedSeries>[];

  /// The series the library holds on the server, and those ticked in the form.
  var _held = <int>{};
  var _chosen = <int>{};

  var _busy = false;
  String? _errorKey;

  @override
  void initState() {
    super.initState();
    _load();
  }

  @override
  void dispose() {
    _name.dispose();
    _description.dispose();
    super.dispose();
  }

  void _reload() {
    setState(() => _loading = true);
    _load();
  }

  Future<void> _load() async {
    try {
      final series = await widget.session.authorized(
        (api, token) => ManageApi(api).allSeries(token),
      );
      final libraryId = widget.library?.id;
      final held = {
        for (final one in series)
          if (one.libraryIds.contains(libraryId)) one.id,
      };
      if (mounted) {
        setState(() {
          _series = [
            ...series.where((one) => one.libraryIds.isEmpty),
            ...series.where((one) => one.libraryIds.isNotEmpty),
          ];
          _held = held;
          _chosen = {...held};
          _loadErrorKey = null;
        });
      }
    } on Exception catch (error) {
      if (mounted) {
        setState(
          () => _loadErrorKey = errorTextKey(error, CatalogScope.of(context)),
        );
      }
    } finally {
      if (mounted) {
        setState(() => _loading = false);
      }
    }
  }

  /// Creates or changes the library, then adds and removes series until the server holds the
  /// ticked ones. Each call is its own [SessionController.authorized]: that repeats a call once
  /// after a 401, and repeating a creation with the calls after it would create two libraries.
  Future<void> _save() async {
    final name = _name.text;
    final description = _description.text.trim().isEmpty
        ? null
        : _description.text;
    final type = _type;
    setState(() {
      _busy = true;
      _errorKey = null;
    });
    try {
      final ManagedLibrary library;
      final saved = _saved;
      if (saved == null) {
        library = await widget.session.authorized(
          (api, token) => ManageApi(api).createLibrary(
            token,
            name: name,
            type: type,
            description: description,
          ),
        );
        _saved = library;
      } else {
        library = saved;
        if (name != saved.name ||
            type != saved.type ||
            description != saved.description) {
          await widget.session.authorized(
            (api, token) => ManageApi(api).changeLibrary(
              token,
              saved.id,
              name: name != saved.name ? name : null,
              type: type != saved.type ? type : null,
              description: description != saved.description
                  ? Change(description)
                  : null,
            ),
          );
          _saved = ManagedLibrary(
            id: saved.id,
            name: name,
            type: type,
            description: description,
            seriesCount: saved.seriesCount,
          );
        }
      }
      final libraryId = library.id;
      for (final seriesId in _chosen.difference(_held)) {
        await widget.session.authorized(
          (api, token) => ManageApi(api).addSeries(token, libraryId, seriesId),
        );
        _held.add(seriesId);
      }
      for (final seriesId in _held.difference(_chosen)) {
        await widget.session.authorized(
          (api, token) =>
              ManageApi(api).removeSeries(token, libraryId, seriesId),
        );
        _held.remove(seriesId);
      }
      if (mounted) {
        Navigator.of(context).pop(true);
      }
    } on Exception catch (error) {
      if (mounted) {
        setState(
          () => _errorKey = errorTextKey(error, CatalogScope.of(context)),
        );
      }
    } finally {
      if (mounted) {
        setState(() => _busy = false);
      }
    }
  }

  Future<void> _delete() async {
    final library = _saved;
    if (library == null) {
      return;
    }
    final confirmed = await confirmDelete(
      context,
      titleKey: 'manage.delete_library',
      explanationKey: 'manage.delete_library_explanation',
    );
    if (!confirmed || !mounted) {
      return;
    }
    setState(() {
      _busy = true;
      _errorKey = null;
    });
    try {
      await widget.session.authorized(
        (api, token) => ManageApi(api).deleteLibrary(token, library.id),
      );
      if (mounted) {
        Navigator.of(context).pop(true);
      }
    } on Exception catch (error) {
      if (mounted) {
        setState(
          () => _errorKey = errorTextKey(error, CatalogScope.of(context)),
        );
      }
    } finally {
      if (mounted) {
        setState(() => _busy = false);
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final ready = !_loading && !_busy && _loadErrorKey == null;
    return Scaffold(
      appBar: AppBar(
        title: Text(
          context.t(
            widget.library == null
                ? 'manage.new_library'
                : 'manage.edit_library',
          ),
        ),
        actions: [
          TextButton(
            onPressed: ready ? _save : null,
            child: Text(context.t('manage.save')),
          ),
        ],
      ),
      body: Stack(
        fit: StackFit.expand,
        children: [
          _content(context),
          if (_loading || _busy)
            const Align(
              alignment: Alignment.topCenter,
              child: LinearProgressIndicator(),
            ),
        ],
      ),
    );
  }

  Widget _content(BuildContext context) {
    final theme = Theme.of(context);
    if (_loadErrorKey case final errorKey?) {
      return Notice(
        text: context.t(errorKey),
        color: theme.colorScheme.error,
        action: FilledButton.tonal(
          onPressed: _loading ? null : _reload,
          child: Text(context.t('manage.reload')),
        ),
      );
    }
    if (_loading) {
      return const SizedBox.shrink();
    }
    return Align(
      alignment: Alignment.topCenter,
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: Widths.form),
        child: ListView(
          padding: const EdgeInsets.all(Spacing.medium),
          children: [
            if (_errorKey case final errorKey?)
              Padding(
                padding: const EdgeInsets.only(bottom: Spacing.medium),
                child: Text(
                  context.t(errorKey),
                  style: TextStyle(color: theme.colorScheme.error),
                ),
              ),
            TextField(
              controller: _name,
              enabled: !_busy,
              decoration: InputDecoration(labelText: context.t('manage.name')),
            ),
            const SizedBox(height: Spacing.medium),
            DropdownButtonFormField<LibraryType>(
              initialValue: _type,
              decoration: InputDecoration(labelText: context.t('manage.type')),
              items: [
                for (final type in LibraryType.values)
                  DropdownMenuItem(
                    value: type,
                    child: Text(context.t(typeTextKey(type))),
                  ),
              ],
              onChanged: _busy
                  ? null
                  : (type) => setState(() => _type = type ?? _type),
            ),
            const SizedBox(height: Spacing.medium),
            TextField(
              controller: _description,
              enabled: !_busy,
              maxLines: null,
              decoration: InputDecoration(
                labelText: context.t('manage.description'),
              ),
            ),
            const SizedBox(height: Spacing.large),
            Text(
              context.t('manage.library_series'),
              style: theme.textTheme.titleMedium,
            ),
            for (final one in _series)
              CheckboxListTile(
                value: _chosen.contains(one.id),
                title: Text(one.name),
                subtitle: one.libraryIds.isEmpty
                    ? Text(context.t('manage.no_library'))
                    : null,
                onChanged: _busy
                    ? null
                    : (ticked) => setState(() {
                        if (ticked ?? false) {
                          _chosen.add(one.id);
                        } else {
                          _chosen.remove(one.id);
                        }
                      }),
              ),
            if (_saved != null) ...[
              const SizedBox(height: Spacing.large),
              OutlinedButton(
                onPressed: _busy ? null : _delete,
                child: Text(context.t('manage.delete')),
              ),
            ],
          ],
        ),
      ),
    );
  }
}

/// The text key of [type]'s name.
String typeTextKey(LibraryType type) => switch (type) {
  LibraryType.books => 'manage.type_books',
  LibraryType.comics => 'manage.type_comics',
  LibraryType.magazines => 'manage.type_magazines',
  LibraryType.documents => 'manage.type_documents',
  LibraryType.others => 'manage.type_others',
};
