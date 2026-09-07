#!/usr/bin/env bash
#
# Build the Canopy issuer hierarchy on Sepolia, end to end.
#
#   ./script/deploy-hierarchy.sh                 # deploy for real
#   ./script/deploy-hierarchy.sh --rehearse      # fork rehearsal, spends nothing
#   ./script/deploy-hierarchy.sh --verify        # just re-run the checks
#   ./script/deploy-hierarchy.sh --reset-broker  # re-arm the lapse between takes
#                                                # (ISSUER=acme BROKER=prime to pick one)
#
# The hierarchy is described declaratively in script/hierarchy.json — four levels, platform ->
# issuer -> broker -> investor. Add an issuer, a broker or a bootstrap investor there and re-run;
# only what is missing gets created. A broker onboarded by two issuers appears twice, under both.
#
# Safe to re-run. Every phase in DeployIssuerHierarchy.s.sol inspects on-chain state before acting,
# so an interrupted run resumes from where it stopped rather than duplicating work. If a phase
# fails, fix the cause and run this again — do not start over.
#
# The parent name is a once-per-year registration. Runs after the first skip the commit--reveal
# entirely, so iterating on the hierarchy costs seconds rather than a 60-second wait.
#
# The commit--reveal wait is the reason this exists: `register` is rejected until MIN_COMMITMENT_AGE
# has passed since `commit`, and that gap cannot happen inside a single broadcast.

set -euo pipefail

cd "$(dirname "${BASH_SOURCE[0]}")/.."

# ---------------------------------------------------------------------------
# Output
# ---------------------------------------------------------------------------

if [[ -t 1 ]]; then
    BOLD=$'\033[1m'; DIM=$'\033[2m'; RED=$'\033[31m'; GREEN=$'\033[32m'; YELLOW=$'\033[33m'; RESET=$'\033[0m'
else
    BOLD=''; DIM=''; RED=''; GREEN=''; YELLOW=''; RESET=''
fi

step()  { echo; echo "${BOLD}==> $*${RESET}"; }
info()  { echo "    $*"; }
warn()  { echo "${YELLOW}    ! $*${RESET}"; }
ok()    { echo "${GREEN}    ✓ $*${RESET}"; }
die()   { echo; echo "${RED}✗ $*${RESET}" >&2; exit 1; }

on_error() {
    echo
    echo "${RED}✗ failed at: ${CURRENT_PHASE:-preflight}${RESET}" >&2
    echo "  This script is resumable — fix the cause and run it again." >&2
    echo "  Completed phases are detected on-chain and skipped." >&2
}
trap on_error ERR

# ---------------------------------------------------------------------------
# Modes
# ---------------------------------------------------------------------------

MODE="deploy"
case "${1:-}" in
    --rehearse)     MODE="rehearse" ;;
    --verify)       MODE="verify" ;;
    --reset-broker) MODE="reset-broker" ;;
    --help|-h)      sed -n '2,23p' "${BASH_SOURCE[0]}" | sed 's/^# \{0,1\}//'; exit 0 ;;
    "")             ;;
    *)              die "unknown option: $1 (try --help)" ;;
esac

SCRIPT=script/DeployIssuerHierarchy.s.sol

if [[ "$MODE" == "rehearse" ]]; then
    step "Fork rehearsal — no transactions, nothing spent"
    forge test --match-path 'test/fork/HierarchyRehearsal.t.sol' -vv
    echo
    ok "rehearsal passed — the same sequence will run against live Sepolia"
    exit 0
fi

# ---------------------------------------------------------------------------
# Preflight
# ---------------------------------------------------------------------------

step "Preflight"

command -v forge >/dev/null || die "forge not found — install Foundry"
command -v cast  >/dev/null || die "cast not found — install Foundry"

# Load .env without letting it clobber anything already exported.
if [[ -f ../.env ]]; then
    set -a; # shellcheck disable=SC1091
    source ../.env; set +a
    info "loaded ../.env"
else
    warn "no ../.env found — relying on the current environment"
fi

: "${DEPLOYER_PRIVATE_KEY:?set DEPLOYER_PRIVATE_KEY in ../.env}"
: "${SEPOLIA_RPC_URL:?set SEPOLIA_RPC_URL in ../.env}"

DEPLOYER=$(cast wallet address --private-key "$DEPLOYER_PRIVATE_KEY")
info "deployer  $DEPLOYER"

cast chain-id --rpc-url "$SEPOLIA_RPC_URL" >/dev/null 2>&1 || die "cannot reach SEPOLIA_RPC_URL"
CHAIN_ID=$(cast chain-id --rpc-url "$SEPOLIA_RPC_URL")
[[ "$CHAIN_ID" == "11155111" ]] || die "expected Sepolia (11155111), got chain id $CHAIN_ID"
info "chain id  $CHAIN_ID"

