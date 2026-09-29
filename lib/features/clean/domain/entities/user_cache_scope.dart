/// Which reverse-DNS app owns a user cache path, and how it is stored —
/// port of `_mole_user_cache_scope` (`lib/core/file_ops.sh`, Mole #1390).
///
/// Only paths inside a reverse-DNS cache tree are in scope: the live-cache
/// guard needs an owner to ask about, and named trees such as
/// `~/Library/Caches/Homebrew` have their own process probes.
library;

/// Where the cache lives, which decides how the open-file check looks at
/// it: a [standard] `~/Library/Caches/<id>` tree only has its SQLite
/// families checked, while a [container] cache is checked for any open
/// descendant, because a container id and the helper process writing into
/// it need not share a name.
enum UserCacheStorage { standard, container }

class UserCacheScope {
  const UserCacheScope(this.owner, this.storage);

  /// The reverse-DNS directory name (`com.vendor.app`) the cache is under.
  final String owner;
  final UserCacheStorage storage;

  @override
  bool operator ==(Object other) =>
      other is UserCacheScope &&
      other.owner == owner &&
      other.storage == storage;

  @override
  int get hashCode => Object.hash(owner, storage);

  @override
  String toString() => 'UserCacheScope($owner, ${storage.name})';
}

/// The scope of [path] under [home], or null when it is not inside a
/// reverse-DNS user cache tree:
///
/// - `~/Library/Caches/<id>[/...]`
/// - `~/Library/Containers/<id>/Data/Library/Caches[/...]`
/// - `~/Library/Group Containers/<id>/[Library/]Caches[/...]`
UserCacheScope? userCacheScopeOf(String path, {required String home}) {
  final normalized = path.endsWith('/')
      ? path.substring(0, path.length - 1)
      : path;
  final library = '${_withoutTrailingSlash(home)}/Library';

  String? component;
  UserCacheStorage? storage;

  if (normalized.startsWith('$library/Caches/')) {
    component = _firstComponent(
      normalized.substring('$library/Caches/'.length),
    );
    storage = UserCacheStorage.standard;
  } else if (normalized.startsWith('$library/Containers/')) {
    final remainder = normalized.substring('$library/Containers/'.length);
    component = _firstComponent(remainder);
    final suffix = remainder.substring(component.length);
    if (!_isOrUnder(suffix, '/Data/Library/Caches')) return null;
    storage = UserCacheStorage.container;
  } else if (normalized.startsWith('$library/Group Containers/')) {
    final remainder = normalized.substring('$library/Group Containers/'.length);
    component = _firstComponent(remainder);
    final suffix = remainder.substring(component.length);
    if (!_isOrUnder(suffix, '/Caches') &&
        !_isOrUnder(suffix, '/Library/Caches')) {
      return null;
    }
    storage = UserCacheStorage.container;
  } else {
    return null;
  }

  // Reverse-DNS style only (com.vendor.app).
  if (!component.contains('.') || component.startsWith('.')) return null;
  return UserCacheScope(component, storage);
}

/// A SQLite main file or its `-wal` / `-shm` / `-journal` companion, by
/// name, case-insensitively — port of `_mole_is_sqlite_database_path`, so
/// a cache sweep cannot reach a database through a case variant.
bool isSqliteFamilyPath(String path) {
  final base = sqliteFamilyBase(path).toLowerCase();
  return base.endsWith('.db') ||
      base.endsWith('.sqlite') ||
      base.endsWith('.sqlite3');
}

/// The main database path a SQLite companion file belongs to.
String sqliteFamilyBase(String path) {
  for (final suffix in const ['-wal', '-shm', '-journal']) {
    if (path.endsWith(suffix)) {
      return path.substring(0, path.length - suffix.length);
    }
  }
  return path;
}

/// Mole's `mole_is_reverse_dns_bundle_id`.
bool isReverseDnsBundleId(String? id) =>
    id != null &&
    id != 'unknown' &&
    RegExp(
      r'^[A-Za-z0-9][-A-Za-z0-9]*(\.[A-Za-z0-9][-A-Za-z0-9]*)+$',
    ).hasMatch(id);

String _firstComponent(String remainder) {
  final slash = remainder.indexOf('/');
  return slash < 0 ? remainder : remainder.substring(0, slash);
}

bool _isOrUnder(String suffix, String root) =>
    suffix == root || suffix.startsWith('$root/');

String _withoutTrailingSlash(String path) =>
    path.endsWith('/') && path.length > 1
    ? path.substring(0, path.length - 1)
    : path;
