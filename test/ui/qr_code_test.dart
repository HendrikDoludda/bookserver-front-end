import 'package:bookserver/ui/qr_code.dart';
import 'package:bookserver/ui/theme.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:material_ui/material_ui.dart';

void main() {
  const link =
      'otpauth://totp/Bookserver:alice?secret=JBSWY3DPEHPK3PXPJBSWY3DPEHPK3PXP&issuer=Bookserver';

  test('the modules are a square with the three finder patterns', () {
    final modules = qrModules(link);
    final size = modules.length;

    expect(size, greaterThanOrEqualTo(21), reason: 'version 1 is the smallest');
    expect((size - 17) % 4, 0, reason: 'every version adds 4 modules');
    for (final row in modules) {
      expect(row, hasLength(size));
    }
    // A finder pattern's outer ring is dark: its top row of 7, in three corners.
    for (final (row, column) in [(0, 0), (0, size - 7), (size - 7, 0)]) {
      expect(
        modules[row].sublist(column, column + 7),
        everyElement(isTrue),
        reason: 'the corner at $row, $column',
      );
    }
  });

  test('other data gives other modules', () {
    expect(qrModules(link), isNot(qrModules('$link-other')));
  });

  testWidgets('is a square no wider than its width token', (tester) async {
    await tester.pumpWidget(
      Directionality(
        textDirection: TextDirection.ltr,
        child: SizedBox(width: 600, child: QrCodeView(data: link)),
      ),
    );

    final size = tester.getSize(find.byType(CustomPaint).last);
    expect(size.width, Widths.qrCode);
    expect(size.height, size.width);
  });
}
