import 'dart:async';

import 'package:pdfrx/pdfrx.dart';

/// One open pdfrx was asked for, and the answer a test gives it.
typedef PdfOpen = ({
  Uri uri,
  bool rangeAccess,
  bool progressive,
  Duration? timeout,
  Completer<PdfDocument> answer,
});

/// Stands in for pdfrx's PDFium engine, which `flutter test` lacks: it notes every open and
/// leaves it waiting until the test answers it.
class FakePdfEngine implements PdfrxEntryFunctions {
  final opens = <PdfOpen>[];

  @override
  Future<void> init() async {}

  @override
  Future<PdfDocument> openUri(
    Uri uri, {
    PdfPasswordProvider? passwordProvider,
    bool firstAttemptByEmptyPassword = true,
    bool useProgressiveLoading = false,
    PdfDownloadProgressCallback? progressCallback,
    bool preferRangeAccess = false,
    Map<String, String>? headers,
    bool withCredentials = false,
    Duration? timeout,
  }) {
    final answer = Completer<PdfDocument>();
    opens.add((
      uri: uri,
      rangeAccess: preferRangeAccess,
      progressive: useProgressiveLoading,
      timeout: timeout,
      answer: answer,
    ));
    return answer.future;
  }

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}
