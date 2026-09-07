# Verification

## Release 1.7.0

- Release build passes on Apple Silicon with Swift 6 command-line tools and macOS 27.
- 38 tests in 9 suites pass. Two obsolete recommendation-picker tests were removed with their unused implementation; five recovery tests were added.
- Recovery tests inject hardware and persistence: disconnect cancellation, failed brightness writes, opt-in wake restoration, resolution revert/disconnect cleanup, and actionable busy-Match feedback. They do not alter real displays or preference files.
- Other tests cover native scale/rotation calculations, HiDPI and refresh selection, bounded linked brightness, nonlinear matching, visual calibration, preference migration, favorites, and invalid/disconnected backend operations.
- Live UI verified: compact display controls, system text shortcut as primary setting, app reading size under Appearance, percentage-link status, and About version 1.7.0 (8).
- Installed bundle verified at `~/Applications/Display Wizard.app`; only that process was running. Installer verifies a staged copy before replacing the destination. Existing user preferences were preserved.
- Previous live checks verified Default/Largest text layouts, preset editing/cancel, exact-resolution menus, Dell 1.5× with successful revert, and estimated brightness matching. Original brightness/resolution values were restored after those checks.

## Reproduce

```sh
bash scripts/test.sh
bash scripts/build.sh
```

The test script supplies Testing framework paths when needed by the command-line-only SDK. SDK linker search-path warnings can occur without full Xcode; they do not prevent a successful build.

## Physical checks still requiring hardware interaction

Automated recovery coverage simulates unplugging and wake events. A physical cable reconnect and full sleep/wake cycle were not performed in this final pass. Repeat those checks after macOS, connection, or hardware changes. Optical brightness equality requires visual calibration or a colorimeter; screenshots cannot verify emitted luminance.

## UI design

The main view keeps brightness and scale actions visible. Secondary settings use native menus with generous triggers. Reading-size changes reflow the grid, while the footer remains fixed. Semantic colors follow macOS appearance. Native menu and segmented-control typography is managed by macOS.

## Memory optimization — 1.8.0

40 tests pass, including deferred profile loading for ordinary use and immediate loading when saved matching requires it. The UI session survives destruction/recreation of its host; settings-page restoration was verified live.

Local `vmmap -summary` spot measurements on the same Mac and two displays:

| State | Physical footprint |
| --- | --- |
| Original 1.7.0 process, already used for about 30 minutes | 49.4 MB |
| Updated 1.8.0, dropdown open | 32.1 MB |
| Updated 1.8.0, dropdown closed | 30.7 MB |

These are observed snapshots, not a controlled long-duration benchmark. SwiftUI's AttributeGraph allocation count returns to zero after closing. Matching was off: using Match or restoring a matched configuration loads the additional matching framework and increases memory. macOS retains some shared/framework caches; RSS includes shared pages and differs from physical footprint.

The app now creates its hosting controller only on demand, releases it on close, retains only the small editing session, releases dismissed HUD content, drains hardware autorelease pools, and requests reclamation of unused allocator pages after a short idle delay. No display hardware settings changed during this pass.
