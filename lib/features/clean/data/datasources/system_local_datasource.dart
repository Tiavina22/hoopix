import 'dart:ffi';
import 'dart:io';

import 'package:hoopix/features/clean/domain/usecases/build_clean_plan.dart';

/// Ports the verified-safe, exact-path slice of Mole's `clean_deep_system`
/// (`lib/clean/system.sh`) hoopix can reach today: a small, fixed list of
/// well-known root-owned system caches Apple regenerates on its own.
///
/// Every path here doubles as an entry in
/// `PrivilegedDeleteChannel.swift`'s own allowlist — the two lists are
/// grown together, one verified entry at a time, the same way Mole reviews
/// each `safe_sudo_remove` / `safe_sudo_find_delete` call under its own
/// scrutiny. This mirrors [CleanCandidate.requiresPrivilegedDeletion]'s
/// bypass of the ordinary `~/Library`-relative protection funnel: the
/// native side's exact-match list is the safety boundary for these paths,
/// not a heuristic.
///
/// `clean_apple_silicon_caches` (`lib/clean/user.sh`) lists three targets
/// on Apple Silicon; only the first is reachable here. The other two,
/// `~/Library/Caches/com.apple.rosetta.update` and
/// `~/Library/Caches/com.apple.amp.mediasevicesd`, both trip
/// `shouldProtectPath`'s blanket `com.apple.*` rule the same way in
/// hoopix as `should_protect_path` does in Mole — `safe_clean` refuses
/// them there too, so they carry zero reachable value in either tool, and
/// are left out rather than proposed only to always show as protected.
///
/// Not ported: the rest of `clean_deep_system` — age-based
/// `/Library/Caches` and `/Library/Logs` sweeps, crash reports, browser
/// code-signature clone caches, GPU shader caches under
/// `/private/var/folders`, and more — is a large, individually reasoned
/// body of work of its own; every one of those needs a generic age- or
/// pattern-based bulk-delete primitive this channel does not have yet,
/// unlike the exact single-path/single-bundle targets it already reaches
/// (these, and `MacosInstallerLocalDataSource`). `clean_local_snapshots` is
/// report-only in Mole itself (it never deletes, only prints a
/// `tmutil listlocalsnapshots` review count) and stays out of Clean's
/// candidate/Trash model for that reason, not for lack of privilege.
class SystemLocalDataSource {
  const SystemLocalDataSource();

  static const system = 'System';

  static const _iconServicesStore =
      '/Library/Caches/com.apple.iconservices.store';

  static const _rosettaUpdateBundle =
      '/Library/Apple/usr/share/rosetta/rosetta_update_bundle';

  CleanSectionTargets enumerate() {
    final targets = [_iconServicesStore];
    // Apple Silicon only: on Intel this bundle is never installed.
    if (Abi.current() == Abi.macosArm64 &&
        FileSystemEntity.typeSync(_rosettaUpdateBundle, followLinks: false) !=
            FileSystemEntityType.notFound) {
      targets.add(_rosettaUpdateBundle);
    }

    return CleanSectionTargets(
      system,
      targets,
      privilegedDeletionPaths: targets.toSet(),
    );
  }
}
