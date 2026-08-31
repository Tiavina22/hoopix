import 'dart:io';

import 'package:hoopix/features/clean/domain/entities/deno_cache_root.dart';
import 'package:hoopix/features/clean/domain/usecases/build_clean_plan.dart';

/// Enumerates what each section proposes to remove.
///
/// Enumeration only: nothing here judges safety or deletes. Every path it
/// returns still goes through the protection funnel, and the funnel's answer
/// is what the user sees.
///
/// Sections and their targets follow Mole's `lib/clean/*.sh`. They are added
/// one at a time rather than guessed at wholesale — each is a hand-curated
/// list, not a rule that can be inferred.
class CleanSectionsLocalDataSource {
  CleanSectionsLocalDataSource({
    required this.home,
    this.denoDir,
    Directory Function(String path)? directory,
  }) : _directory = directory ?? Directory.new;

  final String home;

  /// Read from the environment by the repository, so "DENO_DIR is set to
  /// something odd" is a state this can be handed in a test.
  final String? denoDir;

  final Directory Function(String path) _directory;

  /// Everything the run would consider, section by section, in the order
  /// Mole works through them.
  List<CleanSectionTargets> enumerate() => [
    CleanSectionTargets(userEssentials, _userEssentialsTargets()),
  ];

  static const userEssentials = 'User essentials';

  List<String> _userEssentialsTargets() {
    final targets = <String>[];

    final deno = denoCacheRoot(home: home, denoDir: denoDir);
    if (deno == null) {
      // Refusing is right, but sweeping past an unresolved owner root would
      // be worse: the whole cache batch stays empty rather than risk taking
      // Deno's runtime payloads with it.
      //
      // The other categories below are unaffected — they do not overlap it.
    } else {
      for (final child in _childrenOf('$home/Library/Caches')) {
        // The Deno root itself is review-only, not swept.
        if (child == deno || child.startsWith('$deno/')) continue;
        targets.add(child);
      }
    }

    targets.addAll(_childrenOf('$home/Library/Logs'));

    // Recent-items lists: what was opened, not what is needed to open it.
    const shared = 'Library/Application Support/com.apple.sharedfilelist';
    for (final kind in ['Applications', 'Documents', 'Servers', 'Hosts']) {
      for (final extension in ['sfl2', 'sfl']) {
        targets.add('$home/$shared/com.apple.LSSharedFileList.Recent$kind.$extension');
      }
    }
    targets.add('$home/Library/Preferences/com.apple.recentitems.plist');

    return targets;
  }

  /// Immediate children of [path], or nothing when it cannot be listed.
  /// Symlinks are listed but never followed, so a link cannot redirect the
  /// sweep somewhere it was not pointed.
  List<String> _childrenOf(String path) {
    try {
      return [
        for (final entity in _directory(path).listSync(followLinks: false))
          entity.path,
      ]..sort();
    } on FileSystemException {
      return const [];
    }
  }
}
