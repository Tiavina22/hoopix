import 'package:flutter_test/flutter_test.dart';
import 'package:hoopix/features/purge/domain/entities/purge_cloud_sync.dart';

const _home = '/Users/tester';

void main() {
  test('true for a path under Library/CloudStorage', () {
    expect(
      isCloudSyncedPurgePath(
        '$_home/Library/CloudStorage/Dropbox/project/node_modules',
        home: _home,
      ),
      isTrue,
    );
  });

  test('true for a path under Library/Mobile Documents', () {
    expect(
      isCloudSyncedPurgePath(
        '$_home/Library/Mobile Documents/com~apple~CloudDocs/project/build',
        home: _home,
      ),
      isTrue,
    );
  });

  test('false for an ordinary project path', () {
    expect(
      isCloudSyncedPurgePath('$_home/Code/project/node_modules', home: _home),
      isFalse,
    );
  });

  test('false for a path that merely contains the word Library elsewhere', () {
    expect(
      isCloudSyncedPurgePath(
        '$_home/Code/Library/CloudStorage/node_modules',
        home: _home,
      ),
      isFalse,
    );
  });
}
