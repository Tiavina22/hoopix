import 'package:flutter/material.dart';

/// The area every feature screen renders into. It is a [Scaffold] so the
/// app's [ScaffoldMessenger] has somewhere to present a [SnackBar]: Clean,
/// Purge and Uninstall all report their result that way, and without a
/// Scaffold each of those reports was a failed assertion instead of a
/// message. Transparent, so the shell's own window background shows
/// through unchanged.
class ShellContentArea extends StatelessWidget {
  const ShellContentArea({super.key, required this.child});

  final Widget child;

  @override
  Widget build(BuildContext context) {
    return Scaffold(backgroundColor: Colors.transparent, body: child);
  }
}
