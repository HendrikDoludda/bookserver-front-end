import 'package:bookserver/data/browse_api.dart';
import 'package:bookserver/data/session_controller.dart';
import 'package:bookserver/ui/cover.dart';
import 'package:flutter/painting.dart';

import 'images.dart';

/// The cache keys of [covers], once each has loaded into the image cache through [session] as a
/// [Cover] shows it. Loading decodes for real, so a widget test runs this in `runAsync`.
Future<List<Object>> cachedCovers(
  SessionController session,
  List<(CoverKind, int)> covers,
) async => [
  for (final (kind, id) in covers)
    await _cached(Cover.imageOf(session, kind, id)),
];

Future<Object> _cached(ImageProvider image) async {
  await loaded(image);
  return image.obtainKey(ImageConfiguration.empty);
}

/// Whether the image cache still holds an image under [key]: loading, kept or on show.
bool isCached(Object key) =>
    PaintingBinding.instance.imageCache.statusForKey(key).tracked;
