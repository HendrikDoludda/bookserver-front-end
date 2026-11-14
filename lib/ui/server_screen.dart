import 'package:bookserver/data/session_controller.dart';
import 'package:bookserver/i18n/catalog.dart';
import 'package:bookserver/ui/error_text.dart';
import 'package:bookserver/ui/form_page.dart';
import 'package:material_ui/material_ui.dart';

/// Asks for the server's address and checks that a book server answers there.
class ServerScreen extends StatefulWidget {
  const ServerScreen({super.key, required this.session});

  final SessionController session;

  @override
  State<ServerScreen> createState() => _ServerScreenState();
}

class _ServerScreenState extends State<ServerScreen> {
  final _address = TextEditingController();
  var _busy = false;
  String? _errorKey;

  @override
  void dispose() {
    _address.dispose();
    super.dispose();
  }

  Future<void> _connect() async {
    setState(() {
      _busy = true;
      _errorKey = null;
    });
    try {
      await widget.session.useServer(_address.text);
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
    final errorKey = _errorKey;
    return FormPage(
      children: [
        Text(
          context.t('server.title'),
          style: Theme.of(context).textTheme.headlineSmall,
        ),
        TextField(
          controller: _address,
          enabled: !_busy,
          autofocus: true,
          keyboardType: TextInputType.url,
          autocorrect: false,
          enableSuggestions: false,
          textInputAction: TextInputAction.go,
          onSubmitted: (_) => _connect(),
          decoration: InputDecoration(
            labelText: context.t('server.address_label'),
            hintText: context.t('server.address_hint'),
            errorText: errorKey == null ? null : context.t(errorKey),
            errorMaxLines: 3,
          ),
        ),
        FilledButton(
          onPressed: _busy ? null : _connect,
          child: Text(context.t('server.connect')),
        ),
        if (_busy) const LinearProgressIndicator(),
      ],
    );
  }
}
