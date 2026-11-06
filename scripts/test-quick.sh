#!/usr/bin/env bash
# Every test except the slow screenshot tests, in parallel — for use while
# working. Before publishing a release, run scripts/test-full.sh once.
#
#   bash scripts/test-quick.sh
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
fi
echo
if [ "$FAILED" -eq 0 ]; then
    echo "✓ Quick tests passed in $((SECONDS - total)) s (screenshot tests skipped: scripts/test-full.sh runs them)"
else
    echo "✗ Some tests failed ($((SECONDS - total)) s) — see above"
fi
cleanup_tests
exit "$FAILED"
