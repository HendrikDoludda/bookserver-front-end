import 'package:flutter/foundation.dart';

/// Whether the app runs on a phone or a tablet — iOS or Android — rather than on a desktop.
bool isPhoneOrTablet() => const {
  TargetPlatform.iOS,
  TargetPlatform.android,
}.contains(defaultTargetPlatform);
