#!/bin/bash
# Cross-repo gate for ForgeLoopTUI + ForgeLoop collaboration
# Usage:
#   ./Scripts/cross-repo-gate.sh --quick
#   ./Scripts/cross-repo-gate.sh --full
#   FORGELOOP_ROOT=/abs/path/to/ForgeLoop ./Scripts/cross-repo-gate.sh --full

set -euo pipefail

MODE="quick"
if [[ "${1:-}" == "--full" ]]; then
    MODE="full"
elif [[ "${1:-}" == "--quick" || "${1:-}" == "" ]]; then
    MODE="quick"
else
    echo "Unknown option: ${1:-}"
    echo "Usage: ./Scripts/cross-repo-gate.sh [--quick|--full]"
    exit 2
fi

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
TUI_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"
FORGELOOP_ROOT="${FORGELOOP_ROOT:-$(cd "$TUI_ROOT/../ForgeLoop" && pwd)}"

PASS=0
FAIL=0

log_pass() { echo "  [PASS] $1"; PASS=$((PASS + 1)); }
log_fail() { echo "  [FAIL] $1"; FAIL=$((FAIL + 1)); }

run_step() {
    local label="$1"
    local cwd="$2"
    local cmd="$3"
    echo ""
    echo "[gate] $label"
    echo "       (cd $cwd && $cmd)"
    if (cd "$cwd" && eval "$cmd"); then
        log_pass "$label"
    else
        log_fail "$label"
    fi
}

echo "=== Cross-Repo Gate (${MODE}) ==="
echo "TUI root:       $TUI_ROOT"
echo "ForgeLoop root: $FORGELOOP_ROOT"

if [[ ! -f "$TUI_ROOT/Package.swift" ]]; then
    echo "Invalid ForgeLoopTUI root: $TUI_ROOT"
    exit 2
fi
if [[ ! -f "$FORGELOOP_ROOT/Package.swift" ]]; then
    echo "Invalid ForgeLoop root: $FORGELOOP_ROOT"
    exit 2
fi

run_step "ForgeLoopTUI build" "$TUI_ROOT" "swift build"
run_step "ForgeLoopTUI integration gate" "$TUI_ROOT" "swift test --filter CapabilityEndToEndTests"
run_step "ForgeLoopTUI Public API smoke gate" "$TUI_ROOT" "swift test --filter PublicAPISmokeTests"

run_step "ForgeLoop build" "$FORGELOOP_ROOT" "swift build"
run_step "ForgeLoop ScreenLayout integration gate" "$FORGELOOP_ROOT" "swift test --filter ScreenLayoutIntegrationTests"

if [[ "$MODE" == "full" ]]; then
    run_step "ForgeLoop performance baseline gate" "$FORGELOOP_ROOT" "swift test --filter PerformanceBaselineTests"
    run_step "ForgeLoop performance regression gate" "$FORGELOOP_ROOT" "swift test --filter PerformanceGateTests"
fi

echo ""
echo "=== Summary ==="
echo "  PASS: $PASS"
echo "  FAIL: $FAIL"

if [[ "$FAIL" -gt 0 ]]; then
    echo "Result: FAIL"
    exit 1
fi

echo "Result: PASS"
