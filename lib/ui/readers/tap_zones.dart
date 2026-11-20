/// What a tap on a page does, by where it lands: the outer thirds turn the pages, the middle third
/// shows and hides the reader's bars.
enum TapZone { previous, middle, next }

/// The zone of a tap [dx] from the left edge of a page [width] wide. Right to left, the left edge
/// goes forward: the next page lies on that side.
TapZone tapZoneAt(double dx, double width, {bool rightToLeft = false}) {
  final third = width / 3;
  final (left, right) = rightToLeft
      ? (TapZone.next, TapZone.previous)
      : (TapZone.previous, TapZone.next);
  if (dx < third) {
    return left;
  }
  return dx > width - third ? right : TapZone.middle;
}
