# Enterprise Mobile Skill — Installation Guide

## What's Inside

| File | Lines | Purpose |
|---|---|---|
| `SKILL.md` | ~380 | Main skill: decision framework (Expo vs CLI, navigation, state management), performance/security/offline/UX priorities, app structure, root layout, testing requirements |
| `references/react-native-expo.md` | ~380 | Expo project setup, app.config.ts, Expo Router (tabs, auth guard, typed nav), EAS Build/Submit, config plugins, API client, TanStack Query, theme system |
| `references/push-notifications.md` | ~350 | expo-notifications setup, token registration, Android channels, foreground/background/tap handlers, Expo Push API (backend), FCM direct, rich/actionable notifications, background tasks |
| `references/offline-first.md` | ~280 | MMKV setup + Zustand persistence, TanStack Query offline mode, WatermelonDB (schema, models, sync), pull-push sync, conflict resolution, offline queue, optimistic UI, network banner |
| `references/app-store-deployment.md` | ~280 | EAS Build profiles, iOS App Store Connect (metadata, rejections, Info.plist), Google Play Console (tracks, metadata), OTA updates (EAS Update), versioning, code signing, CI/CD GitHub Actions |
| `references/deep-linking.md` | ~270 | Universal Links (AASA), App Links (assetlinks.json), Expo Router deep links, custom schemes, deferred deep linking, route parameter handling, share links |
| `references/native-modules.md` | ~280 | Expo Modules API (Swift + Kotlin examples), config plugins (permissions, entitlements, CocoaPods, Gradle), Turbo Modules comparison, Fabric native views, SDK bridging pattern |

**Total: ~2,200+ lines of enterprise mobile patterns and implementation code.**

---

## Installation

### Option A: Claude Code — Global Skills (Recommended)

```bash
mkdir -p ~/.claude/skills/enterprise-mobile/references
cp SKILL.md ~/.claude/skills/enterprise-mobile/
cp references/* ~/.claude/skills/enterprise-mobile/references/
ls -R ~/.claude/skills/enterprise-mobile/
```

### Option B: Project-Level

```bash
mkdir -p .claude/skills/enterprise-mobile/references
cp SKILL.md .claude/skills/enterprise-mobile/
cp references/* .claude/skills/enterprise-mobile/references/
```

---

## Trigger Keywords

> mobile app, React Native, Expo, iOS, Android, push notification, offline-first, app store, Google Play, App Store Connect, deep link, universal link, native module, Turbo Module, EAS, mobile navigation, certificate pinning, biometric auth, OTA update, mobile testing, Detox, Maestro, WatermelonDB, MMKV

---

## Pairs With

| Skill | Purpose |
|---|---|
| `enterprise-backend` | API design, auth, WebSocket — mobile consumes these |
| `enterprise-frontend` | Shared design tokens (colors, spacing) for web + mobile |
| `enterprise-deployment` | EAS Build CI/CD, OTA update pipelines |
| `enterprise-testing` | E2E testing patterns (Maestro/Detox) |
| `enterprise-security` | Certificate pinning, secure storage, biometric auth policies |
