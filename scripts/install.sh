#!/bin/bash
set -euo pipefail
cd "$(dirname "$0")/.."
# One stable path keeps Launch at Login registration and updates predictable.
source_app="$PWD/build/Display Wizard.app"
apps_dir="$HOME/Applications"
installed_app="$apps_dir/Display Wizard.app"
if pgrep -x DisplayWizard >/dev/null; then
    echo 'Quit Display Wizard from its app menu before installing.' >&2
    exit 1
fi
[[ -d "$source_app" ]] || { echo "Build the app first." >&2; exit 1; }
mkdir -p "$apps_dir"
staging_dir="$(mktemp -d "$apps_dir/.display-wizard-install.XXXXXX")"
trap 'rm -rf "$staging_dir"' EXIT
ditto "$source_app" "$staging_dir/Display Wizard.app"
xattr -cr "$staging_dir/Display Wizard.app"
codesign --verify --deep --strict "$staging_dir/Display Wizard.app"
if [[ -e "$installed_app" ]]; then
    mv "$installed_app" "$staging_dir/previous.app"
fi
if ! mv "$staging_dir/Display Wizard.app" "$installed_app"; then
    if [[ -d "$staging_dir/previous.app" ]]; then mv "$staging_dir/previous.app" "$installed_app"; fi
    exit 1
fi
printf 'Installed %s\nPreferences preserved in Application Support/DisplayWizard.\n' "$installed_app"
