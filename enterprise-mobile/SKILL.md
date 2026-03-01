---
name: enterprise-mobile
description: Explains how to create, design, modify, or optimize mobile applications with enterprise standards using React Native and Expo. Trigger on ANY mention of mobile app, React Native, Expo, iOS, Android, push notification, offline-first, app store, Google Play, App Store Connect, deep link, universal link, native module, Turbo Module, Fabric, EAS, mobile navigation, mobile performance, certificate pinning, biometric auth, mobile CI/CD, OTA update, code push, mobile testing, Detox, Maestro, mobile analytics, app signing, provisioning profile, mobile offline, WatermelonDB, MMKV, mobile state management, or any request to build a mobile application. This skill applies to new mobile projects AND modifications to existing React Native / Expo apps.
---

# Enterprise Mobile Development Skill

Every mobile application created or modified using this skill must meet enterprise-grade standards for performance, security, offline reliability, and user experience — in that priority order. Mobile apps run on user devices with constrained resources, unreliable networks, and strict platform gatekeepers. There are no shortcuts. Even for MVPs, the performance and security foundations must be production-ready from day one.

## Reference Files

This skill has detailed reference guides. Read the relevant file(s) based on the project's requirements:

### React Native & Expo

- `references/react-native-expo.md` — Expo setup, project structure, EAS Build/Submit, config plugins, Expo Router, managed vs bare workflow

### Push Notifications

- `references/push-notifications.md` — expo-notifications, FCM/APNs setup, token management, notification handling, background notifications, rich notifications

### Offline-First Architecture

- `references/offline-first.md` — WatermelonDB/MMKV, sync strategies, conflict resolution, optimistic UI, network detection, queue-and-retry

### App Store Deployment

- `references/app-store-deployment.md` — EAS Submit, App Store Connect, Google Play Console, signing, OTA updates, versioning, review guidelines

### Deep Linking

- `references/deep-linking.md` — Universal links (iOS), App Links (Android), Expo Router deep links, deferred deep linking, attribution

### Native Module Integration

- `references/native-modules.md` — Expo Modules API, Turbo Modules, Fabric architecture, native views, bridging Swift/Kotlin

Read this SKILL.md first for architecture decisions and standards, then consult the relevant reference files for implementation specifics.

---

## Decision Framework: Choosing the Right Mobile Stack

Before writing any mobile code, evaluate the project requirements and select the appropriate approach.

### Expo vs React Native CLI

| Requirement | Best Choice | Why |
|---|---|---|
| New app, standard features | **Expo (managed)** | Pre-configured toolchain, OTA updates, EAS Build, no Xcode/Android Studio needed for dev |
| Custom native code needed | **Expo (bare/dev client)** | Expo Modules API + config plugins give native access while keeping Expo benefits |
| Existing iOS/Android codebase | **React Native CLI** | Full control over native projects, brownfield integration |
| Heavily custom native UI | **React Native CLI** | Direct Xcode/Android Studio project access |
| Rapid prototyping / MVP | **Expo Go** | Instant testing on device, zero build configuration |
| Enterprise with MDM/custom SDK | **Expo Dev Client** | Custom native runtime + Expo DX benefits |

**Default: Expo with development builds.** It covers 95% of use cases and the toolchain velocity is unmatched.

### Navigation Selection

| Pattern | Best Choice | Why |
|---|---|---|
| File-based routing (Next.js-like) | **Expo Router** | Convention over configuration, deep linking built-in, type-safe |
| Complex nested navigation | **React Navigation** | Most flexible, mature ecosystem, custom navigators |
| Simple tab/stack app | **Expo Router** | Minimal config, automatic deep links |

**Default: Expo Router.** It's built on React Navigation but adds file-based routing, automatic deep linking, and type safety.

### State Management

| Pattern | Best Choice | Why |
|---|---|---|
| Server state (API data) | **TanStack Query** | Caching, background refetch, offline support, optimistic updates |
| Global client state | **Zustand** | Minimal boilerplate, TypeScript-first, persistence via MMKV |
| Complex forms | **React Hook Form + Zod** | Performance (uncontrolled inputs), validation, type inference |
| Local component state | **React useState/useReducer** | Simple, no overhead |

