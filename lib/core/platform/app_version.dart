import 'package:package_info_plus/package_info_plus.dart';

/// The version of the running app (`CFBundleShortVersionString`, which
/// Flutter fills from `pubspec.yaml`'s `version:`).
///
/// The one place the version is read, so the sidebar footer and the About
/// dialog can never disagree about it — and neither can drift from
/// `pubspec.yaml`, the way a hand-typed string would. `PackageInfo` keeps
/// the platform answer after the first call, so asking again is cheap.
Future<String> readAppVersion() async =>
    (await PackageInfo.fromPlatform()).version;
