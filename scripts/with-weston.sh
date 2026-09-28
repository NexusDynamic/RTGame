#!/bin/sh
# Run a command against a private headless weston: the Wayland counterpart of
# xvfb-run, and the same display setup as the experiment's headless nodes
# (RiseTogether's headless-run.sh), minus the GPU. CI runners have none, so
# weston composites with pixman and the app renders through Mesa's llvmpipe.
#
# Usage:
#   scripts/with-weston.sh flutter test integration_test/real_webrtc_test.dart -d linux
#
# Environment:
#   RT_WESTON_RENDERER   weston renderer (default pixman; gl on a real GPU)

set -eu

[ $# -gt 0 ] || { echo "usage: $0 command [args...]" >&2; exit 2; }

RUNTIME_DIR=$(mktemp -d "${TMPDIR:-/tmp}/weston-runtime.XXXXXX")
chmod 700 "$RUNTIME_DIR"   # weston refuses a runtime dir others can read
SOCKET=wayland-risetogether
LOG="$RUNTIME_DIR/weston.log"
CONFIG=$(realpath "$(dirname "$0")/weston.ini")

# A fake seat keeps GDK from warning about a missing keyboard. Newer weston has
# it; older ones (Ubuntu 24.04 ships 13) refuse unknown options outright.
SEAT_OPT=
weston --help 2>&1 | grep -q -- --fake-seat && SEAT_OPT=--fake-seat

WESTON_PID=
cleanup() {
    status=$?
    if [ -n "$WESTON_PID" ]; then
        kill "$WESTON_PID" 2>/dev/null || true
        wait "$WESTON_PID" 2>/dev/null || true
    fi
    if [ "$status" -ne 0 ] && [ -s "$LOG" ]; then
        echo "--- weston log ---" >&2
        cat "$LOG" >&2
    fi
    rm -rf "$RUNTIME_DIR"
}
trap cleanup EXIT
trap 'exit 130' INT TERM

XDG_RUNTIME_DIR="$RUNTIME_DIR" weston -c "$CONFIG" --backend=headless \
    --renderer="${RT_WESTON_RENDERER:-pixman}" --socket="$SOCKET" $SEAT_OPT \
    > "$LOG" 2>&1 &
WESTON_PID=$!

# Wait for the socket rather than sleeping a fixed time.
tries=100
while [ ! -S "$RUNTIME_DIR/$SOCKET" ]; do
    kill -0 "$WESTON_PID" 2>/dev/null || { echo "weston exited early" >&2; exit 1; }
    tries=$((tries - 1))
    [ "$tries" -gt 0 ] || { echo "weston never created $SOCKET" >&2; exit 1; }
    sleep 0.1
done

# The command keeps the caller's XDG_RUNTIME_DIR: pipewire/pulse and the
# session bus live there, and libwebrtc's audio module needs them. It reaches
# weston through an absolute WAYLAND_DISPLAY instead. GDK_BACKEND and the
# unset DISPLAY stop GTK from silently falling back to X11.
unset DISPLAY
WAYLAND_DISPLAY="$RUNTIME_DIR/$SOCKET" GDK_BACKEND=wayland "$@"