---

## Priority 1: Performance

Mobile performance directly impacts user retention. A 100ms delay feels sluggish on mobile.

### Performance Targets

| Metric | Target | Measurement |
|---|---|---|
| Cold start (TTI) | < 2 seconds | Flipper / Expo DevTools |
| JS thread FPS | 60 FPS (16.6ms/frame) | React DevTools Profiler |
| Navigation transition | < 300ms | User perception |
| List scrolling | 60 FPS, no blank frames | FlatList performance monitor |
| Bundle size (JS) | < 5MB compressed | `npx expo export` |
| Memory usage | < 200MB baseline | Xcode Instruments / Android Profiler |
| API response render | < 500ms from tap to data | Network + render time |

### Performance Non-Negotiables

- **Use `FlatList` or `FlashList` for lists** — never `ScrollView` with `.map()` for dynamic data.
- **Memoize expensive components** — `React.memo`, `useMemo`, `useCallback` where profiling shows re-renders.
- **Avoid inline styles for static styling** — use `StyleSheet.create()` outside components.
- **Lazy load heavy screens** — `React.lazy()` + Suspense for screens not on the initial route.
- **Image optimization** — use `expo-image` (not `<Image>`), webp format, appropriate resolution per screen density.
- **Avoid bridge traffic** — batch native calls, use Turbo Modules for hot paths.
- **Hermes engine** — always enabled (default in Expo SDK 49+). Verify with `global.HermesInternal`.
- **Remove console.log in production** — use `babel-plugin-transform-remove-console`.

### FlatList Optimization Pattern

```typescript
import { FlashList } from '@shopify/flash-list'

function OrderList({ orders }: { orders: Order[] }) {
  const renderItem = useCallback(({ item }: { item: Order }) => (
    <OrderCard order={item} />
  ), [])

  const keyExtractor = useCallback((item: Order) => item.id, [])

  return (
    <FlashList
      data={orders}
      renderItem={renderItem}
      keyExtractor={keyExtractor}
      estimatedItemSize={80}
      // FlashList handles recycling automatically
    />
  )
}

// OrderCard must be memoized
const OrderCard = React.memo(function OrderCard({ order }: { order: Order }) {
  return (
    <Pressable style={styles.card}>
      <Text style={styles.title}>{order.title}</Text>
      <Text style={styles.status}>{order.status}</Text>
    </Pressable>
  )
})
```

---

## Priority 2: Security

Mobile apps are distributed binaries — attackers can decompile, intercept traffic, and tamper with storage.

### Security Non-Negotiables

- **Certificate pinning** for all API communication using `expo-secure-store` or `react-native-ssl-pinning`.
- **Secure storage** for tokens and secrets — `expo-secure-store` (Keychain on iOS, EncryptedSharedPreferences on Android). Never `AsyncStorage` for sensitive data.
- **Biometric authentication** for sensitive actions using `expo-local-authentication`.
- **Code obfuscation** — Hermes bytecode provides baseline obfuscation. Add ProGuard rules for Android.
- **Root/jailbreak detection** — warn users, disable sensitive features on compromised devices.
- **No secrets in JS bundle** — API keys, signing keys, and secrets must come from the backend or secure config.
- **App Transport Security (ATS)** — never disable on iOS. All connections must be HTTPS.
- **Disable debugging in release builds** — strip Flipper, React DevTools, console access.

### Secure Storage Pattern

```typescript
import * as SecureStore from 'expo-secure-store'

const TOKEN_KEY = 'auth_access_token'
const REFRESH_KEY = 'auth_refresh_token'

export const secureStorage = {
  async setTokens(access: string, refresh: string) {
    await Promise.all([
      SecureStore.setItemAsync(TOKEN_KEY, access, {
        keychainAccessible: SecureStore.WHEN_UNLOCKED_THIS_DEVICE_ONLY,
      }),
      SecureStore.setItemAsync(REFRESH_KEY, refresh, {
        keychainAccessible: SecureStore.WHEN_UNLOCKED_THIS_DEVICE_ONLY,
      }),
    ])
  },

  async getAccessToken(): Promise<string | null> {
    return SecureStore.getItemAsync(TOKEN_KEY)
  },

  async clearTokens() {
    await Promise.all([
      SecureStore.deleteItemAsync(TOKEN_KEY),
      SecureStore.deleteItemAsync(REFRESH_KEY),
    ])
  },
}
```

