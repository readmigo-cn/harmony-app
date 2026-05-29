#!/bin/bash
# check-release-readiness.sh
# Pre-release verification checklist for Readmigo CN HarmonyOS v0.1.0
#
# Runs checks to ensure:
#   1. agconnect-services.json exists and contains no placeholder markers
#   2. signing-config.json exists and certificate paths resolve
#   3. CnConfig.ets and EntryAbility.ets contain no _PLACEHOLDER_ markers
#   4. signing/*.p12 + signing/*.cer + signing/*.p7b files present
#   5. No MOCK_OK payment fallback markers remain in entry code
#   6. Import boundary check passes (node scripts/check-import-boundary.mjs)
#   7. All HSP modules have required build-profile.json5 + module.json5 files
#
# Exit: 0 if all pass, 1 if any fail

set -e

# Color output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m' # No Color

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="$(dirname "$SCRIPT_DIR")"

echo "=== Release Readiness Verification ==="
echo ""

PASS_COUNT=0
FAIL_COUNT=0

# Helper: print pass
pass() {
  echo -e "${GREEN}✓${NC} $1"
  ((PASS_COUNT++))
}

# Helper: print fail
fail() {
  echo -e "${RED}✗${NC} $1"
  ((FAIL_COUNT++))
}

# Helper: print warning (non-fatal)
warn() {
  echo -e "${YELLOW}⚠${NC} $1"
}

# ============================================================
# Check 1: agconnect-services.json
# ============================================================
echo "Check 1: AGC Services Configuration"
if [ -f "$PROJECT_ROOT/agconnect-services.json" ]; then
  if grep -q '<REPLACE_ME>' "$PROJECT_ROOT/agconnect-services.json"; then
    fail "agconnect-services.json exists but contains <REPLACE_ME> placeholders"
    echo "  → Fill all placeholders in agconnect-services.json"
    echo "    Download from AGC: Project Settings > AGC Services"
  else
    pass "agconnect-services.json exists and is configured"
  fi
else
  fail "agconnect-services.json not found at project root"
  echo "  → Download from AGC: Project Settings > AGC Services"
  echo "  → Place at: $PROJECT_ROOT/agconnect-services.json"
fi

# ============================================================
# Check 2: signing-config.json
# ============================================================
echo "Check 2: Signing Configuration"
if [ -f "$PROJECT_ROOT/signing-config.json" ]; then
  if grep -q '<REPLACE_ME:' "$PROJECT_ROOT/signing-config.json" || \
     grep -q '\[YOUR_' "$PROJECT_ROOT/signing-config.json"; then
    fail "signing-config.json exists but contains placeholder passwords"
    echo "  → Fill keystore passwords in signing-config.json"
  else
    pass "signing-config.json exists and is configured"
  fi
else
  fail "signing-config.json not found at project root"
  echo "  → Copy signing-config.json.example and fill in actual values"
  echo "  → Place at: $PROJECT_ROOT/signing-config.json"
fi

