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

/// One path a section proposed, with what became of it.
class CleanCandidate {
  const CleanCandidate({
    required this.path,
    required this.section,
    this.sizeBytes,
    this.skipReason,
    this.ownerCommand,
    this.requiresPrivilegedDeletion = false,
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
