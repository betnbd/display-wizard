# Display Wizard

A compact native macOS menu-bar utility for display brightness and scaling. Requires Apple Silicon, macOS 14 or later, and Swift 6 command-line tools to build.

## Everyday controls

- Hardware brightness for the built-in display and compatible external monitors.
- Scale buttons based on native panel pixels. Approximate values reflect available macOS modes; exact resolutions and percentages are in each display’s **⋯** menu.
- **Link brightness** preserves percentage-point offsets. **Match** estimates comparable brightness on supported displays, then links their brightness curves. **Fine-tune** saves a visual calibration. Status distinguishes offsets, estimates, calibration, and paused linking.
- **Brightness presets** saves and applies named per-display brightness values.
- **Control–Option–Up/Down** adjusts brightness on the display under the pointer, with a small feedback overlay.
- Display **⋯** menus include resolution favorites, refresh rate, main-display selection, and a shortcut for rotation.
- Resolution changes require confirmation within 15 seconds or revert automatically.

Settings offers **System text size…**, opening macOS Accessibility → Display for compatible apps and system features. **Appearance** contains Display Wizard’s own reading size. Login launch and wake/reconnect brightness restoration are opt-in.

## Build, test, and install

```sh
bash scripts/build.sh
bash scripts/test.sh
# Quit Display Wizard using its app menu before installing or updating.
bash scripts/install.sh
open "$HOME/Applications/Display Wizard.app"
```

The installer uses one stable location, `~/Applications/Display Wizard.app`, verifies the new bundle before replacing the old one, and leaves preferences untouched. A second launched copy exits instead of creating another hardware controller. The app menu includes About and the current version.

Preferences are stored in `~/Library/Application Support/DisplayWizard/preferences.json`. Upgrades migrate older files while retaining presets, favorites, calibration, and reading size. The build output is ad-hoc signed for local use, not Developer ID signed or notarized for distribution.

## Implementation

SwiftUI views are separated into the main dropdown, display card, and settings. Shared typography follows the app’s reading size and macOS appearance. `AppModel` coordinates display lifecycle, writes, previews, and persistence. Its injectable service boundary supports simulated recovery tests. `HardwareService` serializes blocking hardware traffic off the main thread. Pure helpers calculate scale choices, linked offsets, and estimated brightness targets.

`DisplayBackend` uses CoreGraphics, private DisplayServices interfaces, and the bundled MIT-licensed [m1ddc](https://github.com/waydabber/m1ddc) helper. Vendor source and license are retained in `Vendor/m1ddc`; generated helper binaries and build caches are excluded from Git. Artwork provenance is in `Assets/README.md`.

## Limits

Brightness matching is an estimate, not an optical measurement. The Mac profile uses its active SDR range and native linear brightness reading; the Dell U2725QE profile uses a nominal 450-nit maximum. Visual calibration improves the match but ambient light, HDR, automatic brightness, and monitor picture settings can change perception. Unsupported displays retain independent controls.

DDC support depends on the monitor and connection. The app does not create custom modes, virtual displays, HDR boosts, or software dimming overlays. System text sizing only affects apps and features that support the macOS setting.

See [verification notes](docs/TESTING.md). The compact controls take inspiration from [Omarchy’s monitor panel](https://github.com/basecamp/omarchy/blob/quattro/shell/plugins/panels/monitor/Panel.qml).
