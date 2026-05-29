# Release Setup for Readmigo CN HarmonyOS v0.1.0

A step-by-step guide to prepare the Readmigo CN HarmonyOS application for signed release build and submission to AppGallery Connect (AGC).

> **Audience:** Release engineers and developers preparing a production HAP for AppGallery. The entire checklist takes ~2–3 hours on first run (mostly AGC registration and certificate coordination). Estimated time per step is listed below.

---

## Overview

Releasing to AppGallery requires four concurrent workstreams to converge:

1. **AGC registration**: Create app record, download signing configuration
2. **Signing certificate chain**: Generate keystore → .csr → upload to AGC → receive .p7b profile
3. **Config injection**: Fill `agconnect-services.json` + `signing-config.json` with real values
4. **Release build**: Compile with release product + verify no placeholder markers remain

The verification script (`scripts/check-release-readiness.sh`) gates the build to ensure no step is skipped.

---

## Prerequisites

| Tool | Version | Source |
|------|---------|--------|
| DevEco Studio | 5.0.0 or later | huawei.com/deveco |
| HarmonyOS SDK | 5.0.0 (API 12) | Bundled with DevEco |
| Node.js | 18 LTS or later | nodejs.org |
| Bash | 4.0+ (POSIX sh compatible) | System default |
| Huawei account | — | huawei.com |

---

## Step 1: AGC Application Registration (Estimated: 30 min)

### 1.1 Create app record in AppGallery Connect

