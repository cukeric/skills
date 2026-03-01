# App Store Deployment Reference

## EAS Build & Submit Pipeline

### Build Profiles (eas.json)

```json
{
  "build": {
    "development": {
      "developmentClient": true,
      "distribution": "internal",
      "ios": { "simulator": true },
      "env": { "API_URL": "http://localhost:3000" }
    },
    "preview": {
      "distribution": "internal",
      "channel": "preview",
      "env": { "API_URL": "https://staging-api.company.com" }
    },
    "production": {
      "autoIncrement": true,
      "channel": "production",
      "env": { "API_URL": "https://api.company.com" }
    }
  },
  "submit": {
    "production": {
      "ios": {
        "appleId": "team@company.com",
        "ascAppId": "1234567890",
        "appleTeamId": "TEAM_ID"
      },
      "android": {
        "serviceAccountKeyPath": "./google-services.json",
        "track": "production"
      }
    }
  }
}
```

### Build Commands

```bash
# Development (with dev client menu)
eas build --profile development --platform ios
eas build --profile development --platform android

# Preview (internal testers via TestFlight/Internal Track)
eas build --profile preview --platform all

# Production
eas build --profile production --platform all

# Submit to stores
eas submit --platform ios --latest
eas submit --platform android --latest

# Build + submit in one command
eas build --profile production --platform ios --auto-submit
```

---

## iOS: App Store Connect

### Prerequisites

- Apple Developer Program membership ($99/year)
- App Store Connect app record created
- App ID registered in Certificates, Identifiers & Profiles
- Provisioning profiles (EAS handles automatically with `--auto`)

### App Store Metadata Checklist

- [ ] App name (30 chars max)
- [ ] Subtitle (30 chars max)
- [ ] Description (4000 chars max)
- [ ] Keywords (100 chars max, comma-separated)
- [ ] Screenshots: 6.7" (1290×2796), 6.5" (1284×2778), 5.5" (1242×2208)
- [ ] iPad screenshots if supporting tablet
- [ ] App icon (1024×1024, no alpha channel, no rounded corners)
- [ ] Privacy policy URL (required)
- [ ] Support URL
- [ ] Age rating questionnaire completed
- [ ] App privacy details (data collection disclosure)
- [ ] Review notes (login credentials for reviewer)

### Common Rejection Reasons

1. **Crasher / performance issues** — test on oldest supported device
2. **Incomplete information** — missing privacy policy, broken links
3. **Guideline 2.1 Performance** — app doesn't function as described
4. **Guideline 4.0 Design** — not enough native iOS feel, web wrapper
5. **Guideline 5.1.1 Data Collection** — undisclosed data collection
6. **Guideline 2.3.3 Screenshots** — screenshots don't match actual app
7. **Guideline 4.2 Minimum Functionality** — app is too simple / web wrapper

### Info.plist Required Keys

```typescript
// app.config.ts
ios: {
  infoPlist: {
    NSCameraUsageDescription: 'Used to scan documents and take photos',
    NSPhotoLibraryUsageDescription: 'Used to select photos for upload',
    NSLocationWhenInUseUsageDescription: 'Used to show nearby locations',
    NSFaceIDUsageDescription: 'Used for secure authentication',
    NSMicrophoneUsageDescription: 'Used for voice messages',
    ITSAppUsesNonExemptEncryption: false,
  },
}
```

---

## Android: Google Play Console

### Prerequisites

- Google Play Developer account ($25 one-time)
- App created in Google Play Console
- Service account JSON key for automated submissions
- Signing key (EAS manages via cloud signing)

### Play Store Metadata Checklist

- [ ] App title (50 chars max)
- [ ] Short description (80 chars max)
- [ ] Full description (4000 chars max)
- [ ] Screenshots: phone (min 2, 16:9 or 9:16), 7" tablet, 10" tablet
- [ ] Feature graphic (1024×500)
- [ ] App icon (512×512)
- [ ] Privacy policy URL
- [ ] Content rating questionnaire
- [ ] Target audience and content
- [ ] Data safety section (data collection disclosure)
- [ ] Contact email and phone

### Release Tracks

| Track | Purpose | Audience |
|---|---|---|
| Internal testing | Dev team testing | Up to 100 testers, instant publish |
| Closed testing | Beta testers | Invite-only, review optional |
| Open testing | Public beta | Anyone can join, review required |
| Production | Public release | All users, review required |

---

## OTA Updates (EAS Update)

