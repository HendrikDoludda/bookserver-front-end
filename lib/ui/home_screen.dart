import 'package:bookserver/data/session_controller.dart';
import 'package:bookserver/i18n/catalog.dart';
import 'package:material_ui/material_ui.dart';

/// The first screen once signed in.
class HomeScreen extends StatelessWidget {
  const HomeScreen({super.key, required this.session});

  final SessionController session;

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Text(context.t('home.title')),
        actions: [
          IconButton(
            icon: const Icon(Icons.logout),
            tooltip: context.t('home.sign_out'),
            onPressed: session.logOut,
          ),
        ],
      ),
    );
  }
}
