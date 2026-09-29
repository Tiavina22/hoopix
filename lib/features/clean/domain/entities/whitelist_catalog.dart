import 'package:hoopix/features/clean/domain/entities/clean_whitelist.dart';

/// The groups the whitelist editor shows its catalog in — Mole's own
/// `get_all_cache_items` categories.
enum WhitelistCategory {
  systemCache,
  ideCache,
  aiMlCache,
  compilerCache,
  packageManager,
  browserCache,
  networkTools,
  containerCache,
  appCache,
}

/// One cache the user can choose to protect, with the exact pattern the
/// whitelist file stores for it (`~` for the home directory, so the file
/// stays portable between machines and between hoopix and Mole).
class WhitelistCatalogItem {
  const WhitelistCatalogItem(this.label, this.pattern, this.category);

  final String label;
  final String pattern;
  final WhitelistCategory category;
}

/// Port of Mole's `get_all_cache_items` (`lib/manage/whitelist.sh`), in its
/// order. Not ported: the Go, GitHub CLI and Clang module cache rows, whose
/// paths Mole resolves by asking `go env`, `$XDG_CACHE_HOME` and
/// `getconf DARWIN_USER_CACHE_DIR` at run time; any of them can still be
/// protected as a custom path.
const whitelistCatalog = [
  WhitelistCatalogItem(
    'Apple Mail cache',
    '~/Library/Caches/com.apple.mail/*',
    WhitelistCategory.systemCache,
  ),
  WhitelistCatalogItem(
    'Gradle build cache (Android Studio, Gradle projects)',
    '~/.gradle/caches/build-cache-*/*',
    WhitelistCategory.ideCache,
  ),
  WhitelistCatalogItem(
    'Gradle daemon processes cache',
    '~/.gradle/daemon/*',
    WhitelistCategory.ideCache,
  ),
  WhitelistCatalogItem(
    'Gradle worker cache',
    '~/.gradle/workers/*',
    WhitelistCategory.ideCache,
  ),
  WhitelistCatalogItem(
    'Xcode DerivedData (build outputs, indexes)',
    '~/Library/Developer/Xcode/DerivedData/*',
    WhitelistCategory.ideCache,
  ),
  WhitelistCatalogItem(
    'Xcode internal cache files',
    '~/Library/Caches/com.apple.dt.Xcode/*',
    WhitelistCategory.ideCache,
  ),
  WhitelistCatalogItem(
    'Xcode iOS device support symbols',
    '~/Library/Developer/Xcode/iOS DeviceSupport/*/Symbols/System/Library/Caches/*',
    WhitelistCategory.ideCache,
  ),
  WhitelistCatalogItem(
    'JetBrains IDEs data (IntelliJ, PyCharm, WebStorm, GoLand)',
    '~/Library/Application Support/JetBrains/*',
    WhitelistCategory.ideCache,
  ),
  WhitelistCatalogItem(
    'JetBrains IDEs cache',
    '~/Library/Caches/JetBrains/*',
    WhitelistCategory.ideCache,
  ),
  WhitelistCatalogItem(
    'Android Studio cache and indexes',
    '~/Library/Caches/Google/AndroidStudio*/*',
    WhitelistCategory.ideCache,
  ),
  WhitelistCatalogItem(
    'Android build cache',
    '~/.android/build-cache/*',
    WhitelistCategory.ideCache,
  ),
  WhitelistCatalogItem(
    'VS Code runtime cache',
    '~/Library/Application Support/Code/Cache/*',
    WhitelistCategory.ideCache,
  ),
  WhitelistCatalogItem(
    'VS Code extension and update cache',
    '~/Library/Application Support/Code/CachedData/*',
    WhitelistCategory.ideCache,
  ),
  WhitelistCatalogItem(
    'VS Code system cache (Cursor, VSCodium)',
    '~/Library/Caches/com.microsoft.VSCode/*',
    WhitelistCategory.ideCache,
  ),
  WhitelistCatalogItem(
    'Cursor editor cache',
    '~/Library/Caches/com.todesktop.230313mzl4w4u92/*',
    WhitelistCategory.ideCache,
  ),
  WhitelistCatalogItem(
    'LM Studio app cache',
    '~/Library/Caches/com.lmstudio.lmstudio/*',
    WhitelistCategory.aiMlCache,
  ),
  WhitelistCatalogItem(
    'Codex Desktop update staging',
    '~/Library/Caches/com.openai.codex/org.sparkle-project.Sparkle/Installation',
    WhitelistCategory.aiMlCache,
  ),
  WhitelistCatalogItem(
    'Chrome on-device AI models',
    '~/Library/Application Support/Google/Chrome/OptGuideOnDevice*/*',
    WhitelistCategory.aiMlCache,
  ),
  WhitelistCatalogItem(
    'Chrome optimization guide models',
    '~/Library/Application Support/Google/Chrome/optimization_guide_model_store/*',
    WhitelistCategory.aiMlCache,
  ),
  WhitelistCatalogItem(
    'Bazel build cache',
    '~/.cache/bazel/*',
    WhitelistCategory.compilerCache,
  ),
  WhitelistCatalogItem(
    'Rust Cargo registry cache',
    '~/.cargo/registry/cache/*',
    WhitelistCategory.compilerCache,
  ),
  WhitelistCatalogItem(
    'Rust documentation cache',
    '~/.rustup/toolchains/*/share/doc/*',
    WhitelistCategory.compilerCache,
  ),
  WhitelistCatalogItem(
    'Rustup toolchain downloads',
    '~/.rustup/downloads/*',
    WhitelistCategory.compilerCache,
  ),
  WhitelistCatalogItem(
    'ccache compiler cache',
    '~/.ccache/*',
    WhitelistCategory.compilerCache,
  ),
  WhitelistCatalogItem(
    'sccache distributed compiler cache',
    '~/.cache/sccache/*',
    WhitelistCategory.compilerCache,
  ),
  WhitelistCatalogItem(
    'Turbo monorepo build cache',
    '~/.turbo/*',
    WhitelistCategory.compilerCache,
  ),
  WhitelistCatalogItem(
    'Next.js build cache',
    '~/.next/*',
    WhitelistCategory.compilerCache,
  ),
  WhitelistCatalogItem(
    'Vite build cache',
    '~/.vite/*',
    WhitelistCategory.compilerCache,
  ),
  WhitelistCatalogItem(
    'Parcel bundler cache',
    '~/.parcel-cache/*',
    WhitelistCategory.compilerCache,
  ),
  WhitelistCatalogItem(
    'pre-commit hooks cache',
    '~/.cache/pre-commit/*',
    WhitelistCategory.compilerCache,
  ),
  WhitelistCatalogItem(
    'Ruff Python linter cache',
    '~/.cache/ruff/*',
    WhitelistCategory.compilerCache,
  ),
  WhitelistCatalogItem(
    'MyPy type checker cache',
    '~/.cache/mypy/*',
    WhitelistCategory.compilerCache,
  ),
  WhitelistCatalogItem(
    'Pytest test cache',
    '~/.pytest_cache/*',
    WhitelistCategory.compilerCache,
  ),
  WhitelistCatalogItem(
    'PyInstaller binary cache',
    '~/Library/Application Support/pyinstaller/bincache*',
    WhitelistCategory.compilerCache,
  ),
  WhitelistCatalogItem(
    'Flutter SDK cache',
    '~/.cache/flutter/*',
    WhitelistCategory.compilerCache,
  ),
  WhitelistCatalogItem(
    'Swift Package Manager cache',
    '~/.cache/swift-package-manager/*',
    WhitelistCategory.compilerCache,
  ),
  WhitelistCatalogItem(
    'Zig compiler cache',
    '~/.cache/zig/*',
    WhitelistCategory.compilerCache,
  ),
  WhitelistCatalogItem(
    'CocoaPods cache (iOS dependencies)',
    '~/Library/Caches/CocoaPods/*',
    WhitelistCategory.packageManager,
  ),
  WhitelistCatalogItem(
    'npm package cache',
    '~/.npm/_cacache/*',
    WhitelistCategory.packageManager,
  ),
  WhitelistCatalogItem(
    'pip Python package cache',
    '~/.cache/pip/*',
    WhitelistCategory.packageManager,
  ),
  WhitelistCatalogItem(
    'uv Python package cache',
    '~/.cache/uv/*',
    WhitelistCategory.packageManager,
  ),
  WhitelistCatalogItem(
    'R renv global cache (virtual environments)',
    '~/Library/Caches/org.R-project.R/R/renv/*',
    WhitelistCategory.packageManager,
  ),
  WhitelistCatalogItem(
    'tealdeer tldr pages cache',
    '~/Library/Caches/tealdeer/tldr-pages',
    WhitelistCategory.packageManager,
  ),
  WhitelistCatalogItem(
    'Homebrew downloaded packages',
    '~/Library/Caches/Homebrew/*',
    WhitelistCategory.packageManager,
  ),
  WhitelistCatalogItem(
    'Yarn package manager cache',
    '~/.cache/yarn/*',
    WhitelistCategory.packageManager,
  ),
  WhitelistCatalogItem(
    'pnpm package store',
    '~/Library/pnpm/store/*',
    WhitelistCategory.packageManager,
  ),
  WhitelistCatalogItem(
    'Composer PHP dependencies cache (legacy)',
    '~/.composer/cache/*',
    WhitelistCategory.packageManager,
  ),
  WhitelistCatalogItem(
    'Composer PHP dependencies cache',
    '~/Library/Caches/composer/*',
    WhitelistCategory.packageManager,
  ),
  WhitelistCatalogItem(
    'RubyGems cache',
    '~/.gem/cache/*',
    WhitelistCategory.packageManager,
  ),
  WhitelistCatalogItem(
    'Conda package metadata/tarball cache',
    '~/.conda/pkgs',
    WhitelistCategory.packageManager,
  ),
  WhitelistCatalogItem(
    'Anaconda package metadata/tarball cache',
    '~/anaconda3/pkgs',
    WhitelistCategory.packageManager,
  ),
  WhitelistCatalogItem(
    'Playwright browser binaries',
    '~/Library/Caches/ms-playwright*',
    WhitelistCategory.aiMlCache,
  ),
  WhitelistCatalogItem(
    'Selenium WebDriver binaries',
    '~/.cache/selenium/*',
    WhitelistCategory.aiMlCache,
  ),
  WhitelistCatalogItem(
    'Ollama local AI models',
    '~/.ollama/models/*',
    WhitelistCategory.aiMlCache,
  ),
  WhitelistCatalogItem(
    'Safari web browser cache',
    '~/Library/Caches/com.apple.Safari/*',
    WhitelistCategory.browserCache,
  ),
  WhitelistCatalogItem(
    'Chrome browser cache',
    '~/Library/Caches/Google/Chrome/*',
    WhitelistCategory.browserCache,
  ),
  WhitelistCatalogItem(
    'Firefox browser cache',
    '~/Library/Caches/Firefox/*',
    WhitelistCategory.browserCache,
  ),
  WhitelistCatalogItem(
    'Brave browser cache',
    '~/Library/Caches/BraveSoftware/Brave-Browser/*',
    WhitelistCategory.browserCache,
  ),
  WhitelistCatalogItem(
    'Surge proxy cache',
    '~/Library/Caches/com.nssurge.surge-mac/*',
    WhitelistCategory.networkTools,
  ),
  WhitelistCatalogItem(
    'Surge configuration and data',
    '~/Library/Application Support/com.nssurge.surge-mac/*',
    WhitelistCategory.networkTools,
  ),
  WhitelistCatalogItem(
    'Docker BuildX cache',
    '~/.docker/buildx/cache/*',
    WhitelistCategory.containerCache,
  ),
  WhitelistCatalogItem(
    'Podman container cache',
    '~/.local/share/containers/cache/*',
    WhitelistCategory.containerCache,
  ),
  WhitelistCatalogItem(
    'Tart OCI/IPSW cache',
    '~/.tart/cache',
    WhitelistCategory.containerCache,
  ),
  WhitelistCatalogItem(
    'Final Cut Pro proxy media (render files still cleaned)',
    '~/Movies/*.fcpbundle/*/Transcoded Media/Proxy Media',
    WhitelistCategory.appCache,
  ),
  WhitelistCatalogItem(
    'Font cache',
    '~/Library/Caches/com.apple.FontRegistry/*',
    WhitelistCategory.systemCache,
  ),
  WhitelistCatalogItem(
    'Spotlight metadata cache',
    '~/Library/Caches/com.apple.spotlight/*',
    WhitelistCategory.systemCache,
  ),
  WhitelistCatalogItem(
    'CloudKit cache',
    '~/Library/Caches/CloudKit/*',
    WhitelistCategory.systemCache,
  ),
  WhitelistCatalogItem('Trash', '~/.Trash', WhitelistCategory.systemCache),
  WhitelistCatalogItem(
    'iOS/iPadOS device firmware (.ipsw) from iTunes/Finder',
    '~/Library/iTunes/*Software Updates/*.ipsw',
    WhitelistCategory.systemCache,
  ),
  WhitelistCatalogItem(
    'Apple Configurator 2 device firmware (.ipsw)',
    '~/Library/Group Containers/*.group.com.apple.configurator/**/*.ipsw',
    WhitelistCategory.systemCache,
  ),
  WhitelistCatalogItem(
    'Finder metadata, .DS_Store',
    finderMetadataSentinel,
    WhitelistCategory.systemCache,
  ),
];

/// Mole's `patterns_equivalent`: the same pattern once `~`, `$HOME` and
/// `${HOME}` are expanded. Exact string equality, never glob expansion.
bool whitelistPatternsEquivalent(String a, String b, {required String home}) =>
    expandWhitelistHome(a, home: home) == expandWhitelistHome(b, home: home);

String expandWhitelistHome(String pattern, {required String home}) {
  var line = pattern.trim();
  if (line.startsWith('~')) line = '$home${line.substring(1)}';
  return line.replaceAll(r'${HOME}', home).replaceAll(r'$HOME', home);
}
