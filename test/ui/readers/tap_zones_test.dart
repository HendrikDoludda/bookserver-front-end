import 'package:bookserver/ui/readers/tap_zones.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('left to right, the left third goes back, the right third on', () {
    for (final (dx, zone) in [
      (0.0, TapZone.previous),
      (99.9, TapZone.previous),
      (100.0, TapZone.middle),
      (150.0, TapZone.middle),
      (200.0, TapZone.middle),
      (200.1, TapZone.next),
      (300.0, TapZone.next),
    ]) {
      expect(tapZoneAt(dx, 300), zone, reason: '$dx');
    }
  });

  test('right to left, the left third goes on, the right third back', () {
    for (final (dx, zone) in [
      (0.0, TapZone.next),
      (99.9, TapZone.next),
      (150.0, TapZone.middle),
      (200.1, TapZone.previous),
      (300.0, TapZone.previous),
    ]) {
      expect(tapZoneAt(dx, 300, rightToLeft: true), zone, reason: '$dx');
    }
  });
}
