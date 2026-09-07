#!/bin/bash
set -euo pipefail
cd "$(dirname "$0")/.."

# Keep generated test bundles outside Documents, where Finder metadata can
# invalidate ad-hoc signatures. Swift 6.4 CLT needs explicit testing paths.
developer_dir="$(xcode-select -p)"
testing_root="$developer_dir/Library/Developer"
macro_library="$developer_dir/usr/lib/swift/host/plugins/testing/libTestingMacros.dylib"
arguments=(--disable-xctest --scratch-path "${TMPDIR:-/tmp}/display-wizard-test-build")
if [[ -f "$macro_library" ]]; then
    arguments+=(-Xswiftc -load-plugin-library -Xswiftc "$macro_library")
fi
if [[ -d "$testing_root/Frameworks/Testing.framework" ]]; then
    export DYLD_FRAMEWORK_PATH="$testing_root/Frameworks${DYLD_FRAMEWORK_PATH:+:$DYLD_FRAMEWORK_PATH}"
    export DYLD_LIBRARY_PATH="$testing_root/usr/lib${DYLD_LIBRARY_PATH:+:$DYLD_LIBRARY_PATH}"
fi
swift_binary="$(xcrun --find swift)"
"$swift_binary" test "${arguments[@]}" "$@"
