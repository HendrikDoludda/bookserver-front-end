import 'dart:async';
import 'dart:ui' as ui;

import 'package:bookserver/data/session_controller.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/painting.dart';

/// An image from the server, such as a cover or a page, loaded through
/// [SessionController.authorized]: its request carries a live session token, renewed first when
/// it is about to run out.
@immutable
class ServerImage extends ImageProvider<ServerImageKey> {
  const ServerImage(this.session, this.path);

  final SessionController session;

  /// The image's path on the server, such as `/api/v1/covers/book/1`.
  final String path;

  @override
  Future<ServerImageKey> obtainKey(ImageConfiguration configuration) {
    final server = switch (session.stage) {
      LoggedIn(:final server) => server,
      _ => null,
    };
    return SynchronousFuture(ServerImageKey(server, path));
  }

  @override
  ImageStreamCompleter loadImage(
    ServerImageKey key,
    ImageDecoderCallback decode,
  ) => MultiFrameImageStreamCompleter(
    codec: _load(key, decode),
    scale: 1,
    debugLabel: key.path,
  );

  Future<ui.Codec> _load(
    ServerImageKey key,
    ImageDecoderCallback decode,
  ) async {
    try {
      final bytes = await session.authorized(
        (api, sessionToken) => api.getBytes(key.path, bearer: sessionToken),
      );
      return await decode(await ui.ImmutableBuffer.fromUint8List(bytes));
    } catch (_) {
      // A microtask later, as NetworkImage does it: a load that fails at once does so before the
      // cache has stored it, and evicting earlier would find nothing.
      scheduleMicrotask(() => PaintingBinding.instance.imageCache.evict(key));
      rethrow;
    }
  }

  @override
  bool operator ==(Object other) =>
      other is ServerImage &&
      identical(other.session, session) &&
      other.path == path;

  @override
  int get hashCode => Object.hash(identityHashCode(session), path);
}

/// What the image cache keeps a [ServerImage] under: the server as well as the path, since
/// `/api/v1/covers/book/1` on another server is another book.
@immutable
class ServerImageKey {
  const ServerImageKey(this.server, this.path);

  final Uri? server;
  final String path;

  @override
  bool operator ==(Object other) =>
      other is ServerImageKey && other.server == server && other.path == path;

  @override
  int get hashCode => Object.hash(server, path);
}