### Biometric Auth Pattern

```typescript
import * as LocalAuthentication from 'expo-local-authentication'

async function authenticateWithBiometrics(): Promise<boolean> {
  const hasHardware = await LocalAuthentication.hasHardwareAsync()
  if (!hasHardware) return false

  const isEnrolled = await LocalAuthentication.isEnrolledAsync()
  if (!isEnrolled) return false

  const result = await LocalAuthentication.authenticateAsync({
    promptMessage: 'Authenticate to continue',
    fallbackLabel: 'Use passcode',
    disableDeviceFallback: false,
    cancelLabel: 'Cancel',
  })

  return result.success
}
```

---

## Priority 3: Offline Reliability

Enterprise mobile apps must function in environments with poor or no connectivity.

### Offline Strategy Selection

| Scenario | Strategy | Technology |
|---|---|---|
| Read-only cached data | **Cache-first** | TanStack Query + MMKV persistence |
| Simple key-value storage | **Local-first** | MMKV (synchronous, fast) |
| Complex relational data | **Offline-first DB** | WatermelonDB (SQLite-backed, lazy loading) |
| File/media caching | **Download + cache** | expo-file-system |
| Form submissions offline | **Queue-and-retry** | Custom queue in MMKV + background fetch |

### Network Detection

```typescript
import NetInfo from '@react-native-community/netinfo'
import { create } from 'zustand'

interface NetworkState {
  isConnected: boolean
  isInternetReachable: boolean | null
  connectionType: string | null
}

export const useNetworkStore = create<NetworkState>(() => ({
  isConnected: true,
  isInternetReachable: true,
  connectionType: null,
}))

// Initialize in app root
NetInfo.addEventListener((state) => {
  useNetworkStore.setState({
    isConnected: state.isConnected ?? false,
    isInternetReachable: state.isInternetReachable,
    connectionType: state.type,
  })
})
```

---

## Priority 4: User Experience

### Platform Conventions

- **Follow platform design guidelines** — iOS Human Interface Guidelines, Material Design 3 for Android.
- **Platform-specific components** where they differ (e.g., date pickers, action sheets, haptics).
- **Respect system preferences** — dark mode, font scaling, reduce motion, screen reader.
- **Haptic feedback** on meaningful interactions (button press, success, error) using `expo-haptics`.
- **Safe area handling** — always use `SafeAreaView` or `useSafeAreaInsets()` from `react-native-safe-area-context`.
- **Keyboard avoidance** — `KeyboardAvoidingView` or `react-native-keyboard-aware-scroll-view` for forms.

### App Structure (Expo Router)

```
app/
├── (tabs)/                     # Tab navigator layout
│   ├── _layout.tsx             # Tab bar configuration
│   ├── index.tsx               # Home tab
│   ├── search.tsx              # Search tab
│   └── profile.tsx             # Profile tab
├── (auth)/                     # Auth group (no tabs)
│   ├── _layout.tsx             # Stack navigator for auth flow
│   ├── login.tsx
│   ├── register.tsx
│   └── forgot-password.tsx
├── settings/                   # Settings stack
│   ├── _layout.tsx
│   ├── index.tsx
│   ├── notifications.tsx
│   └── security.tsx
├── [id].tsx                    # Dynamic route (detail view)
├── _layout.tsx                 # Root layout (providers, fonts, splash)
└── +not-found.tsx              # 404 handler
src/
├── components/
│   ├── ui/                     # Reusable UI primitives
│   ├── forms/                  # Form components
│   └── lists/                  # List item components
├── hooks/                      # Custom hooks
├── lib/                        # Utilities, API client, storage
├── services/                   # API service layer
├── stores/                     # Zustand stores
├── types/                      # TypeScript types
└── constants/                  # Theme, config, feature flags
```

### Root Layout Pattern

