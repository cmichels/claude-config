#!/usr/bin/env bash
# WSL2 dev environment preflight check
# Run when something feels off before spending time debugging
#
# Usage:
#   claude-preflight.sh              # Full manual preflight (all hardcoded checks)
#   claude-preflight.sh --once       # Registry-driven, skip if already ran this session
#   claude-preflight.sh --registry   # Registry-driven checks only
#   claude-preflight.sh --diagnose "error message"  # Search registry for matching fix

set -euo pipefail

REGISTRY="${HOME}/.claude/friction-registry.yaml"
MARKER="/tmp/claude-preflight-ran"
MARKER_TTL=14400  # 4 hours in seconds

PASS=0
FAIL=0
FIXED=0
WARNINGS=()

# --- Output helpers ---

check() {
    local label="$1"
    local result="$2"
    local detail="${3:-}"
    if [ "$result" = "ok" ]; then
        echo "  [PASS] $label"
        PASS=$((PASS + 1))
    elif [ "$result" = "fixed" ]; then
        echo "  [AUTO-FIXED] $label — $detail"
        FIXED=$((FIXED + 1))
    else
        echo "  [FAIL] $label — $detail"
        FAIL=$((FAIL + 1))
        WARNINGS+=("$label: $detail")
    fi
}

# --- Marker logic for --once ---

marker_is_fresh() {
    [ -f "$MARKER" ] || return 1
    local age
    age=$(( $(date +%s) - $(stat -c '%Y' "$MARKER") ))
    [ "$age" -lt "$MARKER_TTL" ]
}

touch_marker() {
    touch "$MARKER"
}

# --- Registry-driven checks ---

run_registry() {
    if [ ! -f "$REGISTRY" ]; then
        echo "  No friction registry found at $REGISTRY"
        return
    fi

    if ! command -v yq >/dev/null 2>&1; then
        echo "  yq not found — cannot parse friction registry"
        return
    fi

    local count
    count=$(yq '.issues | length' "$REGISTRY")

    for ((i=0; i<count; i++)); do
        local id desc detect fix auto_fix critical message
        id=$(yq -r ".issues[$i].id" "$REGISTRY")
        desc=$(yq -r ".issues[$i].description" "$REGISTRY")
        detect=$(yq -r ".issues[$i].detect" "$REGISTRY")
        fix=$(yq -r ".issues[$i].fix // \"\"" "$REGISTRY")
        auto_fix=$(yq -r ".issues[$i].auto_fix" "$REGISTRY")
        critical=$(yq -r ".issues[$i].critical // \"false\"" "$REGISTRY")
        message=$(yq -r ".issues[$i].message // \"\"" "$REGISTRY")

        if eval "$detect" >/dev/null 2>&1; then
            check "$id" "ok"
        elif [ "$auto_fix" = "true" ] && [ -n "$fix" ]; then
            if eval "$fix" >/dev/null 2>&1; then
                check "$id" "fixed" "$desc"
            else
                check "$id" "fail" "auto-fix failed: $desc"
            fi
        else
            local detail="${message:-$desc}"
            check "$id" "fail" "$detail"
        fi
    done
}

# --- Diagnose mode ---

run_diagnose() {
    local error_msg="$1"

    if [ ! -f "$REGISTRY" ] || ! command -v yq >/dev/null 2>&1; then
        echo "Cannot diagnose: registry or yq not available"
        exit 1
    fi

    echo ""
    echo "Diagnosing: $error_msg"
    echo ""

    local count matched=0
    count=$(yq '.issues | length' "$REGISTRY")

    for ((i=0; i<count; i++)); do
        local id desc fix auto_fix message
        id=$(yq -r ".issues[$i].id" "$REGISTRY")
        desc=$(yq -r ".issues[$i].description" "$REGISTRY")
        fix=$(yq -r ".issues[$i].fix // \"\"" "$REGISTRY")
        auto_fix=$(yq -r ".issues[$i].auto_fix" "$REGISTRY")
        message=$(yq -r ".issues[$i].message // \"\"" "$REGISTRY")

        if echo "$desc $message $id" | grep -qi "$error_msg"; then
            matched=$((matched + 1))
            echo "  Match: $id — $desc"
            if [ -n "$fix" ]; then
                echo "  Fix: $fix"
                if [ "$auto_fix" = "true" ]; then
                    echo "  (auto-fixable)"
                fi
            elif [ -n "$message" ]; then
                echo "  Note: $message"
            fi
            echo ""
        fi
    done

    if [ "$matched" -eq 0 ]; then
        echo "  No matching issues found in registry."
    fi
}

