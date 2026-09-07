# m1ddc

Source: https://github.com/waydabber/m1ddc

Vendored revision: `04d949794102eb8df01ad3681afff6464a3eede2`

License: MIT; see LICENSE. Original code copyright © 2021 waydabber.

Display Wizard builds and bundles this Apple Silicon DDC helper to read and change external monitor hardware brightness. Sources are unmodified. The helper uses Apple's private interfaces; support depends on macOS, monitor DDC/CI support, and the physical display connection.

Build: `make -C Vendor/m1ddc`, then copy the resulting `m1ddc` executable to the app's `Contents/Resources/m1ddc`. Include LICENSE in the distributed app.
