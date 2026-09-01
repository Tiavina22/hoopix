import 'package:flutter_test/flutter_test.dart';
import 'package:hoopix/features/clean/domain/entities/clean_plan.dart';
import 'package:hoopix/features/clean/domain/entities/clean_whitelist.dart';
import 'package:hoopix/features/clean/domain/usecases/build_clean_plan.dart';

const _home = '/Users/tester';

BuildCleanPlan builder({
  List<String>? whitelistLines,
  Set<String> missing = const {},
  Set<String> modelCaches = const {},
}) => BuildCleanPlan(
  home: _home,
  whitelist: CleanWhitelist.from(home: _home, userLines: whitelistLines ?? []),
  exists: (path) => !missing.contains(path),
  holdsModelCache: modelCaches.contains,
);

CleanCandidate candidateFor(CleanPlan plan, String path) =>
    plan.candidates.firstWhere((c) => c.path == path);

void main() {
  test('an ordinary cache is eligible', () {
    final plan = builder()([
      CleanSectionTargets('App caches', [
        '$_home/Library/Caches/com.example.app',
      ]),
    ]);

    expect(plan.eligible.map((c) => c.path), [
      '$_home/Library/Caches/com.example.app',
    ]);
    expect(plan.skipped, isEmpty);
  });

  test('a protected path is kept, and says why', () {
    final plan = builder()([
      CleanSectionTargets('App caches', [
        '$_home/Library/Caches/com.example.app',
        '$_home/Library/Keychains/login.keychain-db',
      ]),
    ]);

    expect(plan.eligible.map((c) => c.path), [
      '$_home/Library/Caches/com.example.app',
    ]);
    expect(
      candidateFor(
        plan,
        '$_home/Library/Keychains/login.keychain-db',
      ).skipReason,
      CleanSkipReason.protected,
    );
  });

  test('a whitelisted path is kept, and says why', () {
    final plan = builder(whitelistLines: ['$_home/Library/Caches/keep-me'])([
      CleanSectionTargets('App caches', ['$_home/Library/Caches/keep-me']),
    ]);

    expect(plan.eligible, isEmpty);
    expect(
      candidateFor(plan, '$_home/Library/Caches/keep-me').skipReason,
      CleanSkipReason.whitelisted,
    );
  });

  test('a compiled model cache is kept, and says why', () {
    const path = '$_home/Library/Caches/com.example.vision';
    final plan = builder(modelCaches: {path})([
      CleanSectionTargets('App caches', [path]),
    ]);

    expect(
      candidateFor(plan, path).skipReason,
      CleanSkipReason.compiledModelCache,
    );
  });

  test('a missing target is not in the plan at all', () {
    const gone = '$_home/Library/Caches/gone';
    final plan = builder(missing: {gone})([
      CleanSectionTargets('App caches', [gone]),
    ]);

    // Not skipped-with-a-reason: it was never the run's business.
    expect(plan.candidates, isEmpty);
  });

  test('a child listed beside its parent collapses into the parent', () {
    final plan = builder()([
      CleanSectionTargets('App caches', [
        '$_home/Library/Caches/app',
        '$_home/Library/Caches/app/blobs',
      ]),
    ]);

    expect(plan.eligible.map((c) => c.path), ['$_home/Library/Caches/app']);
  });

  test('a path proposed by two sections is planned once', () {
    const shared = '$_home/Library/Caches/shared';
    final plan = builder()([
      CleanSectionTargets('App caches', [shared]),
      CleanSectionTargets('Developer tools', [shared]),
    ]);

    expect(plan.candidates, hasLength(1));
    expect(plan.candidates.single.section, 'App caches');
  });

  test('an owner-command target carries its command onto the candidate', () {
    const path = '$_home/.npm';
    final plan = builder()([
      CleanSectionTargets(
        'Developer tools',
        [path],
        ownerCommands: {
          path: ['npm', 'cache', 'clean', '--force'],
        },
      ),
    ]);

    final candidate = candidateFor(plan, path);
    expect(candidate.isOwnerCommand, isTrue);
    expect(candidate.ownerCommand, ['npm', 'cache', 'clean', '--force']);
  });

  test('a target without an owner command is an ordinary Trash removal', () {
    const path = '$_home/Library/Caches/plain';
    final plan = builder()([
      CleanSectionTargets('Developer tools', [path]),
    ]);

    expect(candidateFor(plan, path).isOwnerCommand, isFalse);
  });

  test(
    'an owner-command target that is protected is still kept, and still tagged',
    () {
      const path = '$_home/Library/Keychains/login.keychain-db';
      final plan = builder()([
        CleanSectionTargets(
          'Developer tools',
          [path],
          ownerCommands: {
            path: ['some-tool', 'clean'],
          },
        ),
      ]);

      final candidate = candidateFor(plan, path);
      expect(candidate.skipReason, CleanSkipReason.protected);
      expect(candidate.isOwnerCommand, isTrue);
    },
  );

  test(
    'a privileged-deletion target bypasses the user-space protection funnel',
    () {
      // Filename-shaped like a blanket-protected com.apple.* bundle id, the
      // way the one real System target actually is — the ordinary funnel
      // would otherwise keep Apple's own well-known system caches by name.
      const path = '/Library/Caches/com.apple.iconservices.store';
      final plan = builder()([
        CleanSectionTargets('System', [path], privilegedDeletionPaths: {path}),
      ]);

      final candidate = candidateFor(plan, path);
      expect(candidate.isEligible, isTrue);
      expect(candidate.requiresPrivilegedDeletion, isTrue);
      expect(candidate.isRecoverable, isFalse);
    },
  );

  test('a privileged-deletion target still honors the user\'s whitelist', () {
    const path = '/Library/Caches/com.apple.iconservices.store';
    final plan = builder(whitelistLines: [path])([
      CleanSectionTargets('System', [path], privilegedDeletionPaths: {path}),
    ]);

    final candidate = candidateFor(plan, path);
    expect(candidate.skipReason, CleanSkipReason.whitelisted);
    expect(candidate.requiresPrivilegedDeletion, isTrue);
  });

  test(
    'a target without privileged deletion goes through the funnel as usual',
    () {
      const path = '$_home/Library/Keychains/login.keychain-db';
      final plan = builder()([
        CleanSectionTargets('System', [path]),
      ]);

      final candidate = candidateFor(plan, path);
      expect(candidate.skipReason, CleanSkipReason.protected);
      expect(candidate.requiresPrivilegedDeletion, isFalse);
    },
  );

  test(
    'protection is checked before the whitelist, so the reason is honest',
    () {
      // Whitelisting something already protected must not relabel why it is
      // being kept.
      const path = '$_home/Library/Keychains/login.keychain-db';
      final plan = builder(whitelistLines: [path])([
        CleanSectionTargets('App caches', [path]),
      ]);

      expect(candidateFor(plan, path).skipReason, CleanSkipReason.protected);
    },
  );

  group('the plan itself', () {
    test('totals only what it would actually remove', () {
      const plan = CleanPlan(
        candidates: [
          CleanCandidate(path: '/a', section: 'S', sizeBytes: 100),
          CleanCandidate(path: '/b', section: 'S', sizeBytes: 50),
          CleanCandidate(
            path: '/c',
            section: 'S',
            sizeBytes: 900,
            skipReason: CleanSkipReason.protected,
          ),
          // Unmeasured contributes nothing rather than a guess.
          CleanCandidate(path: '/d', section: 'S'),
        ],
      );

      expect(plan.reclaimableBytes, 150);
      expect(plan.eligible, hasLength(3));
      expect(plan.skippedFor(CleanSkipReason.protected), 1);
    });

    test('counts eligible owner-command candidates, not skipped ones', () {
      const plan = CleanPlan(
        candidates: [
          CleanCandidate(path: '/a', section: 'S'),
          CleanCandidate(
            path: '/b',
            section: 'S',
            ownerCommand: ['tool', 'clean'],
          ),
          CleanCandidate(
            path: '/c',
            section: 'S',
            ownerCommand: ['tool', 'clean'],
            skipReason: CleanSkipReason.protected,
          ),
        ],
      );

      expect(plan.ownerCommandCount, 1);
    });

    test(
      'irreversibleCount counts owner-command and privileged-deletion candidates alike',
      () {
        const plan = CleanPlan(
          candidates: [
            CleanCandidate(path: '/a', section: 'S'),
            CleanCandidate(
              path: '/b',
              section: 'S',
              ownerCommand: ['tool', 'clean'],
            ),
            CleanCandidate(
              path: '/c',
              section: 'S',
              requiresPrivilegedDeletion: true,
            ),
            CleanCandidate(
              path: '/d',
              section: 'S',
              requiresPrivilegedDeletion: true,
              skipReason: CleanSkipReason.whitelisted,
            ),
          ],
        );

        expect(plan.irreversibleCount, 2);
      },
    );

    test('groups by section in the order the run would work', () {
      const plan = CleanPlan(
        candidates: [
          CleanCandidate(path: '/a', section: 'App caches'),
          CleanCandidate(path: '/b', section: 'Developer tools'),
          CleanCandidate(path: '/c', section: 'App caches'),
        ],
      );

      expect(plan.bySection.keys, ['App caches', 'Developer tools']);
      expect(plan.bySection['App caches'], hasLength(2));
    });
  });
}
