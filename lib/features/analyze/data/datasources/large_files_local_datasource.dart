import 'package:hoopix/core/platform/disk_usage.dart';
import 'package:hoopix/core/process/process_runner.dart';
import 'package:hoopix/features/analyze/data/datasources/directory_local_datasource.dart';
import 'package:hoopix/features/analyze/domain/entities/analyze_entry.dart';

/// Only files this big are worth listing; below it the view is noise.
const _minFileSize = 100 * 1024 * 1024;

/// How many to keep, largest first.
const _maxLargeFiles = 20;

/// Source-code and text extensions, skipped even when large: a huge `.json`
/// or `.sql` is usually data someone is working on, not reclaimable space.
/// Same list as Mole's analyzer.
const _skipExtensions = {
  '.go', '.js', '.ts', '.tsx', '.jsx', '.json', '.md', '.txt', '.yml',
  '.yaml', '.xml', '.html', '.css', '.scss', '.sass', '.less', '.py',
  '.rb', '.java', '.kt', '.rs', '.swift', '.m', '.mm', '.c', '.cpp',
  '.h', '.hpp', '.cs', '.sql', '.db', '.lock', '.gradle', '.mjs', '.cjs',
  '.coffee', '.dart', '.svelte', '.vue', '.nim', '.hx',
};

/// Directories whose contents are build output, dependencies or caches.
/// A large file inside one of these is an artifact of the tree, not
/// something to act on file by file.
const _foldedDirectories = {
  '.git', '.svn', '.hg',
  'node_modules', '.npm', '_npx', '_cacache', '.yarn', '.pnpm-store',
  '.next', '.nuxt', 'bower_components', '.vite', '.turbo', '.parcel-cache',
  '.nx', '.bun', '.deno',
  '__pycache__', '.pytest_cache', '.mypy_cache', '.ruff_cache', 'venv',
  '.venv', 'virtualenv', '.tox', 'site-packages', '.eggs', '.pyenv',
  '.poetry', '.pip', '.pipx',
  'vendor', '.bundle', 'gems', '.rbenv', 'target', '.gradle', '.m2',
  '.ivy2', 'out', 'pkg', '.composer', '.cargo',
  'build', 'dist', '.output', 'coverage', '.coverage',
  '.idea', '.vscode', '.vs', '.fleet',
  '.cache', '__MACOSX', '.Trash', 'Caches', '.Spotlight-V100', '.fseventsd',
  '.DocumentRevisions-V100', '.TemporaryItems', '.temp', '.tmp', '_temp',
  '_tmp', '.Homebrew', '.rustup', '.sdkman', '.nvm',
  'Application Scripts', 'Saved Application State', 'Mobile Documents',
  '.docker', '.containerd',
  'Pods', 'DerivedData', '.build', 'xcuserdata', 'Carthage', '.dart_tool',
  '.angular', '.svelte-kit', '.astro', '.solid',
  '.terraform', '.vagrant', 'tmp', 'temp',
};

/// Finds the biggest files under a root by asking Spotlight, which already
/// has the index — walking the tree to answer the same question would take
/// orders of magnitude longer. Same approach as Mole's analyzer.
class LargeFilesLocalDataSource {
  const LargeFilesLocalDataSource(
    this._processRunner, {
    DiskUsage diskUsage = const DiskUsage(),
  }) : _diskUsage = diskUsage;

  final ProcessRunner _processRunner;
  final DiskUsage _diskUsage;

  Future<List<AnalyzeEntry>> find(String root) async {
    final result = await _processRunner.run('mdfind', [
      '-onlyin',
      root,
      'kMDItemFSSize >= $_minFileSize',
    ]);

    final stdout = result.stdout;
    if (stdout == null) return const [];

    final candidates = [
      for (final line in stdout.split('\n'))
        if (line.trim().isNotEmpty &&
            !_isSkippedExtension(line.trim()) &&
            !_isInFoldedDirectory(line.trim()))
          line.trim(),
    ];

    // Sized by what they occupy on disk, not their nominal length, so a
    // sparse or cloud-placeholder hit is not listed at a size it does not
    // hold. A null means the index is ahead of the filesystem, or the hit is
    // not a plain file — either way it is dropped.
    final sizes = await _diskUsage.actualSizes(candidates);

    final files = <AnalyzeEntry>[];
    for (final (index, path) in candidates.indexed) {
      final size = sizes[index];
      if (size == null) continue;
      files.add(
        AnalyzeEntry(
          path: path,
          name: basename(path),
          isDirectory: false,
          sizeBytes: size,
        ),
      );
    }

    files.sort((a, b) => (b.sizeBytes ?? 0).compareTo(a.sizeBytes ?? 0));
    return files.take(_maxLargeFiles).toList();
  }

  bool _isSkippedExtension(String path) {
    final name = basename(path);
    final dot = name.lastIndexOf('.');
    if (dot <= 0) return false;
    return _skipExtensions.contains(name.substring(dot).toLowerCase());
  }

  bool _isInFoldedDirectory(String path) =>
      path.split('/').any(_foldedDirectories.contains);
}
