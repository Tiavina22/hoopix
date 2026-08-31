import 'package:flutter/material.dart';

/// The six capabilities Mole offers; hoopix mirrors the same shape. Only
/// [HoopixSection.status] has a real feature behind it today — the rest
/// route to a shared placeholder until each gets its own feature module.
///
/// Icons are picked as one coherent outlined set (the closest Material has to
/// SF Symbols) so the sidebar reads as a family rather than a grab bag.
enum HoopixSection {
  clean('Clean', 'Free up disk space', Icons.auto_awesome_outlined),
  uninstall('Uninstall', 'Remove apps completely', Icons.delete_outline),
  optimize('Optimize', 'Refresh caches and services', Icons.bolt_outlined),
  analyze('Analyze', 'Explore disk usage', Icons.pie_chart_outline),
  status('Status', 'Monitor system health', Icons.speed_outlined),
  purge('Purge', 'Clean project build artifacts', Icons.folder_delete_outlined);

  const HoopixSection(this.label, this.description, this.icon);

  final String label;
  final String description;
  final IconData icon;

  bool get isImplemented => this == HoopixSection.status;
}