```typescript
// app/_layout.tsx
import { Stack } from 'expo-router'
import { QueryClient, QueryClientProvider } from '@tanstack/react-query'
import { ThemeProvider, useTheme } from '@/lib/theme'
import { useFonts } from 'expo-font'
import * as SplashScreen from 'expo-splash-screen'
import { useEffect } from 'react'
import { GestureHandlerRootView } from 'react-native-gesture-handler'
import { SafeAreaProvider } from 'react-native-safe-area-context'

SplashScreen.preventAutoHideAsync()

const queryClient = new QueryClient({
  defaultOptions: {
    queries: {
      staleTime: 5 * 60 * 1000,      // 5 minutes
      gcTime: 30 * 60 * 1000,         // 30 minutes
      retry: 2,
      refetchOnWindowFocus: false,     // Not relevant on mobile
    },
  },
})

export default function RootLayout() {
  const [fontsLoaded] = useFonts({
    'Inter-Regular': require('@/assets/fonts/Inter-Regular.ttf'),
    'Inter-Medium': require('@/assets/fonts/Inter-Medium.ttf'),
    'Inter-Bold': require('@/assets/fonts/Inter-Bold.ttf'),
  })

  useEffect(() => {
    if (fontsLoaded) SplashScreen.hideAsync()
  }, [fontsLoaded])

  if (!fontsLoaded) return null

  return (
    <GestureHandlerRootView style={{ flex: 1 }}>
      <SafeAreaProvider>
        <QueryClientProvider client={queryClient}>
          <ThemeProvider>
            <Stack screenOptions={{ headerShown: false }} />
          </ThemeProvider>
        </QueryClientProvider>
      </SafeAreaProvider>
    </GestureHandlerRootView>
  )
}
```

---

## Testing Requirements

### Test Pyramid for Mobile

- **Unit tests (60%)**: Business logic, hooks, utilities, stores — Jest + React Native Testing Library
- **Component tests (25%)**: Rendered components, user interactions — React Native Testing Library
- **E2E tests (15%)**: Critical user flows — Maestro (recommended) or Detox

### What Must Be Tested

- [ ] Authentication flow (login, register, biometric, token refresh)
- [ ] Offline behavior (data persistence, queue-and-retry, sync)
- [ ] Push notification handling (foreground, background, tap-to-open)
- [ ] Deep link routing (all registered routes resolve correctly)
- [ ] Navigation flows (tab switching, stack push/pop, modal presentation)
- [ ] Form validation and submission
- [ ] List rendering performance (no dropped frames with 1000+ items)
- [ ] Platform-specific behavior (iOS vs Android differences)

---

## Integration with Other Enterprise Skills

- **enterprise-backend**: Mobile app consumes APIs defined by the backend skill. Use TanStack Query for data fetching, Zod for response validation.
- **enterprise-frontend**: Shared design system tokens (colors, spacing, typography) where web and mobile coexist.
- **enterprise-deployment**: EAS Build/Submit integrates with CI/CD pipelines. Use EAS Update for OTA deployments.
- **enterprise-testing**: Mobile E2E testing (Maestro/Detox) complements the testing skill's patterns.
- **enterprise-security**: Certificate pinning, secure storage, and biometric patterns align with centralized security policies.

---

## Verification Checklist

Before considering any mobile work complete, verify:

- [ ] Expo SDK version is current (or explicitly pinned with reason)
- [ ] Hermes engine enabled and verified (`global.HermesInternal` check)
- [ ] All sensitive data in SecureStore, never AsyncStorage
- [ ] Certificate pinning configured for production API endpoints
- [ ] Deep links tested on both iOS and Android (physical devices)
- [ ] Push notifications tested: foreground, background, killed state
- [ ] Offline mode tested: airplane mode, slow network, network recovery
- [ ] FlatList/FlashList used for all dynamic lists (no ScrollView + map)
- [ ] Images optimized (expo-image, webp, correct resolution)
- [ ] App icons and splash screen configured for all densities
- [ ] EAS Build succeeds for both iOS and Android
- [ ] Bundle size < 5MB JS compressed
- [ ] No console.log statements in production build
- [ ] Accessibility: VoiceOver/TalkBack tested on critical flows
- [ ] SafeAreaView used on all screens