Over-the-air updates deploy JS bundle changes without app store review. Only JS/asset changes — no native code changes.

### Setup

```bash
# Install EAS Update
npx expo install expo-updates

# Configure in app.config.ts
updates: {
  url: 'https://u.expo.dev/your-project-id',
  enabled: true,
  fallbackToCacheTimeout: 5000,  // Wait 5s for update check
  checkAutomatically: 'ON_LOAD',
}
```

### Publish Updates

```bash
# Publish to preview channel
eas update --channel preview --message "Fix login button alignment"

# Publish to production
eas update --channel production --message "Critical bug fix for checkout"

# Publish specific branch
eas update --branch production --message "v1.2.1 hotfix"
```

### Update Strategies

| Strategy | Config | When |
|---|---|---|
| **Immediate** | `checkAutomatically: 'ON_LOAD'`, low timeout | Critical bug fixes |
| **Background** | Download in background, apply on next launch | Normal updates |
| **Forced** | Show update modal, reload app | Security patches |
| **Manual** | User checks for updates in settings | User preference |

### Programmatic Update Check

```typescript
import * as Updates from 'expo-updates'
import { Alert } from 'react-native'

export async function checkForUpdates(): Promise<void> {
  if (__DEV__) return // Skip in development

  try {
    const update = await Updates.checkForUpdateAsync()

    if (update.isAvailable) {
      await Updates.fetchUpdateAsync()

      Alert.alert(
        'Update Available',
        'A new version has been downloaded. Restart to apply.',
        [
          { text: 'Later', style: 'cancel' },
          { text: 'Restart', onPress: () => Updates.reloadAsync() },
        ]
      )
    }
  } catch (error) {
    console.error('Update check failed:', error)
  }
}
```

---

## Versioning Strategy

### Semantic Versioning

```
MAJOR.MINOR.PATCH
1.2.3
```

- **MAJOR**: Breaking changes, major redesigns
- **MINOR**: New features, non-breaking
- **PATCH**: Bug fixes, OTA updates

### Build Numbers

- **iOS `buildNumber`**: Increment for every build submitted
- **Android `versionCode`**: Increment for every build submitted
- **EAS auto-increment**: Set `"autoIncrement": true` in eas.json

### Version Management

```typescript
// app.config.ts
export default {
  version: '1.2.3',          // User-visible version
  ios: { buildNumber: '45' },
  android: { versionCode: 45 },
}
```

---

## Code Signing

### iOS Signing (EAS Managed — Recommended)

```bash
# EAS manages certificates and profiles automatically
eas credentials --platform ios
```

### Android Signing

```bash
# EAS manages keystore in the cloud
eas credentials --platform android

# For manual management
keytool -genkeypair -v -storetype PKCS12 \
  -keystore my-upload-key.keystore \
  -alias my-key-alias \
  -keyalg RSA -keysize 2048 -validity 10000
```

---

## CI/CD Integration

### GitHub Actions + EAS Build

```yaml
# .github/workflows/eas-build.yml
name: EAS Build & Submit
on:
  push:
    branches: [main]
    tags: ['v*']

jobs:
  build:
    runs-on: ubuntu-latest
    steps:
      - uses: actions/checkout@v4
      - uses: actions/setup-node@v4
        with: { node-version: 20 }

      - name: Install dependencies
        run: npm ci

      - name: Setup EAS
        uses: expo/expo-github-action@v8
        with:
          eas-version: latest
          token: ${{ secrets.EXPO_TOKEN }}

      - name: Build preview (on push to main)
        if: github.ref == 'refs/heads/main'
        run: eas build --profile preview --platform all --non-interactive

      - name: Build & submit production (on tag)
        if: startsWith(github.ref, 'refs/tags/v')
        run: eas build --profile production --platform all --auto-submit --non-interactive
```

---

## Deployment Checklist

- [ ] App icons generated for all densities (1024×1024 source)
- [ ] Splash screen configured and tested
- [ ] App Store / Play Store metadata complete
- [ ] Screenshots taken on required device sizes
- [ ] Privacy policy URL accessible and accurate
- [ ] Data collection disclosures match actual behavior
- [ ] Version and build numbers incremented
- [ ] Production API URL configured
- [ ] Analytics / crash reporting enabled
- [ ] Console.log removed (`babel-plugin-transform-remove-console`)
- [ ] Performance tested on low-end devices
- [ ] Deep links tested with production domain
- [ ] Push notifications tested with production certificates
- [ ] OTA update channel configured for production
- [ ] Code signing credentials backed up securely
