import 'package:flutter/foundation.dart';
import 'dart:io' as io;

class AppPlatform {
  static bool get isWeb => kIsWeb;
  static bool get isWindows => !kIsWeb && io.Platform.isWindows;
  static bool get isMacOS => !kIsWeb && io.Platform.isMacOS;
  static bool get isLinux => !kIsWeb && io.Platform.isLinux;
  static bool get isAndroid => !kIsWeb && io.Platform.isAndroid;
  static bool get isIOS => !kIsWeb && io.Platform.isIOS;
  static String get localHostname => !kIsWeb ? io.Platform.localHostname : 'Web Client';
}
