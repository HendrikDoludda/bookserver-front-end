import 'package:bookserver/data/browse_api.dart';
import 'package:bookserver/data/session_controller.dart';
import 'package:bookserver/i18n/catalog.dart';
import 'package:bookserver/ui/readers/epub_reader.dart';
import 'package:bookserver/ui/readers/page_reader.dart';
import 'package:bookserver/ui/readers/pdf_reader.dart';
import 'package:material_ui/material_ui.dart';

/// Opens [book] in the reader for its format, or says the app can't show it yet; done once the
/// reader closes.
Future<void> openBook(
  BuildContext context,
  SessionController session,
  Book book,
) async {
  final Widget reader;
  switch (book.format) {
    case BookFormat.cbz || BookFormat.imageComic:
      reader = PageReader(session: session, book: book);
    case BookFormat.pdf:
      reader = PdfReader(session: session, book: book);
    case BookFormat.epub:
      reader = EpubReader(session: session, book: book);
    case BookFormat.unsupported:
      ScaffoldMessenger.of(context)
        ..hideCurrentSnackBar()
        ..showSnackBar(
          SnackBar(content: Text(context.t('reader.unsupported'))),
        );
      return;
  }
  await Navigator.of(context)
      .push(MaterialPageRoute<void>(builder: (_) => reader));
}
