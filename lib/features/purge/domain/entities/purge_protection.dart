import 'dart:io';

/// Ports the per-target special cases in `is_protected_purge_artifact`
/// (`lib/clean/project.sh`): three [purgeTargets] entries are matched like
/// any other target during scanning, but need a secondary check before
/// they are actually eligible, because unlike the rest of the list their
/// name alone does not prove what produced them.
///
/// Whether [path] — an already-matched `purgeTargets` candidate — must be
/// left alone rather than offered for cleanup.
bool isProtectedPurgeArtifact(String path) {
  final trimmed = _withoutTrailingSlash(path);
  final base = trimmed.split('/').last;

  switch (base) {
    case 'bin':
      // Only .NET's own build output under a project's bin/ is eligible;
      // every other bin/ (a language runtime, a vendored tool) stays.
      return !_isDotnetBinDir(trimmed);
    case 'vendor':
      return _isProtectedVendorDir(trimmed);
    case 'DerivedData':
      // Xcode's own global cache is the only DerivedData purge reaches; a
      // differently-located directory that happens to share the name is
      // left alone.
      return !trimmed.contains('/Library/Developer/Xcode/DerivedData');
    default:
      return false;
  }
}

bool _isDotnetBinDir(String path) {
  if (path.split('/').last != 'bin') return false;
  final parent = _parentOf(path);

  final hasProjectFile = _entries(
    parent,
  ).any((name) => _matchesAny(name, const ['.csproj', '.fsproj', '.vbproj']));
  if (!hasProjectFile) return false;

  return _isDirectory('$path/Debug') || _isDirectory('$path/Release');
}

/// Only PHP Composer's own `vendor/` is regenerable with a plain `composer
/// install`; every other ecosystem's `vendor/` either carries state Mole
/// cannot prove is rebuildable (Rails' importmap vendoring) or is
/// protected conservatively when the owner is unrecognized.
bool _isProtectedVendorDir(String path) {
  final parent = _parentOf(path);
  if (_isPhpProjectRoot(parent)) return false;
  if (_isRailsProjectRoot(parent)) return true;
  if (_isGoProjectRoot(parent)) return true;
  return true;
}

bool _isPhpProjectRoot(String dir) => _isFile('$dir/composer.json');

bool _isGoProjectRoot(String dir) => _isFile('$dir/go.mod');

bool _isRailsProjectRoot(String dir) {
  if (!_isFile('$dir/config/application.rb')) return false;
  if (!_isFile('$dir/Gemfile')) return false;
  return _isFile('$dir/bin/rails') || _isFile('$dir/config/environment.rb');
}

String _parentOf(String path) {
  final lastSlash = path.lastIndexOf('/');
  if (lastSlash <= 0) return '/';
  return path.substring(0, lastSlash);
}

String _withoutTrailingSlash(String path) =>
    path.endsWith('/') && path.length > 1
    ? path.substring(0, path.length - 1)
    : path;

bool _matchesAny(String name, List<String> suffixes) =>
    suffixes.any(name.endsWith);

List<String> _entries(String dir) {
  try {
    return [
      for (final entity in Directory(dir).listSync(followLinks: false))
        entity.path.split('/').last,
    ];
  } on FileSystemException {
    return const [];
  }
}

bool _isFile(String path) =>
    FileSystemEntity.typeSync(path, followLinks: false) ==
    FileSystemEntityType.file;

bool _isDirectory(String path) =>
    FileSystemEntity.typeSync(path, followLinks: false) ==
    FileSystemEntityType.directory;
