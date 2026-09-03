/// Why a target the section proposed will not be removed. Kept and shown
/// rather than dropped: "hoopix skipped 12 things and won't say which" is
/// how a cleanup tool loses trust.
enum CleanSkipReason {
  /// [shouldProtectPath] refused it.
  protected,

  /// The user's whitelist covers it.
  whitelisted,

  /// Holds a compiled model cache a running app will not rebuild.
  compiledModelCache,
}

/// Exact process names and/or full-command-line patterns a candidate's
/// removal must reconfirm are still not running immediately before it
/// happens — the same shape [ProcessGuard.check] takes, kept here free of
/// any process/platform dependency so this stays a plain domain value.
class ProcessRecheck {
  const ProcessRecheck({this.exactNames = const [], this.patterns = const []});

  final List<String> exactNames;
  final List<String> patterns;
}

/// One path a section proposed, with what became of it.
class CleanCandidate {
  const CleanCandidate({
    required this.path,
    required this.section,
    this.sizeBytes,
    this.skipReason,
    this.ownerCommand,
    this.requiresPrivilegedDeletion = false,
    this.recheckProcessGuard,
    this.revalidatorKey,
  });

  final String path;

  /// The section that proposed it, so the preview can group by where the
  /// space is going.
  final String section;

  /// Null while unmeasured, or when the size could not be read. For an
  /// owner-command candidate this is an estimate — how much [path] holds
  /// today — not a guarantee of what the command frees.
  final int? sizeBytes;

  /// Null when the path is eligible for removal.
  final CleanSkipReason? skipReason;

  /// When set, approving this candidate runs this command instead of moving
  /// [path] to Trash — some tools (npm, Go, ...) only reclaim their cache
  /// correctly through their own cache-clean command, not a raw directory
  /// move. [path] is still what protection, whitelist and sizing run
  /// against: the root the command reclaims. Not recoverable the way a
  /// Trash move is.
  final List<String>? ownerCommand;

  /// When true, approving this candidate deletes [path] through the
  /// administrator-privileges channel instead of a Trash move — the narrow
  /// set of root-owned system caches Mole itself only ever reaches through
  /// `sudo` (`clean_deep_system`, `lib/clean/system.sh`). Not recoverable
  /// the way a Trash move is, and mutually exclusive with [ownerCommand]:
  /// a candidate needs at most one non-default removal mechanism.
  final bool requiresPrivilegedDeletion;

  /// When set, this candidate's removal — Trash move or owner command
  /// alike — must reconfirm none of these processes are running
  /// immediately before it happens. The scan-time check that made the
  /// candidate eligible in the first place leaves a window before
  /// approval — sizing every candidate, then waiting on the user — where
  /// the owning app could have been launched. Mirrors Mole's own second
  /// process check right before its own deletion call, used for exactly
  /// the same handful of higher-risk targets (Chrome/Firefox profile
  /// caches, Dropbox/Google Drive/OneDrive, Xcode's cache/build
  /// products/DerivedData, Tart's prune). Null when the candidate's
  /// mechanism has no such race in Mole either.
  final ProcessRecheck? recheckProcessGuard;

  /// When set, names the datasource that must reconfirm this candidate's
  /// full eligibility immediately before it is removed — everything beyond
  /// process liveness that only the datasource which found it can re-check:
  /// a file's own identity, Software Update's pending state, whether an
  /// updater has switched which version is current. The repository resolves
  /// the key to that datasource's own revalidation, so this stays a plain
  /// domain value rather than a callback embedded in an entity.
  ///
  /// Mole runs the equivalent guard immediately before each of its own
  /// removals (`macos_installer_candidate_still_eligible`,
  /// `_autodesk_fusion_delete_guard_allows`). Null for a candidate whose
  /// eligibility cannot drift between scan and approval.
  final String? revalidatorKey;

  bool get isEligible => skipReason == null;
  bool get isOwnerCommand => ownerCommand != null;

  /// Whether approving this candidate can be undone from the Trash. False
  /// for both non-default mechanisms — the confirmation copy must not
  /// promise recoverability it cannot deliver.
  bool get isRecoverable => !isOwnerCommand && !requiresPrivilegedDeletion;

  CleanCandidate withSize(int? sizeBytes) => CleanCandidate(
    path: path,
    section: section,
    sizeBytes: sizeBytes,
    skipReason: skipReason,
    ownerCommand: ownerCommand,
    requiresPrivilegedDeletion: requiresPrivilegedDeletion,
    recheckProcessGuard: recheckProcessGuard,
    revalidatorKey: revalidatorKey,
  );
}

/// What a clean run intends to do, before it does any of it.
///
/// The preview is not a courtesy here — it is the product. Mole is dry-run
/// capable for the same reason: the user should be able to see exactly what
/// will be removed, and how much that reclaims, before anything moves.
class CleanPlan {
  const CleanPlan({required this.candidates});

  final List<CleanCandidate> candidates;

  List<CleanCandidate> get eligible => [
    for (final c in candidates)
      if (c.isEligible) c,
  ];

  List<CleanCandidate> get skipped => [
    for (final c in candidates)
      if (!c.isEligible) c,
  ];

  /// What removing everything eligible would reclaim. Unmeasured paths
  /// contribute nothing rather than a guess.
  int get reclaimableBytes =>
      eligible.fold(0, (total, c) => total + (c.sizeBytes ?? 0));

  /// Eligible paths grouped by the section that proposed them, in first-seen
  /// order so the preview reads in the order the run would work.
  Map<String, List<CleanCandidate>> get bySection {
    final grouped = <String, List<CleanCandidate>>{};
    for (final candidate in eligible) {
      grouped.putIfAbsent(candidate.section, () => []).add(candidate);
    }
    return grouped;
  }

  int skippedFor(CleanSkipReason reason) =>
      skipped.where((c) => c.skipReason == reason).length;

  /// How many eligible candidates clear by running an owner command rather
  /// than moving to Trash — the confirmation copy must not promise every
  /// approved item can be put back when this is above zero.
  int get ownerCommandCount => eligible.where((c) => c.isOwnerCommand).length;

  /// How many eligible candidates cannot be put back from the Trash at
  /// all — an owner command or a privileged system delete. The
  /// confirmation copy switches to mechanism-neutral wording whenever this
  /// is above zero, regardless of which mechanism is responsible.
  int get irreversibleCount => eligible.where((c) => !c.isRecoverable).length;
}
