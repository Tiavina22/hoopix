import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:hoopix/core/process/process_failure.dart';
import 'package:hoopix/core/process/process_runner.dart';
import 'package:hoopix/features/uninstall/data/datasources/pkg_receipt_apps.dart';

/// A fake `pkgutil`: `--pkgs` answers [pkgs], `--files <id>` answers from
/// [files]; an id missing from [files] fails like a broken receipt.
class _Pkgutil extends ProcessRunner {
  _Pkgutil({required this.pkgs, this.files = const {}, this.pkgsFail = false});

  String pkgs;
  final Map<String, String> files;
  final bool pkgsFail;
  final calls = <String>[];

  @override
  Future<ProcessResult> run(String executable, List<String> arguments) async {
    expect(executable, 'pkgutil');
    calls.add(arguments.join(' '));
    if (arguments.first == '--pkgs') {
      return pkgsFail
          ? ProcessResult.failure(ProcessFailure.nonZeroExit('pkgutil', 1, ''))
          : ProcessResult.success(pkgs);
    }
    final listed = files[arguments.last];
    return listed == null
        ? ProcessResult.failure(
            ProcessFailure.nonZeroExit('pkgutil', 1, 'No receipt'),
          )
        : ProcessResult.success(listed);
  }
}

void main() {
  final farFuture = DateTime.now().add(const Duration(hours: 1));

  PkgReceiptApps receiptsWith(
    _Pkgutil pkgutil, {
    Set<String> directories = const {
      '/opt/vendor/Tool.app',
      '/usr/local/bin/Helper.app',
    },
  }) => PkgReceiptApps(
    runner: pkgutil,
    typeOf: (path) => directories.contains(path)
        ? FileSystemEntityType.directory
        : FileSystemEntityType.notFound,
  );

  group('nonstandardAppFromReceiptPath', () {
    test('cuts back to the first .app under /usr/local or /opt', () {
      expect(
        nonstandardAppFromReceiptPath(
          'opt/vendor/Tool.app/Contents/Info.plist',
        ),
        '/opt/vendor/Tool.app',
      );
      expect(
        nonstandardAppFromReceiptPath('usr/local/bin/Helper.app'),
        '/usr/local/bin/Helper.app',
      );
    });

    test('ignores every other location, and non-app paths', () {
      expect(
        nonstandardAppFromReceiptPath('Applications/Tool.app/Contents/x'),
        isNull,
      );
      expect(nonstandardAppFromReceiptPath('usr/local/bin/tool'), isNull);
      expect(
        nonstandardAppFromReceiptPath('opt/x/Tool.application/Contents'),
        isNull,
      );
      expect(nonstandardAppFromReceiptPath(''), isNull);
    });
  });

  test(
    "collects the apps a vendor's receipts installed, skipping Apple's",
    () async {
      final pkgutil = _Pkgutil(
        pkgs: 'com.apple.pkg.Core\norg.vendor.tool\nnet.other.helper\n',
        files: {
          'org.vendor.tool':
              'opt/vendor/Tool.app\nopt/vendor/Tool.app/Contents/Info.plist\n',
          'net.other.helper':
              'usr/local/bin/Helper.app/Contents/MacOS/Helper\n'
              'usr/local/bin/Gone.app/Contents/Info.plist\n',
        },
      );

      final scan = await receiptsWith(
        pkgutil,
      ).nonstandardAppPaths(deadline: farFuture);

      expect(scan.complete, isTrue);
      // Gone.app is in a receipt but no longer on disk.
      expect(scan.appPaths, [
        '/opt/vendor/Tool.app',
        '/usr/local/bin/Helper.app',
      ]);
      expect(pkgutil.calls, isNot(contains('--files com.apple.pkg.Core')));
    },
  );

  test('a receipt it cannot read makes the answer incomplete', () async {
    final scan = await receiptsWith(
      _Pkgutil(pkgs: 'org.vendor.broken\n'),
    ).nonstandardAppPaths(deadline: farFuture);

    expect(scan.complete, isFalse);
  });

  test('a receipt list it cannot read is incomplete, not empty', () async {
    final scan = await receiptsWith(
      _Pkgutil(pkgs: '', pkgsFail: true),
    ).nonstandardAppPaths(deadline: farFuture);

    expect(scan.complete, isFalse);
  });

  test('running past the deadline makes the answer incomplete', () async {
    final scan =
        await receiptsWith(
          _Pkgutil(pkgs: 'org.vendor.tool\n', files: {'org.vendor.tool': ''}),
        ).nonstandardAppPaths(
          deadline: DateTime.now().subtract(const Duration(seconds: 1)),
        );

    expect(scan.complete, isFalse);
  });

  test('reuses the last walk while the receipt list is unchanged, and walks '
      'again as soon as a package is added', () async {
    final pkgutil = _Pkgutil(
      pkgs: 'org.vendor.tool\n',
      files: {
        'org.vendor.tool': 'opt/vendor/Tool.app\n',
        'net.other.helper': 'usr/local/bin/Helper.app\n',
      },
    );
    final receipts = receiptsWith(pkgutil);

    await receipts.nonstandardAppPaths(deadline: farFuture);
    await receipts.nonstandardAppPaths(deadline: farFuture);
    expect(pkgutil.calls.where((c) => c.startsWith('--files')), hasLength(1));

    pkgutil.pkgs = 'org.vendor.tool\nnet.other.helper\n';
    final scan = await receipts.nonstandardAppPaths(deadline: farFuture);

    expect(pkgutil.calls.where((c) => c.startsWith('--files')), hasLength(3));
    expect(scan.appPaths, [
      '/opt/vendor/Tool.app',
      '/usr/local/bin/Helper.app',
    ]);
  });
}
