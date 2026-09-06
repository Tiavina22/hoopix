/// The fixed lists Mole's own `mo purge` is built from
/// (`lib/clean/purge_shared.sh`, `lib/clean/project.sh`), ported verbatim.
/// Every list here is a safety boundary in its own right — see
/// [purgeTargets]'s own doc for the sharpest example — so additions must
/// come from reading Mole's source, never guessed.
library;

/// Heavy, rebuildable project build artifacts purge may ever propose —
/// `MOLE_PURGE_TARGETS`. This list is also the entire boundary
/// `isProjectContainer` uses to refuse ever treating one of these names as
/// a scannable project container: a stray `~/node_modules` would otherwise
/// look like a container (every npm package ships `package.json`, the
/// first project indicator), the scan would start below the artifact
/// itself, and nested-artifact collapsing would never see `node_modules`
/// to collapse into — package-internal `dist/`/`build/` directories would
/// reach the delete list, leaving `package.json` in place while the
/// package is actually gone, needing a network restore purge must never
/// require (Mole issue #1459). `bin`, `vendor`, and `DerivedData` are
/// matched like any other target here but then vetoed by
/// [isProtectedPurgeArtifact] unless a secondary condition holds.
const purgeTargets = [
  'node_modules',
  'target', // Rust, Maven
  'build', // Gradle, various
  'dist', // JS builds
  'venv', // Python
  '.venv', // Python
  '.pytest_cache', // Python (pytest)
  '.mypy_cache', // Python (mypy)
  '.tox', // Python (tox virtualenvs)
  '.nox', // Python (nox virtualenvs)
  '.ruff_cache', // Python (ruff)
  '.gradle', // Gradle local
  '.terragrunt-cache', // Terragrunt downloaded modules/providers
  '__pycache__', // Python
  '.next', // Next.js
  '.nuxt', // Nuxt.js
  '.output', // Nuxt.js
  'vendor', // PHP Composer
  'bin', // .NET build output (guarded; see isProtectedPurgeArtifact)
  'obj', // C# / Unity
  '.turbo', // Turborepo cache
  '.parcel-cache', // Parcel bundler
  '.dart_tool', // Flutter/Dart build cache
  '.zig-cache', // Zig
  'zig-out', // Zig
  '.angular', // Angular
  '.svelte-kit', // SvelteKit
  '.astro', // Astro
  'coverage', // Code coverage reports
  'DerivedData', // Xcode
  'Pods', // CocoaPods
  '.cxx', // React Native Android NDK build cache
  '.expo', // Expo
  '.build', // Swift Package Manager
];

/// Default scan roots — `MOLE_PURGE_DEFAULT_SEARCH_PATHS`. The last two are
/// the only dot-directory containers in scope, listed explicitly because
/// [isProjectContainer] categorically rejects a dot-prefixed basename:
/// discovery cannot reach them any other way without widening that rule to
/// dot directories in general, which purge deliberately does not do. The
/// worktrees themselves are never purge targets — only rebuildable
/// artifacts found inside a checkout are.
List<String> purgeDefaultSearchPaths(String home) => [
  '$home/www',
  '$home/dev',
  '$home/Projects',
  '$home/GitHub',
  '$home/Code',
  '$home/Workspace',
  '$home/Repos',
  '$home/Development',
  '$home/Library/CloudStorage',
  '$home/.codex/worktrees',
  '$home/.claude/worktrees',
];

/// A repository or worktree is the project-wide ownership boundary even
/// when nested packages have their own manifests — checked first, and
/// `.git` is kept in [projectIndicators] too since container discovery
/// consumes that list directly.
const monorepoIndicators = [
  'lerna.json',
  'pnpm-workspace.yaml',
  'nx.json',
  'rush.json',
  '.git',
];

const projectIndicators = [
  'package.json',
  'Cargo.toml',
  'go.mod',
  'pyproject.toml',
  'requirements.txt',
  'pom.xml',
  'build.gradle',
  'terragrunt.hcl',
  'Gemfile',
  'composer.json',
  'pubspec.yaml',
  'Package.swift', // Swift Package Manager
  'Makefile',
  'build.zig',
  'build.zig.zon',
  '.git',
];

/// Minimum age, in days, before a project artifact is considered for
/// cleanup — `MIN_AGE_DAYS`.
const purgeMinimumAgeDays = 7;

/// The exact byte signature a `CACHEDIR.TAG` file's first line must match
/// for a directory to be treated as a cache root purge may also propose,
/// independent of the named-target list.
const cachedirTagSignature = 'Signature: 8a477f597d28d172789f06886806bc55';
