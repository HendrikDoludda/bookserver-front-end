import 'dart:async';
import 'dart:convert';

import 'package:flutter/painting.dart';

/// A valid 1×1 PNG.
final onePixelPng = base64Decode(
  'iVBORw0KGgoAAAANSUhEUgAAAAEAAAABCAYAAAAfFcSJAAAADUlEQVR42mNkYPhfDwAChwGA60e6kgAAAABJRU5ErkJggg==',
);

/// Resolves [image] and answers it once it has loaded, or its error once it has failed.
Future<ImageInfo> loaded(ImageProvider image) {
  final result = Completer<ImageInfo>();
  final stream = image.resolve(ImageConfiguration.empty);
  late final ImageStreamListener listener;
  listener = ImageStreamListener(
    (info, _) {
      stream.removeListener(listener);
      if (!result.isCompleted) {
        result.complete(info);
      }
    },
    onError: (error, stackTrace) {
      stream.removeListener(listener);
      if (!result.isCompleted) {
        result.completeError(error, stackTrace);
      }
    },
  );
  stream.addListener(listener);
  return result.future;
}
