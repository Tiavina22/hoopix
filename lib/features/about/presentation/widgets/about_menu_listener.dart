import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:hoopix/features/about/presentation/widgets/about_dialog.dart';

/// The channel the native "About hoopix" app-menu item calls. macOS wires
/// that item to the First Responder's `showAboutPanel:`, which
/// `MainFlutterWindow.swift` answers by invoking `show` on this channel.
const aboutMenuChannelName = 'fit.hoopix/about';

/// Opens [HoopixAboutDialog] when the native app menu asks for it.
///
/// Sits *above* the `MaterialApp` (the menu event has no widget context of
/// its own), so the dialog is shown through [navigatorKey] — the same key
/// the app passes to `MaterialApp.navigatorKey` — rather than through this
/// widget's own [BuildContext], which has no Navigator ancestor.
class AboutMenuListener extends StatefulWidget {
  const AboutMenuListener({
    super.key,
    required this.navigatorKey,
    required this.child,
    this.dialogBuilder,
  });

  final GlobalKey<NavigatorState> navigatorKey;
  final Widget child;

  /// What to show. Defaults to the real dialog; a test substitutes one whose
  /// version lookup and link opener are stubbed.
  final WidgetBuilder? dialogBuilder;

  @override
  State<AboutMenuListener> createState() => _AboutMenuListenerState();
}

class _AboutMenuListenerState extends State<AboutMenuListener> {
  static const _channel = MethodChannel(aboutMenuChannelName);

  @override
  void initState() {
    super.initState();
    _channel.setMethodCallHandler(_onCall);
  }

  @override
  void dispose() {
    _channel.setMethodCallHandler(null);
    super.dispose();
  }

  Future<Object?> _onCall(MethodCall call) async {
    if (call.method != 'show') throw MissingPluginException();

    final context = widget.navigatorKey.currentContext;
    // The menu can fire before the first frame has built the Navigator; there
    // is nothing to show it in yet, and dropping the click beats crashing.
    if (context == null) return null;

    // Not awaited: the dialog stays open until the user closes it, and the
    // native caller must not be left waiting on a reply for that long.
    unawaited(
      showDialog<void>(
        context: context,
        builder: widget.dialogBuilder ?? (_) => const HoopixAboutDialog(),
      ),
    );
    return null;
  }

  @override
  Widget build(BuildContext context) => widget.child;
}
