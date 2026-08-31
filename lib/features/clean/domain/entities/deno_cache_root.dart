/// Where Deno keeps its cache, or null when that cannot be answered safely.
///
/// Deno's root sits inside the otherwise broad `~/Library/Caches` sweep, but
/// it is review-only: `deno clean` removes the entire DENO_DIR, including
/// origin storage and downloaded runtime payloads, so it is not a cache in
/// the sense the sweep assumes. The sweep therefore skips it.
///
/// Returns null for a DENO_DIR that is relative, contains control characters
/// or traversal, or names a root so broad that treating it as "Deno's cache"
/// would exclude far more than Deno. Refusing is the safe answer — but the
/// caller must then keep the whole batch empty rather than sweep past an
/// unresolved owner root, which is why this reports null instead of falling
/// back to the default.
///
/// Port of `mole_deno_cache_root` in Mole's `lib/core/base.sh`.
String? denoCacheRoot({required String home, String? denoDir}) {
  var root = (denoDir == null || denoDir.isEmpty)
      ? '$home/Library/Caches/deno'
      : denoDir;

  if (!root.startsWith('/')) return null;
  if (root.codeUnits.any((unit) => unit < 0x20 || unit == 0x7f)) return null;
  if (root.contains('/../') ||
      root.endsWith('/..') ||
      root.contains('/./') ||
      root.endsWith('/.') ||
      root.contains('//')) {
    return null;
  }

  if (root.length > 1 && root.endsWith('/')) {
    root = root.substring(0, root.length - 1);
  }
  final homeRoot = home.endsWith('/') ? home.substring(0, home.length - 1) : home;

  // Roots so broad that excluding them would exclude everything the sweep
  // is for.
  const tooBroad = ['', '/'];
  if (tooBroad.contains(root) ||
      root == homeRoot ||
      root == '$homeRoot/Library' ||
      root == '$homeRoot/Library/Caches' ||
      root == '$homeRoot/.cache') {
    return null;
  }

  return root;
}
