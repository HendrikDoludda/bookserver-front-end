import 'package:bookserver/data/api_client.dart';
import 'package:bookserver/data/manage_api.dart';
import 'package:bookserver/data/session_controller.dart';
import 'package:bookserver/i18n/catalog.dart';
import 'package:bookserver/ui/error_text.dart';
import 'package:bookserver/ui/manage/confirm_delete.dart';
import 'package:bookserver/ui/theme.dart';
import 'package:flutter/services.dart';
import 'package:material_ui/material_ui.dart';

/// A series' name, description and release years. Saving or deleting closes the form with
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

  @override
  void dispose() {
    _name.dispose();
    _description.dispose();
    _startYear.dispose();
    _endYear.dispose();
    super.dispose();
  }

  /// Sends only the fields that changed; with none, the form just closes.
  Future<void> _save() async {
    final series = widget.series;
    final name = _name.text;
    final description = _description.text.trim().isEmpty
        ? null
        : _description.text;
    final startYear = int.tryParse(_startYear.text);
    final endYear = int.tryParse(_endYear.text);
    final unchanged =
        name == series.name &&
        description == series.description &&
        startYear == series.startYear &&
        endYear == series.endYear;
    if (unchanged) {
      Navigator.of(context).pop(false);
      return;
    }
    await _run(
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
    );
  }

  Future<void> _delete() async {
    final confirmed = await confirmDelete(
      context,
      titleKey: 'manage.delete_series',
      explanationKey: 'manage.delete_series_explanation',
    );
    if (confirmed && mounted) {
      await _run(
        (api, token) => ManageApi(api).deleteSeries(token, widget.series.id),
      );
    }
  }

  /// Runs [call] with the session; closes the form when it succeeds, else says why.
  Future<void> _run(
    Future<void> Function(ApiClient api, String token) call,
  ) async {
    setState(() {
      _busy = true;
      _errorKey = null;
    });
    try {
      await widget.session.authorized(call);
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
