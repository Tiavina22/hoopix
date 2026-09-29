import 'package:flutter_test/flutter_test.dart';
import 'package:hoopix/features/clean/domain/entities/user_cache_scope.dart';

const _home = '/Users/tester';

UserCacheScope? scopeOf(String path) => userCacheScopeOf(path, home: _home);

void main() {
  group('userCacheScopeOf', () {
    test('a reverse-DNS cache under Library/Caches is standard', () {
      expect(
        scopeOf('$_home/Library/Caches/com.example.App'),
        const UserCacheScope('com.example.App', UserCacheStorage.standard),
      );
      expect(
        scopeOf('$_home/Library/Caches/com.example.App/Cache.db-wal'),
        const UserCacheScope('com.example.App', UserCacheStorage.standard),
      );
    });

    test('an app container cache is container-scoped', () {
      expect(
        scopeOf(
          '$_home/Library/Containers/com.example.App/Data/Library/Caches',
        ),
        const UserCacheScope('com.example.App', UserCacheStorage.container),
      );
      expect(
        scopeOf(
          '$_home/Library/Containers/com.example.App/Data/Library/Caches/x',
        ),
        const UserCacheScope('com.example.App', UserCacheStorage.container),
      );
    });

    test('both group container cache layouts are container-scoped', () {
      for (final path in [
        '$_home/Library/Group Containers/group.com.example/Caches/x',
        '$_home/Library/Group Containers/group.com.example/Library/Caches/x',
      ]) {
        expect(
          scopeOf(path),
          const UserCacheScope('group.com.example', UserCacheStorage.container),
          reason: path,
        );
      }
    });

    test('anything else in a container is out of scope', () {
      expect(
        scopeOf('$_home/Library/Containers/com.example.App/Data/tmp/x'),
        isNull,
      );
      expect(
        scopeOf('$_home/Library/Group Containers/group.com.example/Logs/x'),
        isNull,
      );
    });

    test('a named, non-reverse-DNS cache tree is out of scope', () {
      expect(scopeOf('$_home/Library/Caches/Homebrew'), isNull);
      expect(scopeOf('$_home/Library/Caches/.hidden.dir'), isNull);
    });

    test('paths outside the Library are out of scope', () {
      expect(scopeOf('$_home/.npm/_cacache'), isNull);
      expect(scopeOf('/Library/Caches/com.apple.iconservices.store'), isNull);
    });
  });

  group('SQLite families', () {
    test('recognizes the main file and every companion, in any case', () {
      for (final path in [
        '/c/Cache.db',
        '/c/Cache.db-wal',
        '/c/Cache.db-shm',
        '/c/Cache.db-journal',
        '/c/store.SQLITE',
        '/c/store.sqlite3-wal',
      ]) {
        expect(isSqliteFamilyPath(path), isTrue, reason: path);
      }
      expect(isSqliteFamilyPath('/c/Cache.dbx'), isFalse);
      expect(isSqliteFamilyPath('/c/fsCachedData'), isFalse);
    });

    test('a companion maps back to its main database', () {
      expect(sqliteFamilyBase('/c/Cache.db-wal'), '/c/Cache.db');
      expect(sqliteFamilyBase('/c/Cache.db-shm'), '/c/Cache.db');
      expect(sqliteFamilyBase('/c/Cache.db'), '/c/Cache.db');
    });
  });
}
