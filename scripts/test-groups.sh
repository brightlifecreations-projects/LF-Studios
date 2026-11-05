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
#   VideoEditorDiscoverabilityTests, VideoInspectorLayoutTests,
#   VideoLibraryFavouritesTests, VideoKeymapSettingsTests — change settings
#   every test process shares (UserDefaults.standard).
#   VideoPerformanceTests, VideoLongProjectPerformanceTests,
#   VideoLongTakeTests — check how fast exports and
#   long edits are; with other tests using the Mac they miss their limits.
#   RecordingFrameTests — puts the frame bar on the real screen and asks
#   the window server what a click hits; another test's window would be
#   in the way. It also takes the ⌃⌘Esc shortcut.
#   VideoDockTests, VideoFloatingPanelTests — the panel layout is a setting
#   every test process shares, and floating panels are real windows.
#   VideoAgentTests — the agent connection's switch, token and port are
#   shared settings, and it serves on this Mac.
#   VideoAIAssistantTests, VideoAIKeysTests — the AI provider, model and
#   frames switches are shared settings, and they swap the key store.
#   VideoEditorBasicsTests — uses the clipboard and plays in real time.
SNAPSHOTS='SnapshotTests'
SERIAL='VideoLibraryFavouritesTests|VideoKeymapSettingsTests|RecordingEngineIntegrationTests|EditorMemoryValidationTests|VideoTimelineInteractionTests|VideoEditorLifecycleTests|VideoEditorDiscoverabilityTests|VideoInspectorLayoutTests|VideoPerformanceTests|VideoLongProjectPerformanceTests|VideoLongTakeTests|RecordingFrameTests|VideoDockTests|VideoFloatingPanelTests|VideoAgentTests|VideoAIAssistantTests|VideoAIKeysTests|VideoEditorBasicsTests|VideoLongTimelineTests'

# Tests that put real windows on screen or record it: they run one class at
# a time too (with SERIAL), so WindowServer never has several test processes
# drawing at once. SCREEN_SNAPSHOTS: screenshot tests that need a real
# window (the recording bar, the Area popover); test-full.sh runs them alone.
UI='VideoTranscriptTests|CaptureLocalizationTests|VideoEditingPowerTests|RecordingHUDTests|CaptureChromeTests|VideoTimelineSnappingTests|AnnotationCanvasInteractionTests|VideoPreviewInteractionTests|RecordingBarTests|RecordingSafetyTests'
SERIAL="$SERIAL|$UI"
SCREEN_SNAPSHOTS='Reference1211SnapshotTests|VideoEditor121SnapshotTests'

# At most this many test processes at once (LF_TEST_WORKERS overrides):
# more overloads WindowServer on a 16 GB Mac (it panicked with the default).
WORKERS="${LF_TEST_WORKERS:-2}"

# The load guard. Every 10 s while tests run it checks WindowServer's CPU
# and the Mac's memory pressure; when WindowServer stays above 80 % for 30 s
# or memory pressure is critical it stops the tests, logs it, waits 2
# minutes, closes every test process, and runs that part again (up to 3
# times). Log: .build/test-guard.log.
GUARD_LOG="${GUARD_LOG:-$PWD/.build/test-guard.log}"
TRIPPED="${TMPDIR:-/tmp}/lfstudios-test-guard-tripped"

# Quits whatever tests left behind: test runners (their windows and capture
# streams go with them), the MCP helper, and test copies of LF Studios
# (anything but the installed app).
cleanup_tests() {
    pkill -TERM -f '\.xctest' 2>/dev/null
    pkill -TERM -f 'swiftpm-testing-helper' 2>/dev/null
    pkill -TERM -f 'lfstudios-mcp' 2>/dev/null
    pgrep -f 'Contents/MacOS/LFStudios' | while read -r pid; do
        ps -o command= -p "$pid" | grep -q '^/Applications/LF Studios.app/' || kill "$pid" 2>/dev/null
    done
    sleep 1
    pkill -KILL -f '\.xctest' 2>/dev/null
    return 0
}

watch_load() {
    local pid="$1" hot=0 server cpu level
    while kill -0 "$pid" 2>/dev/null; do
        sleep 10
        server=$(pgrep -x WindowServer) || continue
        cpu=$(top -l 2 -s 1 -pid "$server" -stats cpu | tail -1 | cut -d. -f1)
        level=$(sysctl -n kern.memorystatus_vm_pressure_level)
        if [ "${cpu:-0}" -gt "${LF_GUARD_CPU:-80}" ]; then hot=$((hot + 10)); else hot=0; fi
        if [ "$hot" -ge 30 ] || [ "${level:-1}" -ge 4 ]; then
            mkdir -p "$(dirname "$GUARD_LOG")"
            echo "$(date '+%F %T') guard stopped the tests: WindowServer ${cpu}% (hot ${hot} s), memory pressure level ${level} (4 = critical)" | tee -a "$GUARD_LOG" >&2
            touch "$TRIPPED"
            pkill -TERM -P "$pid" 2>/dev/null
            kill -TERM "$pid" 2>/dev/null
            cleanup_tests
            return
        fi
    done
}

# Runs a test command under the load guard.
guarded() {
    local tries=0 code pid watcher
    while :; do
        rm -f "$TRIPPED"
        "$@" &
        pid=$!
        watch_load "$pid" &
        watcher=$!
        wait "$pid"
        code=$?
        [ -f "$TRIPPED" ] || kill "$watcher" 2>/dev/null
        wait "$watcher" 2>/dev/null
        cleanup_tests
        [ -f "$TRIPPED" ] || return "$code"
        tries=$((tries + 1))
        if [ "$tries" -ge 3 ]; then
            echo "$(date '+%F %T') guard: gave up on '$*' after 3 stops" | tee -a "$GUARD_LOG" >&2
            return 1
        fi
        echo "$(date '+%F %T') guard: waiting 2 minutes, then running it again" | tee -a "$GUARD_LOG" >&2
        sleep 120
        cleanup_tests
    done
}

# Classes from a list ("A|B|C") one at a time, each under the guard, with
# a short pause between them so each one's windows are gone before the next.
run_serial() {
    local ok=0 class
    for class in ${1//|/ }; do
        guarded swift test --skip-build --filter "\\.$class/" || ok=1
        sleep 3
    done
    return $ok
}

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
