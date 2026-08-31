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
  });

  final String path;

  /// The section that proposed it, so the preview can group by where the
  /// space is going.
  final String section;

  /// Null while unmeasured, or when the size could not be read.
  final int? sizeBytes;

  /// Null when the path is eligible for removal.
  final CleanSkipReason? skipReason;

  bool get isEligible => skipReason == null;

  CleanCandidate withSize(int? sizeBytes) => CleanCandidate(
    path: path,
    section: section,
    sizeBytes: sizeBytes,
    skipReason: skipReason,
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

  List<CleanCandidate> get eligible =>
      [for (final c in candidates) if (c.isEligible) c];

  List<CleanCandidate> get skipped =>
      [for (final c in candidates) if (!c.isEligible) c];

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
}