1. Open [AppGallery Connect](https://connect.cloud.huawei.com/AGC/)
2. Select "My Apps" → "New App"
3. Fill in:
   - **App name**: `Readmigo CN`
   - **Default language**: Chinese (Simplified)
   - **Package name**: `com.readmigo.harmony.cn`
   - **Platform**: HarmonyOS
4. Click "Create"

### 1.2 Download agconnect-services.json

1. In AGC, navigate to app → **Manage APIs**
2. Enable: AppGallery Connect Core, Push Kit, Analytics Kit, Crash Service
3. Navigate to app → **Project Settings** → **AGC Services**
4. Download **agconnect-services.json**
5. Place it at the project root: `/Users/hongbin/Documents/readmigo-cn/harmony-app/agconnect-services.json`

### Verification

```bash
# agconnect-services.json must exist and contain no placeholder markers
test -f agconnect-services.json && \
  ! grep -q '<REPLACE_ME>' agconnect-services.json && \
  echo "✓ agconnect-services.json ready"
```

---

## Step 2: Signing Certificate Generation (Estimated: 45 min)

The HarmonyOS signing chain requires a local keystore, Huawei-signed certificate (.cer), and publishing profile (.p7b).

### 2.1 Generate keystore in DevEco Studio

1. Open DevEco Studio
2. Tools → AppSign → **Key Store File Management**
3. Click **Create Key Store**
   - **Alias**: `readmigo-cn-release`
   - **Password**: [Use strong password, save to secure location]
   - **Key type**: `ECC` (NIST P-256, shorter than RSA and sufficient for HarmonyOS)
   - **Validity**: 25 years
   - **Distinguished Name (DN)**: 
     - CN: Readmigo CN
     - O: Readmigo CN
     - C: CN (country code)
4. Save keystore as `signing/readmigo-cn-release.p12`

### 2.2 Generate Certificate Signing Request (.csr)

1. In DevEco **Key Store File Management**, select the keystore above
2. Right-click → **Generate CSR**
3. Save as `signing/readmigo-cn-release.csr`

### 2.3 Upload CSR to AppGallery & receive .cer

1. In AGC app → **App Signature** → **App Signing Certificate**
2. Click **Upload CSR**
3. Choose `signing/readmigo-cn-release.csr`
4. AGC signs and immediately displays the certificate
5. Download & save as `signing/readmigo-cn-release.cer`

### 2.4 Generate Publishing Profile (.p7b)

1. In AGC, navigate to app → **App Signature** → **App Publishing Profile**
2. Click **Create**
   - **Module**: `entry` (or leave default)
   - **Certificate**: Select the certificate uploaded above
   - **Level**: `Release`
3. Download the `.p7b` file
4. Save as `signing/readmigo-cn-release.p7b`

### Verification

```bash
# All three files must exist
for f in signing/readmigo-cn-release.p12 signing/readmigo-cn-release.cer signing/readmigo-cn-release.p7b; do
  test -f "$f" || (echo "✗ Missing $f"; exit 1)
done
echo "✓ All certificate files present"
```

---

## Step 3: Fill signing-config.json (Estimated: 10 min)

The `signing-config.json` file at the project root connects the build system to your keystore and certificate chain.

### 3.1 Create signing-config.json

Copy from template and fill in actual paths and passwords:

```json
{
  "signings": [
    {
      "name": "readmigo",
      "type": "HarmonyOS",
      "material": {
        "certpath": "signing/readmigo-cn-release.cer",
        "keyAlias": "readmigo-cn-release",
        "keyPassword": "[YOUR_KEYSTORE_PASSWORD]",
        "storeFile": "signing/readmigo-cn-release.p12",
        "storePassword": "[YOUR_KEYSTORE_PASSWORD]"
      }
    }
  ]
}
```

### 3.2 Add .p7b profile to build-profile.json5

Edit `build-profile.json5`, uncomment and fill the release signing config:

```javascript
"signingConfigs": [
  {
    "name": "release",
    "type": "HarmonyOS",
    "material": {
      "certpath": "signing/readmigo-cn-release.cer",
      "storePassword": "[YOUR_KEYSTORE_PASSWORD]",
      "keyAlias": "readmigo-cn-release",
      "keyPassword": "[YOUR_KEYSTORE_PASSWORD]",
      "profile": "signing/readmigo-cn-release.p7b",
      "signAlg": "SHA256withECDSA",
      "storeFile": "signing/readmigo-cn-release.p12"
    }
  }
],
```

And wire the release product to this config:

```javascript
{
  "name": "release",
  "signingConfig": "release",  // Changed from "default"
  "compatibleSdkVersion": "5.0.0(12)",
  "compileSdkVersion": "5.0.0(12)",
  "targetSdkVersion": "5.0.0(12)",
  "runtimeOS": "HarmonyOS"
}
```

### Verification

```bash
# signing-config.json must exist and not contain placeholder passwords
test -f signing-config.json && \
  ! grep -q '\[YOUR_' signing-config.json && \
  echo "✓ signing-config.json configured"
```

---

## Step 4: Update Placeholder Config Constants (Estimated: 15 min)

### 4.1 CnConfig.ets

The file `entry/src/main/ets/core/config/CnConfig.ets` contains placeholders that must be filled with real values from AGC and external services.

Edit the following:

```typescript
// From AGC > App Information
export const SA_SERVER_URL = 'https://sa.readmigo.cn/sa';  // From SensorsAnalytics
export const SA_PROJECT_NAME = 'readmigo_harmony';          // From SensorsAnalytics
export const AGC_APP_ID = 'com.readmigo.harmony.cn';        // From AGC > App Information > App ID
export const SENTRY_DSN = 'https://[KEY]@sentry.io/[PROJECT]';  // From Sentry project settings
export const SENTRY_ENV = 'production';
export const WECHAT_APP_ID = 'wx[YOUR_ID]';                // From Tencent WeChat Open Platform
```

### 4.2 EntryAbility.ets (if not already synchronized)

If `entry/src/main/ets/entryability/EntryAbility.ets` still contains placeholders, update lines 43–48:

```typescript
const SA_SERVER_URL = 'https://sa.readmigo.cn/sa';
const SA_PROJECT_NAME = 'readmigo_harmony';
const AGC_APP_ID = 'com.readmigo.harmony.cn';
const SENTRY_DSN = 'https://[KEY]@sentry.io/[PROJECT]';
const SENTRY_ENV = 'production';
```

### Verification

```bash
# CnConfig.ets must exist and contain no _PLACEHOLDER_ markers
test -f entry/src/main/ets/core/config/CnConfig.ets && \
  ! grep -q '_PLACEHOLDER_' entry/src/main/ets/core/config/CnConfig.ets && \
  ! grep -q '\[YOUR_' entry/src/main/ets/core/config/CnConfig.ets && \
  echo "✓ CnConfig.ets placeholders replaced"
```

---

## Step 5: Run Release Readiness Check (Estimated: 2 min)

Before building, verify all configuration files are in place and properly filled:

```bash
bash /Users/hongbin/Documents/readmigo-cn/harmony-app/scripts/check-release-readiness.sh
```

Expected output:

```
=== Release Readiness Verification ===
✓ agconnect-services.json exists and is configured
✓ signing-config.json exists and is configured
✓ CnConfig.ets contains no placeholder markers
✓ All required certificate files present
✓ No MOCK_OK markers found in payment code
✓ Import boundary check passed
✓ All HSP modules have required config files
=== All checks passed. Ready to build. ===
```

If any check fails, the script will list remediation steps. **Do not proceed to Step 6 until all checks pass.**

---

## Step 6: Build & Upload (Estimated: 5–10 min)

### 6.1 Build release HAP

```bash
cd /Users/hongbin/Documents/readmigo-cn/harmony-app
./hvigorw assembleHap --mode product=release
```

Output HAP path:

```
entry/build/default/outputs/release/entry-release.hap
```

### 6.2 Upload to AppGallery Connect

1. In AGC, navigate to app → **Version Management** → **New Version**
2. Fill in:
   - **Version number**: `0.1.0`
   - **Version name**: `0.1.0`
   - **Release notes**: [Copy from `docs/changelog/CHANGELOG.md`]
3. Upload the HAP:
   - Click **Upload APK/HAP**
   - Select `entry-release.hap`
4. Click **Save**

### 6.3 Submit for Review

1. Scroll to **Submit for Review**
2. Fill content rating questionnaire (select "Ages 3+" or based on app content)
3. Click **Submit for Review**
4. Wait for Huawei review (typically 1–3 hours)

### Verification

AppGallery displays a "pending review" status. Check back in ~2 hours for approval.

---

## Rollback & Troubleshooting

| Issue | Cause | Fix |
|-------|-------|-----|
| Build fails: "signingConfig not found" | `build-profile.json5` not updated with release signing config | Re-read Step 3.2, ensure `"signingConfig": "release"` is set |
| Build fails: "keystore file not found" | Path mismatch in signing-config.json | Verify path is relative to project root, e.g., `signing/readmigo-cn-release.p12` |
| Build fails: "placeholder markers remain" | `check-release-readiness.sh` detected unfilled config | Re-read Step 4, search for `_PLACEHOLDER_` and `[YOUR_` |
| AGC upload fails: "package signature invalid" | Certificate chain mismatched | Ensure .p7b profile matches the .cer from the same CSR |
| AGC upload fails: "version number already exists" | Duplicate version in AGC | Increment version number in Step 6.2 |

---

## Release Timeline

| Milestone | Action | Owner | Duration |
|-----------|--------|-------|----------|
| Day 1 | Steps 1–3 (AGC registration, certificate generation) | Release Engineer | ~1.5 hours |
| Day 1 | Step 4 (config injection) | Backend/Config Owner | ~15 min |
| Day 1 | Step 5 (readiness check) | Release Engineer | ~2 min |
| Day 1 | Step 6 (build & upload) | Release Engineer | ~10 min |
| Day 2 | Monitor Huawei review | Release Engineer | ~2 hours |
| Day 2 | Publish to AppGallery | Product Manager | ~5 min |

---

## Reference

- [HarmonyOS App Signing](https://developer.huawei.com/consumer/en/doc/harmonyos-guides/app-signature-0000001052418349)
- [AppGallery Connect Overview](https://developer.huawei.com/consumer/en/service/josp/agc/index.html)
- [HarmonyOS 5.0 SDK](https://developer.huawei.com/consumer/en/harmonyos/doc/)
- [Readmigo Architecture Docs](./ARCHITECTURE.md)
- [Bundle Strategy](./bundle-strategy.md)
