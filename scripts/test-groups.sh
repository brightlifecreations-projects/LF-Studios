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
SERIAL='VideoLibraryFavouritesTests|VideoKeymapSettingsTests|RecordingEngineIntegrationTests|EditorMemoryValidationTests|VideoTimelineInteractionTests|VideoEditorLifecycleTests|VideoEditorDiscoverabilityTests|VideoInspectorLayoutTests|VideoPerformanceTests|VideoPreviewPerformanceTests|VideoLongProjectPerformanceTests|VideoLongTakeTests|RecordingFrameTests|VideoDockTests|VideoFloatingPanelTests|VideoAgentTests|VideoAIAssistantTests|VideoAIKeysTests|VideoEditorBasicsTests|VideoLongTimelineTests'

# Tests that put real windows on screen or record it: they run one class at
# a time too (with SERIAL), so WindowServer never has several test processes
# drawing at once.
UI='Audit123Tests|VideoAgentLimitsTests|VideoTranscriptTests|CaptureLocalizationTests|VideoEditingPowerTests|RecordingHUDTests|CaptureChromeTests|VideoTimelineSnappingTests|AnnotationCanvasInteractionTests|VideoPreviewInteractionTests|RecordingBarTests|RecordingSafetyTests'
SERIAL="$SERIAL|$UI"
# Every screenshot class, for test-full.sh: each runs alone under the
# memory kill-switch (they draw big editor windows).
snapshot_classes() {
    grep -ho 'class [A-Za-z0-9]*SnapshotTests' Tests/LFStudiosCoreTests/Snapshots/*.swift | awk '{print $2}' | sort -u | paste -sd'|' -
}

# At most this many test processes at once (LF_TEST_WORKERS overrides):
# more overloads WindowServer on a 16 GB Mac (it panicked with more).
WORKERS="${LF_TEST_WORKERS:-1}"
# Compile jobs for the build step (LF_BUILD_JOBS overrides).
BUILD_JOBS="${LF_BUILD_JOBS:-2}"

# The load guard. Every 10 s while tests run it checks memory pressure,
# WindowServer's CPU, and that WindowServer still answers (it asks for the
# window list; a 5 s wait counts as no answer). Critical memory pressure,
# WindowServer above 80 % for 30 s, or no answer twice in a row: it stops
# the tests and closes every test process, logs it, does NOT run that part
# again, and waits until memory pressure has been normal for 2 minutes
# before the next part. Warning pressure pauses before each part until it
# drops. Log: .build/test-guard.log.
GUARD_LOG="${GUARD_LOG:-$PWD/.build/test-guard.log}"
TRIPPED="${TMPDIR:-/tmp}/lfstudios-test-guard-tripped"

guard_log() {
    mkdir -p "$(dirname "$GUARD_LOG")"
    echo "$(date '+%F %T') $*" | tee -a "$GUARD_LOG" >&2
}
pressure() { sysctl -n kern.memorystatus_vm_pressure_level; }

# True when WindowServer hands over its window list within 5 s.
windowserver_answers() {
    perl -e 'alarm 5; exec @ARGV' osascript -l JavaScript -e 'ObjC.import("CoreGraphics"); $.CGWindowListCopyWindowInfo(0, 0); ""' >/dev/null 2>&1
}

# Waits until memory pressure is normal and has stayed so for $1 seconds.
wait_normal() {
    local need="${1:-0}" calm=0 said=""
    while :; do
        if [ "$(pressure)" -le 1 ]; then
            [ "$calm" -ge "$need" ] && return 0
            calm=$((calm + 10))
        else
            calm=0
            [ -n "$said" ] || { guard_log "memory pressure level $(pressure) (2 warning, 4 critical): waiting until it is normal"; said=1; }
        fi
        sleep 10
    done
}

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

# A test process that has used no CPU for 3 minutes is stuck (a prompt
# nobody answers, a wait that never ends): its stack goes to
# .build/test-stuck-*.txt and only that process is quit, so the run goes on.
STUCK_SECONDS="${LF_STUCK_SECONDS:-180}"
check_stuck() {
    local test cpu
    test=$(pgrep -f '\.xctest' | tail -1)
    [ -n "$test" ] || { idle=0; idle_pid=""; return; }
    [ "$test" = "$idle_pid" ] || { idle=0; idle_pid=$test; }
    cpu=$(ps -o %cpu= -p "$test" | tr -d ' ' | cut -d. -f1)
    if [ "${cpu:-1}" -eq 0 ]; then idle=$((idle + 10)); else idle=0; fi
    if [ "$idle" -ge "$STUCK_SECONDS" ]; then
        local stack
        stack="$(dirname "$GUARD_LOG")/test-stuck-$(date +%H%M%S).txt"
        sample "$test" 1 -file "$stack" >/dev/null 2>&1
        guard_log "stuck: $(ps -o command= -p "$test" | grep -oE '[A-Za-z0-9]+Tests(/[A-Za-z0-9_]+)?' | head -1) used no CPU for ${idle} s; quit it (stack: $stack)"
        kill -TERM "$test" 2>/dev/null
        idle=0
    fi
}

watch_load() {
    local pid="$1" hot=0 silent=0 server cpu level reason idle=0 idle_pid=""
    while kill -0 "$pid" 2>/dev/null; do
        sleep 10
        check_stuck
        reason=""
        level=$(pressure)
        server=$(pgrep -x WindowServer)
        cpu=0
        [ -n "$server" ] && cpu=$(top -l 2 -s 1 -pid "$server" -stats cpu | tail -1 | cut -d. -f1)
        if [ "${cpu:-0}" -gt "${LF_GUARD_CPU:-80}" ]; then hot=$((hot + 10)); else hot=0; fi
        if windowserver_answers; then silent=0; else silent=$((silent + 1)); fi
        [ "${level:-1}" -ge 4 ] && reason="memory pressure critical"
        [ "$hot" -ge 30 ] && reason="WindowServer at ${cpu}% for ${hot} s"
        [ "$silent" -ge 2 ] && reason="WindowServer didn't answer twice in a row"
        if [ -n "$reason" ]; then
            guard_log "guard stopped the tests: $reason (WindowServer ${cpu}%, memory pressure level ${level})"
            touch "$TRIPPED"
            pkill -TERM -P "$pid" 2>/dev/null
            kill -TERM "$pid" 2>/dev/null
            cleanup_tests
            return
        fi
    done
}

# The memory kill-switch, for every screenshot and UI test (run_serial).
# Every second it reads the test process's memory (top's MEM: what it holds,
# window and GPU surfaces included) and the Mac's swap; above 1.5 GB, or
# swap up 500 MB since the test started, it kills the test at once. Each
# test's peak goes to .build/test-memcap.log.
MEMCAP_MB="${LF_MEMCAP_MB:-1536}"
SWAPCAP_MB="${LF_SWAPCAP_MB:-500}"
MEMCAP_LOG="${MEMCAP_LOG:-$PWD/.build/test-memcap.log}"

footprint_mb() {
    top -l 1 -pid "$1" -stats mem 2>/dev/null | tail -1 | awk '{v=$1; u=substr(v,length(v)); n=v+0; if (u=="G") n*=1024; else if (u=="K" || u=="B") n/=1024; print int(n)}'
}
swap_mb() { sysctl -n vm.swapusage | awk '{gsub("M","",$6); print int($6)}'; }

# memcap <label> <command...>
memcap() {
    local label="$1" pid swap0 swap peak=0 mem=0 test code
    shift
    mkdir -p "$(dirname "$MEMCAP_LOG")"
    swap0=$(swap_mb)
    "$@" &
    pid=$!
    while kill -0 "$pid" 2>/dev/null; do
        test=$(pgrep -f '\.xctest' | tail -1)
        if [ -n "$test" ]; then
            mem=$(footprint_mb "$test")
            [ "${mem:-0}" -gt "$peak" ] && peak=$mem
        fi
        swap=$(swap_mb)
        if [ "${mem:-0}" -gt "$MEMCAP_MB" ] || [ $((swap - swap0)) -gt "$SWAPCAP_MB" ]; then
            pkill -KILL -f '\.xctest' 2>/dev/null
            kill -TERM "$pid" 2>/dev/null
            wait "$pid" 2>/dev/null
            echo "$(date '+%F %T') KILLED $label: test process ${mem} MB (peak ${peak} MB), swap +$((swap - swap0)) MB" | tee -a "$MEMCAP_LOG" >&2
            return 1
        fi
        sleep 1
    done
    wait "$pid"
    code=$?
    echo "$(date '+%F %T') $label: peak ${peak} MB, swap +$(( $(swap_mb) - swap0 )) MB, exit $code" >> "$MEMCAP_LOG"
    return "$code"
}

# Runs a test command under the load guard (never twice: a stopped part
# is reported as failed).
guarded() {
    local code pid watcher
    wait_normal 0
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
    if [ -f "$TRIPPED" ]; then
        guard_log "guard: '$*' stopped and not run again; waiting for 2 calm minutes"
        wait_normal 120
        return 1
    fi
    return "$code"
}

# Classes from a list ("A|B|C") one at a time, each under the guard, with
# a short pause between them so each one's windows are gone before the next.
run_serial() {
    local ok=0 class
    for class in ${1//|/ }; do
        guarded memcap "$class" swift test --skip-build --filter "\\.$class/" || ok=1
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
