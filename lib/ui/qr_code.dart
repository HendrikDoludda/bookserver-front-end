import 'package:bookserver/ui/theme.dart';
import 'package:material_ui/material_ui.dart';
import 'package:qr/qr.dart';

/// The modules of [data]'s QR code, row by row: `true` for a dark one.
List<List<bool>> qrModules(String data) {
  final image = QrImage(
    QrCode(
      payload: QrPayload.fromString(data),
      errorCorrectLevel: QrErrorCorrectLevel.medium,
    ),
  );
  return [
    for (var row = 0; row < image.moduleCount; row++)
      [
        for (var column = 0; column < image.moduleCount; column++)
          image.isDark(row, column),
      ],
  ];
}

/// [data] as a QR code: a square no wider than [Widths.qrCode], with the quiet zone around it
/// that scanners need.
class QrCodeView extends StatelessWidget {
  QrCodeView({super.key, required String data}) : _modules = qrModules(data);

  final List<List<bool>> _modules;

  @override
  Widget build(BuildContext context) {
    return Center(
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: Widths.qrCode),
        child: AspectRatio(
          aspectRatio: 1,
          child: CustomPaint(painter: _QrPainter(_modules)),
        ),
      ),
    );
  }
}

class _QrPainter extends CustomPainter {
  _QrPainter(this.modules);

  final List<List<bool>> modules;

  // The quiet zone the QR standard asks for, in modules.
  static const _quietZone = 4;

  @override
  void paint(Canvas canvas, Size size) {
    final cells = modules.length + 2 * _quietZone;
    final cell = size.width / cells;
    // Black on white in both themes: scanners look for dark squares on a light ground, and many
    // can't read the colours turned around.
    canvas.drawRect(
      Offset.zero & size,
      Paint()..color = const Color(0xFFFFFFFF),
    );
    // Without anti-aliasing, neighbouring squares meet without the faint seams a scanner could
    // read as light modules.
    final dark = Paint()
      ..color = const Color(0xFF000000)
      ..isAntiAlias = false;
    for (var row = 0; row < modules.length; row++) {
      for (var column = 0; column < modules.length; column++) {
        if (modules[row][column]) {
          canvas.drawRect(
            Rect.fromLTWH(
              (column + _quietZone) * cell,
              (row + _quietZone) * cell,
              cell,
              cell,
            ),
            dark,
          );
        }
      }
    }
  }

  @override
  bool shouldRepaint(_QrPainter oldDelegate) => oldDelegate.modules != modules;
}
