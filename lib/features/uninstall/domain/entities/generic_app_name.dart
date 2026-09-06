/// Ports `LAUNCH_AGENT_NAME_COMMON_WORDS` (`lib/core/app_protection_data.sh`)
/// and its lowercase mirror `_mole_uninstall_is_common_app_name`
/// (`lib/core/app_protection.sh`) — kept as one list here rather than the
/// two independently-defined copies Mole carries, since both describe the
/// same rule: a display name this generic is not enough evidence on its
/// own to match a loose, name-only glob (a LaunchAgent search, a
/// vendor-nested support directory, a shared `/Users/Shared` path). An app
/// actually named "System" or "Update" still gets torn down through its
/// bundle id and exact-path templates, which do not use this list at all.
const genericAppNames = {
  'music',
  'notes',
  'photos',
  'finder',
  'safari',
  'preview',
  'calendar',
  'contacts',
  'messages',
  'reminders',
  'clock',
  'weather',
  'stocks',
  'books',
  'news',
  'podcasts',
  'voice',
  'files',
  'store',
  'system',
  'helper',
  'agent',
  'daemon',
  'service',
  'update',
  'sync',
  'backup',
  'cloud',
  'manager',
  'monitor',
  'server',
  'client',
  'worker',
  'runner',
  'launcher',
  'driver',
  'plugin',
  'extension',
  'widget',
  'utility',
};

/// Whether [appName] is one of [genericAppNames], case-insensitively.
bool isGenericAppName(String appName) =>
    genericAppNames.contains(appName.toLowerCase());
