import 'package:bookserver/data/account_controller.dart';
import 'package:bookserver/data/session_controller.dart';
import 'package:bookserver/i18n/catalog.dart';
import 'package:bookserver/i18n/catalog_controller.dart';
import 'package:bookserver/ui/manage/manage_screen.dart';
import 'package:bookserver/ui/settings_screen.dart';
import 'package:material_ui/material_ui.dart';

/// The signed-in user's menu, at the top right of the browse screens: Settings, Manage for an
/// admin, and Sign out.
class UserMenu extends StatelessWidget {
  const UserMenu({
    super.key,
    required this.session,
    required this.catalogs,
    required this.account,
  });

  final SessionController session;
  final CatalogController catalogs;
  final AccountController account;

  @override
  Widget build(BuildContext context) {
    return PopupMenuButton<_Entry>(
      icon: const Icon(Icons.account_circle),
      tooltip: context.t('menu.user'),
      onSelected: (entry) {
        switch (entry) {
          case _Entry.settings:
            Navigator.of(context).push(
              MaterialPageRoute<void>(
                builder: (_) =>
                    SettingsScreen(session: session, catalogs: catalogs),
              ),
            );
          case _Entry.manage:
            Navigator.of(context).push(
              MaterialPageRoute<void>(
                builder: (_) => ManageScreen(session: session),
              ),
            );
          case _Entry.signOut:
            session.logOut();
        }
      },
      itemBuilder: (context) => [
        PopupMenuItem(
          value: _Entry.settings,
          child: Text(context.t('menu.settings')),
        ),
        if (account.isAdmin)
          PopupMenuItem(
            value: _Entry.manage,
            child: Text(context.t('menu.manage')),
          ),
        PopupMenuItem(
          value: _Entry.signOut,
          child: Text(context.t('menu.sign_out')),
        ),
      ],
    );
  }
}

enum _Entry { settings, manage, signOut }
