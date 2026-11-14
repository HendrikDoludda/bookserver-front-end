import 'package:bookserver/data/libraries_api.dart';
import 'package:bookserver/data/session_controller.dart';
import 'package:bookserver/i18n/catalog.dart';
import 'package:bookserver/ui/error_text.dart';
import 'package:bookserver/ui/theme.dart';
import 'package:material_ui/material_ui.dart';

/// The first screen once signed in: the server's libraries.
class HomeScreen extends StatefulWidget {
  const HomeScreen({super.key, required this.session});

  final SessionController session;

  @override
  State<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends State<HomeScreen> {
  var _loading = true;
  List<Library>? _libraries;
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
      final libraries = await widget.session.authorized(
        (api, sessionToken) => LibrariesApi(api).list(sessionToken),
      );
      if (mounted) {
        setState(() {
          _libraries = libraries;
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
        title: Text(context.t('home.title')),
        actions: [
          // A button rather than pull-to-refresh, which a mouse can't do.
          IconButton(
            icon: const Icon(Icons.refresh),
            tooltip: context.t('home.reload'),
            onPressed: _loading ? null : _reload,
          ),
          IconButton(
            icon: const Icon(Icons.logout),
            tooltip: context.t('home.sign_out'),
            onPressed: widget.session.logOut,
          ),
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
      return _Notice(
        text: context.t(errorKey),
        color: Theme.of(context).colorScheme.error,
        action: FilledButton.tonal(
          onPressed: _loading ? null : _reload,
          child: Text(context.t('home.reload')),
        ),
      );
    }
    return switch (_libraries) {
      null => const SizedBox.shrink(),
      [] => _Notice(text: context.t('home.empty')),
      final libraries => ListView.builder(
        itemCount: libraries.length,
        itemBuilder: (context, index) =>
            ListTile(title: Text(libraries[index].name)),
      ),
    };
  }
}

class _Notice extends StatelessWidget {
  const _Notice({required this.text, this.color, this.action});

  final String text;
  final Color? color;
  final Widget? action;

  @override
  Widget build(BuildContext context) {
    return Center(
      child: SingleChildScrollView(
        padding: const EdgeInsets.all(Spacing.large),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          spacing: Spacing.medium,
          children: [
            Text(
              text,
              textAlign: TextAlign.center,
              style: TextStyle(color: color),
            ),
            ?action,
          ],
        ),
      ),
    );
  }
}
