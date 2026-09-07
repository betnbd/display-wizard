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
