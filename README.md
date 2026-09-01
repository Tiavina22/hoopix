# Hoopix

A free, open-source macOS maintenance app, built with Flutter.

Licensed under the [GNU GPLv3](LICENSE).

Hoopix is an alternative to the paid native Mac apps in this space: cleanup,
app management, maintenance, disk maps, and live system status in one place,
with the interface free and the source open.

> **Status: early.** Only the **Status** dashboard is functional today. Clean,
> Uninstall, Optimize, Analyze, and Purge appear in the sidebar as
> placeholders — they have no logic behind them yet, and nothing in the app
> currently deletes, moves, or modifies a single file on your Mac.

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
  features/
    status/
      data/                 # datasources (macOS CLI probes), models (parsers), repository impl
      domain/               # entities, repository interface, use cases
      presentation/         # controller, screen, widgets
```

Dependency direction is inward only: `presentation → domain ← data`. The data
layer is the only place allowed to touch `ProcessRunner`.

The engine is written from scratch in Dart — Hoopix has **no runtime
dependency** on any external CLI binary.

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
macOS chrome: San Francisco via `.AppleSystemUIFont`, a 4pt spacing grid,
tabular figures on every live number so the dashboard doesn't jitter,
hairline-bordered surfaces instead of heavy elevation, and a full-height
sidebar with the traffic lights floating over it.

The brand color is **peach**, defined as a full ramp in
`core/theme/hoopix_colors.dart`. Status hues (green/gold/red) deliberately sit
*outside* the peach family so a threshold warning reads as a signal rather
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

The macOS App Sandbox is disabled in `macos/Runner/*.entitlements`: a system
utility has to spawn `pmset`, `vm_stat`, and friends, which the sandbox
forbids. That means Hoopix is distributed outside the Mac App Store.
