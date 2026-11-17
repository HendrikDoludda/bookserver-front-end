import 'package:bookserver/i18n/catalog.dart';
import 'package:bookserver/ui/error_text.dart';
import 'package:bookserver/ui/notice.dart';
import 'package:material_ui/material_ui.dart';

/// A screen of a list from the server: progress while it loads, the reason it didn't load with
/// Reload under it, a notice when it's empty, and Reload in the app bar unless [reloadInAppBar]
/// is false.
class ListScreen<T> extends StatefulWidget {
  const ListScreen({
    super.key,
    required this.title,
    required this.load,
    required this.builder,
    required this.emptyKey,
    required this.reloadKey,
    this.reloadInAppBar = true,
    this.actions = const [],
  });

  final String title;

  /// Loads the list: once when the screen opens, and again at every Reload.
  final Future<List<T>> Function() load;

  /// Shows the list once it has loaded with at least one entry.
  final Widget Function(BuildContext context, List<T> items) builder;

  /// The text for an empty list.
  final String emptyKey;

  /// The text of the Reload buttons.
  final String reloadKey;

  /// Whether Reload is in the app bar too, not only under a failure.
  final bool reloadInAppBar;

  /// More app bar buttons, after Reload.
  final List<Widget> actions;

  @override
  State<ListScreen<T>> createState() => _ListScreenState<T>();
}

class _ListScreenState<T> extends State<ListScreen<T>> {
  var _loading = true;
  List<T>? _items;
  String? _errorKey;

  @override
  void initState() {
    super.initState();
    _load();
  }

  void _reload() {
    setState(() => _loading = true);
    _load();
  }

  Future<void> _load() async {
    try {
      final items = await widget.load();
      if (mounted) {
        setState(() {
          _items = items;
          _errorKey = null;
        });
      }
    } on Exception catch (error) {
      if (mounted) {
        setState(
          () => _errorKey = errorTextKey(error, CatalogScope.of(context)),
        );
      }
    } finally {
      if (mounted) {
        setState(() => _loading = false);
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Text(widget.title),
        actions: [
          if (widget.reloadInAppBar)
            // A button rather than pull-to-refresh, which a mouse can't do.
            IconButton(
              icon: const Icon(Icons.refresh),
              tooltip: context.t(widget.reloadKey),
              onPressed: _loading ? null : _reload,
            ),
          ...widget.actions,
        ],
      ),
      body: Stack(
        fit: StackFit.expand,
        children: [
          _content(context),
          if (_loading)
            const Align(
              alignment: Alignment.topCenter,
              child: LinearProgressIndicator(),
            ),
        ],
      ),
    );
  }

  Widget _content(BuildContext context) {
    if (_errorKey case final errorKey?) {
      return Notice(
        text: context.t(errorKey),
        color: Theme.of(context).colorScheme.error,
        action: FilledButton.tonal(
          onPressed: _loading ? null : _reload,
          child: Text(context.t(widget.reloadKey)),
        ),
      );
    }
    return switch (_items) {
      null => const SizedBox.shrink(),
      [] => Notice(text: context.t(widget.emptyKey)),
      final items => widget.builder(context, items),
    };
  }
}