BALANCE=$(cast balance "$DEPLOYER" --rpc-url "$SEPOLIA_RPC_URL")
BALANCE_ETH=$(cast from-wei "$BALANCE")
info "balance   $BALANCE_ETH ETH"
# The full sequence is ~8 transactions, two of which deploy proxies.
if awk -v b="$BALANCE_ETH" 'BEGIN { exit !(b < 0.02) }'; then
    die "deployer has $BALANCE_ETH ETH — fund it before running (need ~0.02)"
fi

if [[ -z "${PERMISSIONED_TOKEN:-}" ]]; then
    warn "PERMISSIONED_TOKEN is not set"
    warn "the checker will bind a placeholder and MUST be redeployed once Builder B's token exists"
    warn "(PERMISSIONED_TOKEN is immutable on the checker)"
fi

ok "preflight passed"

# ---------------------------------------------------------------------------
# Phases
# ---------------------------------------------------------------------------

run_phase() {
    local sig="$1" label="$2"
    CURRENT_PHASE="$label"
    step "$label"
    forge script "$SCRIPT" --sig "$sig" --rpc-url "$SEPOLIA_RPC_URL" --broadcast --slow
    ok "$label"
}

if [[ "$MODE" == "verify" ]]; then
    CURRENT_PHASE="verify"
    step "Verify"
    forge script "$SCRIPT" --sig "verify()" --rpc-url "$SEPOLIA_RPC_URL"
    exit 0
fi

if [[ "$MODE" == "reset-broker" ]]; then
    CURRENT_PHASE="reset-broker"
    step "Re-arm the broker name"
    warn "this unregisters and re-registers ONE issuer's broker — SETUP ONLY, never on camera"
    warn "unregister is the revocation transaction the pitch claims is unnecessary"
    # Both halves are needed: a broker label can appear under several issuers, and re-arming the
    # wrong one silently resets the broker that is supposed to SURVIVE the lapse.
    forge script "$SCRIPT" --sig "resetBroker(string,string)" "${ISSUER:-}" "${BROKER:-}" \
        --rpc-url "$SEPOLIA_RPC_URL" --broadcast --slow
    echo
    ok "broker re-armed — let the countdown run out on its own for the take"
    exit 0
fi

ETH_REGISTRAR=0x7d1B7f586a62Ac3F54b9A396849757814283270b
PARENT_LABEL="${PARENT_LABEL:-canopy}"

# The parent is a once-per-year cost. Everything below it is cheap to rebuild, so on every run
# after the first this skips straight past the commit--reveal and its wait.
PARENT_FREE=$(cast call "$ETH_REGISTRAR" "isAvailable(string)(bool)" "$PARENT_LABEL" \
    --rpc-url "$SEPOLIA_RPC_URL" | tr -d '[:space:]')

if [[ "$PARENT_FREE" == "false" ]]; then
    step "1-3/6  ${PARENT_LABEL}.eth already registered — skipping commit, wait and register"
    info "re-running only the parts that are cheap to rebuild"
else
    run_phase "commitParent()" "1/6  deploy platform registry + commit to ${PARENT_LABEL}.eth"

    # --- the wait ----------------------------------------------------------
    # Read MIN_COMMITMENT_AGE from the chain rather than assuming 60s, and add a buffer: the
    # constraint is on *block* timestamps, so the next block must be far enough ahead, not merely
    # our wall clock.
    CURRENT_PHASE="commitment wait"
    MIN_AGE=$(cast call "$ETH_REGISTRAR" "MIN_COMMITMENT_AGE()(uint64)" --rpc-url "$SEPOLIA_RPC_URL" | tr -d '[:space:]')
    WAIT=$(( MIN_AGE + 15 ))

    step "2/6  waiting ${WAIT}s for the commitment to mature (MIN_COMMITMENT_AGE=${MIN_AGE}s)"
    for (( i = WAIT; i > 0; i-- )); do
        printf "\r    %ss remaining " "$i"
        sleep 1
    done
    printf "\r%*s\r" 40 ""
    ok "commitment matured"

    run_phase "registerParent()" "3/6  register ${PARENT_LABEL}.eth + wire setParent"
fi
run_phase "buildIssuers()"   "4/6  every issuer in script/hierarchy.json, with setParent on each"
run_phase "buildHierarchy()" "5/6  every broker under every issuer, with setParent on each"
run_phase "deployCheckers()" "6/6  one ENSAllowlistChecker per issuer + record every investor's path"

# ---------------------------------------------------------------------------
# Verify
# ---------------------------------------------------------------------------

CURRENT_PHASE="verify"
step "Verify — the end-of-day criterion"
forge script "$SCRIPT" --sig "verify()" --rpc-url "$SEPOLIA_RPC_URL"

trap - ERR
echo
ok "hierarchy live on Sepolia"
info "addresses written to ../deployments.json — Builder B reads this"
echo
if [[ -z "${PERMISSIONED_TOKEN:-}" ]]; then
    warn "remember: the checker is bound to a PLACEHOLDER token."
    warn "re-run with PERMISSIONED_TOKEN set once Builder B's token is deployed."
fi
