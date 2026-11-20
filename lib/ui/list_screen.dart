import 'package:bookserver/i18n/catalog.dart';
import 'package:bookserver/ui/error_text.dart';
import 'package:bookserver/ui/notice.dart';
import 'package:bookserver/ui/theme.dart';
import 'package:material_ui/material_ui.dart';

/// A screen of a list from the server: progress while it loads, the reason it didn't load with
/// Reload under it, a notice when it's empty, and Reload in the app bar unless [reloadInAppBar]
/// is false. A [sidebar] sits beside the list in a wide window and over it in a narrow one.
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
    this.sidebar,
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

  /// A panel beside the list from [Breakpoints.sidebarBeside] wide, shown until its button hides
  /// it; narrower, a drawer its button opens over the list.
  final Widget? sidebar;

  @override
  State<ListScreen<T>> createState() => _ListScreenState<T>();
}

class _ListScreenState<T> extends State<ListScreen<T>> {
  var _loading = true;
  List<T>? _items;
  String? _errorKey;
  var _sidebarShown = true;

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
    final sidebar = widget.sidebar;
    final beside =
        MediaQuery.sizeOf(context).width >= Breakpoints.sidebarBeside;
    final list = Stack(
      fit: StackFit.expand,
      children: [
        _content(context),
        if (_loading)
          const Align(
            alignment: Alignment.topCenter,
            child: LinearProgressIndicator(),
          ),
      ],
    );
    return Scaffold(
      appBar: AppBar(
        leading: sidebar == null ? null : _sidebarButtons(context, beside),
        leadingWidth: sidebar == null
            ? null
            : 2 * kMinInteractiveDimension + Spacing.small,
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
      drawer: sidebar != null && !beside ? Drawer(child: sidebar) : null,
      // Only the button opens the drawer: on iOS a drag from the left edge goes back.
      drawerEnableOpenDragGesture: false,
      body: sidebar != null && beside && _sidebarShown
          ? Row(
              children: [
                SizedBox(width: Widths.sidebar, child: sidebar),
                const VerticalDivider(),
                Expanded(child: list),
              ],
            )
          : list,
    );
  }

  /// Back, and the sidebar's button beside it: with a drawer, the app bar would otherwise show the
  /// drawer's button in place of Back.
  Widget _sidebarButtons(BuildContext context, bool beside) => Row(
    mainAxisAlignment: MainAxisAlignment.end,
    children: [
      if (Navigator.of(context).canPop()) const BackButton(),
      Builder(
        builder: (context) => IconButton(
          icon: const Icon(Icons.menu),
          tooltip: context.t('menu.libraries'),
          onPressed: beside
              ? () => setState(() => _sidebarShown = !_sidebarShown)
              : () => Scaffold.of(context).openDrawer(),
        ),
      ),
    ],
  );

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