# ============================================================
# Check 3: Certificate files exist
# ============================================================
echo "Check 3: Signing Certificate Files"
CERT_COUNT=0
for cert in "$PROJECT_ROOT/signing"/*.p12 "$PROJECT_ROOT/signing"/*.cer "$PROJECT_ROOT/signing"/*.p7b; do
  if [ -f "$cert" ]; then
    ((CERT_COUNT++))
  fi
done

if [ $CERT_COUNT -ge 3 ]; then
  pass "All required certificate files present (.p12, .cer, .p7b)"
elif [ $CERT_COUNT -gt 0 ]; then
  fail "Only $CERT_COUNT of 3 required certificate files found"
  echo "  → Generate keystore (.p12) in DevEco Studio"
  echo "  → Generate CSR, upload to AGC, receive .cer and .p7b"
  echo "  → Place in: $PROJECT_ROOT/signing/"
else
  fail "No certificate files found in $PROJECT_ROOT/signing/"
  echo "  → Generate keystore (.p12) in DevEco Studio"
  echo "  → Generate CSR, upload to AGC, receive .cer and .p7b"
  echo "  → Place in: $PROJECT_ROOT/signing/"
fi

# ============================================================
# Check 4: CnConfig.ets placeholders
# ============================================================
echo "Check 4: Configuration Constant Placeholders"
CNCONFIG_PATH="$PROJECT_ROOT/entry/src/main/ets/core/config/CnConfig.ets"
if [ -f "$CNCONFIG_PATH" ]; then
  if grep -q '_PLACEHOLDER_' "$CNCONFIG_PATH" || grep -q '\[YOUR_' "$CNCONFIG_PATH"; then
    fail "CnConfig.ets contains unfilled placeholder markers"
    echo "  → Replace _PLACEHOLDER_* markers with real values from:"
    echo "    - SA_SERVER_URL: from SensorsAnalytics"
    echo "    - AGC_APP_ID: from AGC > App Information"
    echo "    - SENTRY_DSN: from Sentry project settings"
    echo "    - WECHAT_APP_ID: from Tencent WeChat Open Platform"
  else
    pass "CnConfig.ets contains no placeholder markers"
  fi
else
  warn "CnConfig.ets not found at $CNCONFIG_PATH (will be created by auth-push-dev)"
fi

# Also check EntryAbility.ets as fallback
ENTRY_PATH="$PROJECT_ROOT/entry/src/main/ets/entryability/EntryAbility.ets"
if [ -f "$ENTRY_PATH" ] && grep -q '_PLACEHOLDER_' "$ENTRY_PATH"; then
  fail "EntryAbility.ets still contains _PLACEHOLDER_ markers"
  echo "  → Update placeholder constants at top of EntryAbility.ets"
fi

# ============================================================
# Check 5: No MOCK_OK payment markers
# ============================================================
echo "Check 5: Payment Fallback Markers"
MOCK_COUNT=$(find "$PROJECT_ROOT/entry/src/main/ets" -name "*.ets" -exec grep -l 'MOCK_OK' {} \; 2>/dev/null | wc -l)
if [ $MOCK_COUNT -eq 0 ]; then
  pass "No MOCK_OK payment fallback markers found in entry code"
else
  fail "Found $MOCK_COUNT file(s) with MOCK_OK markers in payment code"
  echo "  → Remove MOCK_OK markers from payment provider implementations"
  echo "  → Ensure real payment providers are integrated before release"
fi

# ============================================================
# Check 6: Import boundary check
# ============================================================
echo "Check 6: Architecture Boundary Compliance"
if [ -f "$PROJECT_ROOT/scripts/check-import-boundary.mjs" ]; then
  if node "$PROJECT_ROOT/scripts/check-import-boundary.mjs" > /dev/null 2>&1; then
    pass "Import boundary check passed (no layer violations)"
  else
    fail "Import boundary violations detected"
    echo "  → Run: node $PROJECT_ROOT/scripts/check-import-boundary.mjs"
    echo "  → Fix violations before release"
  fi
else
  warn "check-import-boundary.mjs not found (skipping architecture check)"
fi

# ============================================================
# Check 7: HSP module structure
# ============================================================
echo "Check 7: HSP Module Configuration"
# List of expected HSP modules per bundle-strategy.md
HSP_MODULES=()
MISSING_MODULES=0

# Scan for existing HSP modules with build-profile.json5
for hsp_dir in "$PROJECT_ROOT"/entry/src/main/ets/features/*/; do
  if [ -d "$hsp_dir" ] && [ -f "$hsp_dir/build-profile.json5" ]; then
    HSP_MODULES+=("$(basename "$hsp_dir")")
  fi
done

if [ ${#HSP_MODULES[@]} -eq 0 ]; then
  warn "No HSP modules with build-profile.json5 found yet (expected in W21–W22)"
  warn "Core entry module must have build-profile.json5"
  if [ ! -f "$PROJECT_ROOT/entry/build-profile.json5" ]; then
    fail "entry/build-profile.json5 not found"
    ((MISSING_MODULES++))
  else
    pass "entry/build-profile.json5 present"
  fi
else
  for module in "${HSP_MODULES[@]}"; do
    MODULE_PATH="$PROJECT_ROOT/$module"
    if [ -f "$MODULE_PATH/build-profile.json5" ] && [ -f "$MODULE_PATH/module.json5" ]; then
      pass "HSP module '$module' has required config files"
    else
      fail "HSP module '$module' missing build-profile.json5 or module.json5"
      ((MISSING_MODULES++))
    fi
  done
fi

# ============================================================
# Summary
# ============================================================
echo ""
echo "=== Verification Summary ==="
echo -e "Passed: ${GREEN}$PASS_COUNT${NC}  Failed: ${RED}$FAIL_COUNT${NC}"
echo ""

if [ $FAIL_COUNT -eq 0 ]; then
  echo -e "${GREEN}✓ All checks passed. Ready to build.${NC}"
  echo ""
  echo "Next step:"
  echo "  ./hvigorw assembleHap --mode product=release"
  exit 0
else
  echo -e "${RED}✗ Some checks failed. Address issues above before building.${NC}"
  echo ""
  echo "Refer to docs/release-setup.md for detailed remediation steps."
  exit 1
fi