# --- Hardcoded checks (original preflight) ---

run_hardcoded() {
    # 1. gpg-agent running
    if gpg-connect-agent --no-autostart 'getinfo version' /bye &>/dev/null; then
        check "gpg-agent running" "ok"
    else
        check "gpg-agent running" "fail" "start with: gpg-agent --daemon"
    fi

    # 2. pinentry-mode loopback in gpg.conf
    if grep -q 'pinentry-mode loopback' ~/.gnupg/gpg.conf 2>/dev/null; then
        check "pinentry-mode loopback (gpg.conf)" "ok"
    else
        check "pinentry-mode loopback (gpg.conf)" "fail" "add to ~/.gnupg/gpg.conf: pinentry-mode loopback"
    fi

    # 3. allow-loopback-pinentry in gpg-agent.conf
    if grep -q 'allow-loopback-pinentry' ~/.gnupg/gpg-agent.conf 2>/dev/null; then
        check "allow-loopback-pinentry (gpg-agent.conf)" "ok"
    else
        check "allow-loopback-pinentry (gpg-agent.conf)" "fail" "add to ~/.gnupg/gpg-agent.conf: allow-loopback-pinentry"
    fi

    # 4. git GPG signing configured
    signing_key=$(git config --global user.signingkey 2>/dev/null || true)
    gpg_sign=$(git config --global commit.gpgsign 2>/dev/null || true)
    if [ -n "$signing_key" ] && [ "$gpg_sign" = "true" ]; then
        check "git GPG signing config" "ok"
    else
        check "git GPG signing config" "fail" "signingkey='$signing_key' commit.gpgsign='$gpg_sign'"
    fi

    # 5. win32yank on PATH (clipboard bridging)
    if command -v win32yank.exe &>/dev/null; then
        check "win32yank (clipboard)" "ok"
    else
        check "win32yank (clipboard)" "fail" "not found on PATH — clipboard bridging broken"
    fi

    # 6. fzf resolves to non-system binary (PATH ordering)
    fzf_path=$(command -v fzf 2>/dev/null || true)
    if [ -z "$fzf_path" ]; then
        check "fzf PATH" "fail" "fzf not found"
    elif echo "$fzf_path" | grep -q '^/usr/bin/fzf'; then
        check "fzf PATH (non-system)" "fail" "resolves to system fzf at $fzf_path — prepend user install to PATH"
    else
        check "fzf PATH (non-system)" "ok"
    fi

    # 7. Docker daemon accessible
    if docker info &>/dev/null 2>&1; then
        check "Docker daemon" "ok"
    else
        check "Docker daemon" "fail" "not running or credentials misconfigured"
    fi

    # 8. GPG can actually sign (passphrase cache warm)
    test_sig=$(echo "preflight-test" | gpg --clearsign 2>&1)
    if echo "$test_sig" | grep -q 'BEGIN PGP SIGNED MESSAGE'; then
        check "GPG passphrase cache (can sign)" "ok"
    else
        check "GPG passphrase cache (can sign)" "fail" "run: echo test | gpg --clearsign  (to warm cache)"
    fi
}

# --- Main ---

case "${1:-}" in
    --once)
        if marker_is_fresh; then
            exit 0
        fi
        echo ""
        echo "PREFLIGHT (registry)"
        echo "===================="
        run_registry
        echo ""
        if [ "$FIXED" -gt 0 ] || [ "$FAIL" -gt 0 ]; then
            echo "$PASS passed, $FIXED auto-fixed, $FAIL failed"
        fi
        touch_marker
        # Always exit 0 — advisory only, never block Claude
        exit 0
        ;;
    --registry)
        echo ""
        echo "PREFLIGHT (registry)"
        echo "===================="
        run_registry
        echo ""
        echo "$PASS passed, $FIXED auto-fixed, $FAIL failed"
        [ $FAIL -gt 0 ] && exit 1 || exit 0
        ;;
    --diagnose)
        if [ -z "${2:-}" ]; then
            echo "Usage: claude-preflight.sh --diagnose \"error message\""
            exit 1
        fi
        run_diagnose "$2"
        exit 0
        ;;
    "")
        echo ""
        echo "WSL2 Preflight Check"
        echo "===================="
        run_hardcoded
        echo ""
        echo "Result: $PASS passed, $FAIL failed"
        echo ""
        [ $FAIL -gt 0 ] && exit 1 || exit 0
        ;;
    *)
        echo "Usage: claude-preflight.sh [--once|--registry|--diagnose \"msg\"]"
        exit 1
        ;;
esac
