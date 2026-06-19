#!/bin/bash
# =============================================================================
# Codex CLI Intel Mac SIGTRAP Fix
# =============================================================================
# Fixes the "trace trap" / SIGTRAP crash of OpenAI Codex CLI on Intel Macs.
#
# Root cause: the distributed x86_64 binary has an invalid entitlements blob
# that macOS ignores, so V8 fails to allocate executable memory and the process
# gets killed with EXC_BREAKPOINT (SIGTRAP).
#
# This script re-signs the binary with the correct entitlements:
#   - com.apple.security.cs.allow-jit
#   - com.apple.security.cs.allow-unsigned-executable-memory
#
# Solution source: https://github.com/openai/codex/issues/27358
# Related issues:
#   - https://github.com/openai/codex/issues/29000
#   - https://github.com/openai/codex/issues/27862
#   - https://github.com/openai/codex/issues/28893
# =============================================================================

set -euo pipefail

RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[0;33m'
NC='\033[0m' # No Color

log_info()  { echo -e "${GREEN}[INFO]${NC}  $*"; }
log_warn()  { echo -e "${YELLOW}[WARN]${NC}  $*"; }
log_error() { echo -e "${RED}[ERROR]${NC} $*"; }

# ---- Config ----------------------------------------------------------------
RELEASES_DIR="${HOME}/.codex/packages/standalone/releases"
ENTITLEMENTS_FILE="/tmp/codex-jit.entitlements"

# ---- Ensure entitlements plist exists -------------------------------------
ensure_entitlements() {
    if [[ -f "${ENTITLEMENTS_FILE}" ]]; then
        return
    fi
    log_info "Creating entitlements file..."
    cat > "${ENTITLEMENTS_FILE}" << 'EOF'
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
    <key>com.apple.security.cs.allow-jit</key>
    <true/>
    <key>com.apple.security.cs.allow-unsigned-executable-memory</key>
    <true/>
</dict>
</plist>
EOF
}

# ---- Check if a binary needs re-signing -----------------------------------
needs_resign() {
    local binary="$1"
    # Check if both entitlements are present
    local ents
    ents=$(codesign -d --entitlements - "$binary" 2>/dev/null || true)
    if [[ -z "$ents" ]]; then
        # Can't read entitlements — needs resign
        return 0
    fi
    # Check for the missing entitlement
    if ! echo "$ents" | grep -q "allow-unsigned-executable-memory"; then
        return 0
    fi
    if ! echo "$ents" | grep -q "allow-jit"; then
        return 0
    fi
    return 1
}

# ---- Re-sign a single binary ----------------------------------------------
resign_binary() {
    local binary="$1"
    log_info "Re-signing: ${binary}"
    codesign --force --sign - --entitlements "${ENTITLEMENTS_FILE}" "$binary"
    log_info "Done: both entitlements now active"
}

# ---- Print current entitlements -------------------------------------------
show_entitlements() {
    local binary="$1"
    echo ""
    log_info "Current entitlements for: ${binary}"
    codesign -d --entitlements - "$binary" 2>&1 || true
    echo ""
}

# ---- Find Intel Mac releases ----------------------------------------------
find_intel_binaries() {
    for dir in "${RELEASES_DIR}"/*-x86_64-apple-darwin; do
        if [[ -d "$dir" ]] && [[ -f "$dir/bin/codex" ]]; then
            echo "$dir/bin/codex"
        fi
    done
}

# ---- Main -----------------------------------------------------------------
main() {
    echo ""
    echo "╔══════════════════════════════════════════════════════════╗"
    echo "║   Codex CLI Intel Mac SIGTRAP Fix                      ║"
    echo "║   https://github.com/openai/codex/issues/27358         ║"
    echo "╚══════════════════════════════════════════════════════════╝"
    echo ""

    # Check we're on macOS
    if [[ "$(uname)" != "Darwin" ]]; then
        log_error "This fix only applies to macOS."
        exit 1
    fi

    # Check we're on Intel
    local arch
    arch=$(uname -m)
    if [[ "$arch" != "x86_64" ]]; then
        log_warn "This machine is ${arch}, not x86_64. The SIGTRAP bug is Intel-specific."
        log_warn "If you're not experiencing crashes, no fix is needed."
        read -rp "Continue anyway? [y/N] " yn
        if [[ ! "$yn" =~ ^[Yy] ]]; then
            exit 0
        fi
    fi

    # Find Codex install
    if [[ ! -d "${RELEASES_DIR}" ]]; then
        log_error "Codex releases directory not found: ${RELEASES_DIR}"
        log_error "Is Codex CLI installed?"
        exit 1
    fi

    ensure_entitlements

    local binaries
    binaries=$(find_intel_binaries)

    if [[ -z "$binaries" ]]; then
        log_error "No Intel Codex binaries found in ${RELEASES_DIR}"
        exit 1
    fi

    local fixed=0
    local already=0

    while IFS= read -r binary; do
        if needs_resign "$binary"; then
            resign_binary "$binary"
            show_entitlements "$binary"
            fixed=$((fixed + 1))
        else
            log_info "Already OK: ${binary}"
            already=$((already + 1))
        fi
    done <<< "$binaries"

    echo ""
    echo "──────────────────────────────────────────────────────────"
    log_info "Summary: ${fixed} fixed, ${already} already OK"
    echo ""
    echo "Now try running:  codex"
    echo "If it still crashes, report at: https://github.com/openai/codex/issues"
    echo ""
}

main "$@"
