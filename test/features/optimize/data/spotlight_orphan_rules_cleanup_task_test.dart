import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:hoopix/core/process/bundle_install_resolver.dart';
import 'package:hoopix/core/process/process_failure.dart';
import 'package:hoopix/core/process/process_runner.dart';
import 'package:hoopix/features/optimize/data/datasources/spotlight_orphan_rules_cleanup_task.dart';
import 'package:hoopix/features/optimize/domain/entities/optimize_outcome.dart';

import '../../../support/fake_process_runner.dart';

const _home = '/Users/tester';
const _plist = '$_home/Library/Preferences/com.apple.spotlight.plist';

ProcessResult _fail() =>
    ProcessResult.failure(ProcessFailure.nonZeroExit('PlistBuddy', 1, ''));

Map<String, ProcessResult> _entries(List<String> values) => {
  for (var i = 0; i < values.length; i++)
    '/usr/libexec/PlistBuddy -c Print :EnabledPreferenceRules:$i $_plist':
        ProcessResult.success('${values[i]}\n'),
  '/usr/libexec/PlistBuddy -c Print :EnabledPreferenceRules:${values.length} '
          '$_plist':
      _fail(),
};

void main() {
  // No app root ever resolves to a real directory, so
  // BundleInstallResolver.hasInstalledApp falls through its mdfind miss and
  // its filesystem fallback (an empty listing) to a clean "not installed" —
  // deterministic, and never touches the real machine's own /Applications.
  BundleInstallResolver isolatedResolver(ProcessRunner probe) =>
      BundleInstallResolver(
        home: _home,
        probe: probe,
        directory: (_) => Directory('/nonexistent-hoopix-test-root'),
      );

  test('action id matches the catalog', () async {
    final result = await SpotlightOrphanRulesCleanupTask(
      home: _home,
      probe: FakeProcessRunner({
        'defaults read com.apple.spotlight EnabledPreferenceRules': _fail(),
      }),
    ).run();

    expect(result.task.action, 'spotlight_orphan_rules_cleanup');
  });

  test(
    'unchanged when there is no EnabledPreferenceRules key at all',
    () async {
      final result = await SpotlightOrphanRulesCleanupTask(
        home: _home,
        probe: FakeProcessRunner({
          'defaults read com.apple.spotlight EnabledPreferenceRules': _fail(),
        }),
      ).run();

      expect(result.outcome, OptimizeOutcome.unchanged);
    },
  );

  test('never touches System.* or com.apple.* rules', () async {
    final result = await SpotlightOrphanRulesCleanupTask(
      home: _home,
      probe: FakeProcessRunner({
        'defaults read com.apple.spotlight EnabledPreferenceRules':
            ProcessResult.success(''),
        ..._entries(['System.iphoneApps', 'com.apple.finder']),
      }),
    ).run();

    expect(result.outcome, OptimizeOutcome.unchanged);
  });

  test('keeps an entry that is not a well-formed bundle id', () async {
    final result = await SpotlightOrphanRulesCleanupTask(
      home: _home,
      probe: FakeProcessRunner({
        'defaults read com.apple.spotlight EnabledPreferenceRules':
            ProcessResult.success(''),
        ..._entries(['not-a-bundle-id']),
      }),
    ).run();

    expect(result.outcome, OptimizeOutcome.unchanged);
  });

  test('removes a bundle id the resolver confirms has no installed app, '
      'rewriting the array with only what is kept', () async {
    final probe = FakeProcessRunner({
      'defaults read com.apple.spotlight EnabledPreferenceRules':
          ProcessResult.success(''),
      ..._entries(['com.example.Kept', 'com.example.Gone']),
      // "Kept" resolves through the mdfind fast path (still installed);
      // "Gone" misses mdfind and the isolated resolver's filesystem
      // fallback finds nothing either, so it is confirmed orphaned.
      "mdfind kMDItemCFBundleIdentifier == 'com.example.Kept'":
          ProcessResult.success('/Applications/Kept.app\n'),
      "mdfind kMDItemCFBundleIdentifier == 'com.example.Gone'": _fail(),
      'defaults write com.apple.spotlight EnabledPreferenceRules -array '
          'com.example.Kept': ProcessResult.success(
        '',
      ),
    });

    final result = await SpotlightOrphanRulesCleanupTask(
      home: _home,
      probe: probe,
      resolver: isolatedResolver(probe),
    ).run();

    expect(result.outcome, OptimizeOutcome.applied);
  });

  test('deletes the whole key when nothing survives', () async {
    final probe = FakeProcessRunner({
      'defaults read com.apple.spotlight EnabledPreferenceRules':
          ProcessResult.success(''),
      ..._entries(['com.example.OnlyOne']),
      "mdfind kMDItemCFBundleIdentifier == 'com.example.OnlyOne'": _fail(),
      'defaults delete com.apple.spotlight EnabledPreferenceRules':
          ProcessResult.success(''),
    });

    final result = await SpotlightOrphanRulesCleanupTask(
      home: _home,
      probe: probe,
      resolver: isolatedResolver(probe),
    ).run();

    expect(result.outcome, OptimizeOutcome.applied);
  });

  test('reports failed when the rewrite does not stick', () async {
    final probe = FakeProcessRunner({
      'defaults read com.apple.spotlight EnabledPreferenceRules':
          ProcessResult.success(''),
      ..._entries(['com.example.OnlyOne']),
      "mdfind kMDItemCFBundleIdentifier == 'com.example.OnlyOne'": _fail(),
      'defaults delete com.apple.spotlight EnabledPreferenceRules':
          ProcessResult.failure(
            ProcessFailure.nonZeroExit('defaults', 1, 'denied'),
          ),
    });

    final result = await SpotlightOrphanRulesCleanupTask(
      home: _home,
      probe: probe,
      resolver: isolatedResolver(probe),
    ).run();

    expect(result.outcome, OptimizeOutcome.failed);
  });
}
