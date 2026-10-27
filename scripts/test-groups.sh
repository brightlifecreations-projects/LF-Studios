# The test groups test-quick.sh and test-full.sh run (sourced, not run).
#
# SNAPSHOTS: the slow screenshot tests, Tests/LFStudiosCoreTests/Snapshots
# (every class there ends in SnapshotTests). They render the editor, the
# export sheet and more in every language. test-full.sh runs them,
# test-quick.sh skips them.
#
# SERIAL: tests that can't share the Mac with other tests at the same time,
# so they run one after another after the parallel part:
#   RecordingEngineIntegrationTests, EditorMemoryValidationTests,
#   VideoTimelineInteractionTests — record the real screen and windows;
#   another test's window on screen would end up in their recording.
#   VideoEditorLifecycleTests — uses the clipboard.
#   VideoEditorDiscoverabilityTests, VideoInspectorLayoutTests — change
#   settings every test process shares (UserDefaults.standard).
#   VideoPerformanceTests, VideoLongTakeTests — check how fast exports and
#   long edits are; with other tests using the Mac they miss their limits.
SNAPSHOTS='SnapshotTests'
SERIAL='RecordingEngineIntegrationTests|EditorMemoryValidationTests|VideoTimelineInteractionTests|VideoEditorLifecycleTests|VideoEditorDiscoverabilityTests|VideoInspectorLayoutTests|VideoPerformanceTests|VideoLongTakeTests'

# Each test process keeps its drafts and presets in a folder of its own
# in here (VideoTestStorage.swift); start each run with it empty.
clear_test_storage() {
    rm -rf "${TMPDIR:-/tmp}/lfstudios-test-storage"
}

# Runs one step, prints how long it took, and remembers a failure.
FAILED=0
step() {
    local title="$1"
    shift
    local start=$SECONDS
    echo "▶ $title"
    if "$@"; then
        echo "✓ $title — $((SECONDS - start)) s"
    else
        echo "✗ $title failed — $((SECONDS - start)) s"
        FAILED=1
    fi
}
