/// Ports `mole_purge_is_cloud_synced_path` (`lib/clean/purge_shared.sh`):
/// whether [path] lives under iCloud Drive or a third-party cloud-sync
/// root. Purge still proposes these — [home] is itself a default search
/// root's parent for `~/Library/CloudStorage` — but the caller should
/// warn that removing a cloud-synced artifact can propagate to every
/// other device signed into the same account, not just this Mac.
bool isCloudSyncedPurgePath(String path, {required String home}) {
  const suffixes = ['/Library/CloudStorage', '/Library/Mobile Documents'];
  for (final suffix in suffixes) {
    final root = '$home$suffix';
    if (path == root || path.startsWith('$root/')) return true;
  }
  return false;
}
