# Hoopix

A free, open-source macOS maintenance app, built with Flutter.

Licensed under the [GNU GPLv3](LICENSE).

Hoopix is an alternative to the paid native Mac apps in this space: cleanup,
app management, maintenance, disk maps, and live system status in one place,
with the interface free and the source open.

> **Status: early, but it does act on your Mac.** Every section below is
> implemented, and several of them delete or change real files. Read the
> confirmation before you approve one.

## Install

Requires **macOS 12 (Monterey) or later on Apple Silicon** (M1 or newer). The
current release does not run on Intel Macs.

1. Download `Hoopix-<version>-macos-arm64.dmg` from the
   [Releases](https://github.com/Tiavina22/hoopix/releases) page, and only from
   there: Hoopix deletes files, so do not run a copy from anywhere else.
2. Optionally check it against the `SHA256SUMS` file published with it:
   `shasum -a 256 -c SHA256SUMS`.
3. Open the disk image and drag **hoopix** onto **Applications**.

**The first launch is blocked by macOS, and that is expected.** Hoopix is not
signed with an Apple Developer ID and is not notarized yet, so Gatekeeper
refuses an app it does not recognize. To allow it, either:

- open **System Settings › Privacy & Security** (Security & Privacy on macOS
  12), scroll down to the message about *hoopix*, and click **Open Anyway**; or
- run `xattr -dr com.apple.quarantine /Applications/hoopix.app` in Terminal.

You only do this once.

## What it does

| Section | What it does | Can you undo it? |
|---|---|---|
| **Status** | Live CPU, memory, storage, battery, and network. Read-only. | Nothing changes. |
| **Clean** | Finds caches, logs, and leftovers, shows a preview, then removes what you approve. | Items go to the Trash, except those reclaimed by their own tool's clean command: those are flagged in the confirmation and cannot be put back. |
| **Uninstall** | Removes an app, its launch agents, login item, Dock tile, and known leftover files. Apps installed with Homebrew go through `brew uninstall --cask`. | The app and its leftovers go to the Trash. A Homebrew uninstall is permanent, and the confirmation says so. |
| **Purge** | Removes old project build artifacts (`node_modules`, `target`, and similar). | **No.** These are deleted outright. |
| **Analyze** | A disk explorer: see what is big, then move it to the Trash. | Yes, from the Trash. |
| **Optimize** | Runs bounded maintenance tasks (refresh caches, rebuild the Launch Services database, and so on). Some ask for your administrator password. | Not applicable. |
| **History** | Read-only list of what the other sections did or refused to do, and why. | Nothing changes. |

Anything that deletes asks you first, is checked again at the moment it runs,
and is written to `~/Library/Logs/hoopix/operations.log`. Protected system
paths are refused. The rules are ported from
[Mole](https://github.com/tw93/Mole).

## Two systems

The codebase is organized as **Clean Architecture, feature-first**, which is
also where the two halves of the product live:

| System | Layers | Rule |
|---|---|---|
| **Engine** (*moteur*) | `features/<name>/data` + `features/<name>/domain` | Pure Dart. No Flutter imports in `domain/`. Owns collection, parsing, and policy. |
| **Interface** | `features/<name>/presentation` | Flutter only. Talks to typed entities and use cases — never to `dart:io` directly. |

```
lib/
  core/                     # shared: process runner, theme tokens, navigation, shared widgets
  features/                 # analyze, clean, history, optimize, purge, settings, status, uninstall, about
    status/                 # every feature has the same three layers, e.g.:
      data/                 # datasources (macOS CLI probes), models (parsers), repository impl
      domain/               # entities, repository interface, use cases
      presentation/         # controller, screen, widgets
```

Dependency direction is inward only: `presentation → domain ← data`. The data
layer is the only place allowed to touch `ProcessRunner`.

The engine is written from scratch in Dart. Hoopix has **no runtime
dependency on Mole or any other third-party tool**: it only calls what macOS
ships (`du`, `pmset`, `launchctl`, `osascript`, ...), plus Homebrew when you
have it, and only to uninstall an app you installed through it.

### How Status reads the system

Each metric comes from a standard macOS tool, parsed in the data layer. Every
call is timeout-bounded, and a probe that fails leaves its own card blank
instead of blanking the dashboard.

| Metric | Source |
|---|---|
| Host / uptime | `sysctl -n kern.boottime`, `sw_vers`, `hostname` |
| CPU | `top -l 1 -n 0 -s 0`, `sysctl hw.physicalcpu hw.ncpu` |
| Memory | `vm_stat`, `sysctl -n hw.memsize` |
| Storage | `df -k` |
| Battery | `pmset -g batt` |
| Network | `netstat -ib` |

## Design

Hoopix follows Apple's HIG principles rather than stock Material or stock
macOS chrome: the type scale follows the HIG sizes, set in Manrope; a 4pt
spacing grid; hairline-bordered surfaces instead of heavy elevation; and a
full-height sidebar with the traffic lights floating over it. Manrope has no
tabular figures, so numbers that update live are laid out with `TabularText`
instead, which keeps the dashboard from wobbling.

The brand color is a **rose**, defined as a full ramp in
`core/theme/hoopix_colors.dart`. Status hues (green/gold/red) deliberately sit
*outside* the rose family so a threshold warning reads as a signal rather
than decoration.

All colors are semantic roles on a `ThemeExtension` (`context.palette.brand`),
so light and dark both resolve from one place.

## Develop

```bash
flutter pub get
flutter run -d macos
flutter analyze
flutter test
```

To build the release package (a `.dmg` and a `.zip` with checksums, ad hoc
signed, for this Mac's architecture only) into `build/dist`:

```bash
./scripts/build_macos_release.sh
```

The script builds one architecture at a time because Xcode 27's `lipo` rejects
the multi-architecture check Flutter 3.38 makes; see the comment at the top of
the script.

The macOS App Sandbox is disabled in `macos/Runner/*.entitlements`: a system
utility has to spawn `pmset`, `vm_stat`, and friends, and move or delete files
across your disk, which the sandbox forbids. That means Hoopix is distributed
outside the Mac App Store.

On first use, macOS asks for permission to let Hoopix control **System Events**
(to remove a login item) and **Finder** (to move an app to the Trash when a
password is required). Refusing System Events only leaves an app's login item
in place. Refusing Finder means apps that need a password to remove, such as
Mac App Store apps, cannot be uninstalled from Hoopix.
