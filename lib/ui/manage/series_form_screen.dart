import 'package:bookserver/data/api_client.dart';
import 'package:bookserver/data/browse_api.dart';
import 'package:bookserver/data/manage_api.dart';
import 'package:bookserver/data/session_controller.dart';
import 'package:bookserver/i18n/catalog.dart';
import 'package:bookserver/ui/books_screen.dart';
import 'package:bookserver/ui/cover.dart';
import 'package:bookserver/ui/error_text.dart';
import 'package:bookserver/ui/manage/confirm_delete.dart';
import 'package:bookserver/ui/manage/cover_choice_screen.dart';
import 'package:bookserver/ui/theme.dart';
import 'package:flutter/services.dart';
import 'package:material_ui/material_ui.dart';

/// A series' name, description, release years and cover. Saving or deleting closes the form with
/// `true`; a series with books can't be deleted, and the form says so.
class SeriesFormScreen extends StatefulWidget {
  const SeriesFormScreen({
    super.key,
    required this.session,
    required this.series,
  });

  final SessionController session;
  final ManagedSeries series;

  @override
  State<SeriesFormScreen> createState() => _SeriesFormScreenState();
}

class _SeriesFormScreenState extends State<SeriesFormScreen> {
  late final _name = TextEditingController(text: widget.series.name);
  late final _description = TextEditingController(
    text: widget.series.description,
  );
  late final _startYear = TextEditingController(
    text: widget.series.startYear?.toString(),
  );
  late final _endYear = TextEditingController(
    text: widget.series.endYear?.toString(),
  );

  var _busy = false;
  String? _errorKey;

  /// What saving does with the cover; null leaves it as it is.
  CoverChoice? _cover;

  @override
  void dispose() {
    _name.dispose();
    _description.dispose();
    _startYear.dispose();
    _endYear.dispose();
    super.dispose();
  }

  Future<void> _chooseCover() async {
    final seriesId = widget.series.id;
    final choice = await Navigator.of(context).push<CoverChoice>(
      MaterialPageRoute(
        builder: (_) => CoverChoiceScreen<Book>(
          session: widget.session,
          kind: CoverKind.book,
          load: () => widget.session.authorized(
            (api, token) => BrowseApi(api).booksOf(seriesId, token),
          ),
          idOf: (book) => book.id,
          nameOf: bookName,
        ),
      ),
    );
    if (choice != null && mounted) {
      setState(() => _cover = choice);
    }
  }

  /// Sends only the fields that changed, then the cover picked; with neither, the form just
  /// closes.
  Future<void> _save() async {
    final series = widget.series;
    final name = _name.text;
    final description = _description.text.trim().isEmpty
        ? null
        : _description.text;
    final startYear = int.tryParse(_startYear.text);
    final endYear = int.tryParse(_endYear.text);
    final fieldsUnchanged =
        name == series.name &&
        description == series.description &&
        startYear == series.startYear &&
        endYear == series.endYear;
    final cover = _cover;
    if (fieldsUnchanged && cover == null) {
      Navigator.of(context).pop(false);
      return;
    }
    await _run([
      if (!fieldsUnchanged)
        (api, token) => ManageApi(api).changeSeries(
          token,
          series.id,
          name: name != series.name ? name : null,
          description: description != series.description
              ? Change(description)
              : null,
          startYear: startYear != series.startYear ? Change(startYear) : null,
          endYear: endYear != series.endYear ? Change(endYear) : null,
        ),
      if (cover != null)
        (api, token) => switch (cover) {
          PickedCover(:final id) => ManageApi(
            api,
          ).chooseSeriesCover(token, series.id, id),
          AutomaticCover() => ManageApi(api).resetSeriesCover(token, series.id),
        },
    ]);
  }

  Future<void> _delete() async {
    final confirmed = await confirmDelete(
      context,
      titleKey: 'manage.delete_series',
      explanationKey: 'manage.delete_series_explanation',
    );
    if (confirmed && mounted) {
      await _run([
        (api, token) => ManageApi(api).deleteSeries(token, widget.series.id),
      ]);
    }
  }

  /// Runs [calls] in turn, each in its own [SessionController.authorized]; closes the form when
  /// all succeed, else says why.
  Future<void> _run(
    List<Future<void> Function(ApiClient api, String token)> calls,
  ) async {
    setState(() {
      _busy = true;
      _errorKey = null;
    });
    try {
      try {
        for (final call in calls) {
          await widget.session.authorized(call);
        }
      } finally {
        // Also after a failure: a call before it may have changed what a cover shows.
        await _forgetCovers();
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

  /// Drops the covers this form can change from the image cache: the series' own, and its
  /// libraries', which fall back to their first series by name.
  Future<void> _forgetCovers() => Future.wait([
    Cover.forget(widget.session, CoverKind.series, [widget.series.id]),
    Cover.forget(widget.session, CoverKind.library, widget.series.libraryIds),
  ]);

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Scaffold(
      appBar: AppBar(
        title: Text(context.t('manage.edit_series')),
        actions: [
          TextButton(
            onPressed: _busy ? null : _save,
            child: Text(context.t('manage.save')),
          ),
        ],
      ),
      body: Stack(
        fit: StackFit.expand,
        children: [
          Align(
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
                    decoration: InputDecoration(
                      labelText: context.t('manage.name'),
                    ),
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
                  const SizedBox(height: Spacing.medium),
                  Row(
                    spacing: Spacing.medium,
                    children: [
                      Expanded(
                        child: _YearField(
                          controller: _startYear,
                          enabled: !_busy,
                          label: context.t('manage.start_year'),
                        ),
                      ),
                      Expanded(
                        child: _YearField(
                          controller: _endYear,
                          enabled: !_busy,
                          label: context.t('manage.end_year'),
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: Spacing.medium),
                  CoverField(
                    session: widget.session,
                    current: (kind: CoverKind.series, id: widget.series.id),
                    candidates: CoverKind.book,
                    choice: _cover,
                    onTap: _busy ? null : _chooseCover,
                  ),
                  const SizedBox(height: Spacing.large),
                  OutlinedButton(
                    onPressed: _busy ? null : _delete,
                    child: Text(context.t('manage.delete')),
                  ),
                ],
              ),
            ),
          ),
          if (_busy)
            const Align(
              alignment: Alignment.topCenter,
              child: LinearProgressIndicator(),
            ),
        ],
      ),
    );
  }
}

/// A year of up to four digits; left empty, the year is unknown.
class _YearField extends StatelessWidget {
  const _YearField({
    required this.controller,
    required this.enabled,
    required this.label,
  });

  final TextEditingController controller;
  final bool enabled;
  final String label;

  @override
  Widget build(BuildContext context) {
    return TextField(
      controller: controller,
      enabled: enabled,
      keyboardType: TextInputType.number,
      inputFormatters: [
        FilteringTextInputFormatter.digitsOnly,
        LengthLimitingTextInputFormatter(4),
      ],
      decoration: InputDecoration(labelText: label),
    );
  }
}
