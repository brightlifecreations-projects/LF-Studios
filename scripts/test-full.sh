#!/usr/bin/env bash
# Every test, screenshot tests included — run once before publishing a
# release (while working, scripts/test-quick.sh is enough).
#
#   bash scripts/test-full.sh
#
# Needs full Xcode (XCTest). Groups: scripts/test-groups.sh.
set -uo pipefail
cd "$(dirname "$0")/.."
source scripts/test-groups.sh

total=$SECONDS
clear_test_storage
step "Build" swift build --build-tests -j "$BUILD_JOBS"
if [ "$FAILED" -eq 0 ]; then
    step "Tests in parallel (no screenshots)" guarded swift test --skip-build --parallel --num-workers "$WORKERS" --skip "$SNAPSHOTS|$SERIAL"
    step "Tests that run alone" run_serial "$SERIAL"
    step "Screenshot tests, one class at a time" run_serial "$(snapshot_classes)"
fi
echo
if [ "$FAILED" -eq 0 ]; then
    echo "✓ All tests passed in $((SECONDS - total)) s"
else
    echo "✗ Some tests failed ($((SECONDS - total)) s) — see above"
fi
cleanup_tests
exit "$FAILED"
