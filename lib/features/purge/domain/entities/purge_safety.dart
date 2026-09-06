import 'dart:io';

import 'package:hoopix/features/purge/domain/entities/purge_constants.dart';

/// Whether [dir] is itself a recognized project root — any
/// [monorepoIndicators] or [projectIndicators] file present directly in
/// it. Ports `mole_purge_is_project_root` (`lib/clean/purge_shared.sh`).
bool isPurgeProjectRoot(String dir) {
  for (final indicator in monorepoIndicators) {
    if (_exists('$dir/$indicator')) return true;
  }
  for (final indicator in projectIndicators) {
    if (_exists('$dir/$indicator')) return true;
  }
  return false;
}

/// Ports `is_safe_project_artifact_under_root` (`lib/clean/project.sh`):
/// [path] must be lexically under [searchRoot], and either at depth ≥1
/// below it, or — for a direct child (depth 0) — only when [searchRoot]
/// is itself a recognized project root (single-project mode, where the
/// configured root *is* the project and its own top-level artifacts are
/// in scope).
bool isSafeProjectArtifactUnderRoot(String path, String searchRoot) {
  final trimmedPath = _withoutTrailingSlash(path);
  final trimmedRoot = _withoutTrailingSlash(searchRoot);

  if (!trimmedPath.startsWith('/') ||
      !trimmedRoot.startsWith('/') ||
      trimmedRoot == '/') {
    return false;
  }
  if (!trimmedPath.startsWith('$trimmedRoot/')) return false;

  final relative = trimmedPath.substring(trimmedRoot.length + 1);
  final depth = '/'.allMatches(relative).length;
  if (depth < 1) return isPurgeProjectRoot(trimmedRoot);
  return true;
}

/// Ports `is_safe_project_artifact`: containment is checked lexically
/// first, then — when both sides exist as directories — re-checked
/// against their physical (symlink-resolved) paths, so a symlinked
/// ancestor can never lend a configured root authority over an unrelated
/// tree, and OS aliases (`/var` → `/private/var`) still match correctly.
///
/// [resolvePhysicalPath] is injected so tests can simulate symlink
/// resolution without real filesystem symlinks; production resolves via
/// `Directory(path).resolveSymbolicLinksSync()`.
bool isSafeProjectArtifact(
  String path,
  String searchRoot, {
  String? Function(String path)? resolvePhysicalPath,
}) {
  if (!path.startsWith('/')) return false;

  final trimmedRoot = searchRoot == '/'
      ? searchRoot
      : _withoutTrailingSlash(searchRoot);

  final lexicallyContained = path.startsWith('$trimmedRoot/');

  final bothExistAsDirs =
      _isDirectory(path) && _isDirectory(trimmedRoot);
  if (bothExistAsDirs) {
    final resolve = resolvePhysicalPath ?? _resolvePhysicalPath;
    final physicalPath = resolve(path);
    final physicalRoot = resolve(trimmedRoot);
    if (physicalPath == null ||
        physicalRoot == null ||
        !physicalPath.startsWith('$physicalRoot/')) {
      return false;
    }
    return isSafeProjectArtifactUnderRoot(physicalPath, physicalRoot);
  }

  if (!lexicallyContained) return false;
  return isSafeProjectArtifactUnderRoot(path, trimmedRoot);
}

bool _exists(String path) =>
    FileSystemEntity.typeSync(path, followLinks: false) !=
    FileSystemEntityType.notFound;

bool _isDirectory(String path) =>
    FileSystemEntity.typeSync(path, followLinks: true) ==
    FileSystemEntityType.directory;

String _withoutTrailingSlash(String path) =>
    path.endsWith('/') && path.length > 1
    ? path.substring(0, path.length - 1)
    : path;

String? _resolvePhysicalPath(String path) {
  try {
    return Directory(path).resolveSymbolicLinksSync();
  } on FileSystemException {
    return null;
  }
}
