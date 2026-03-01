# React Native & Expo Reference

## Expo Project Setup

### Creating a New Expo Project

```bash
# Create new Expo project with TypeScript
npx -y create-expo-app@latest my-app --template tabs

# Or minimal template
npx -y create-expo-app@latest my-app --template blank-typescript

cd my-app

# Install essential dependencies
npx expo install expo-router expo-linking expo-constants expo-status-bar
npx expo install react-native-safe-area-context react-native-screens
npx expo install react-native-gesture-handler react-native-reanimated
npx expo install expo-image expo-secure-store expo-haptics
npx expo install @react-native-async-storage/async-storage

# State & data fetching
npm install zustand @tanstack/react-query zod
npm install react-hook-form @hookform/resolvers

# Development
npm install -D @types/react @types/react-native
```

### app.config.ts (Dynamic Configuration)

```typescript
import { ExpoConfig, ConfigContext } from 'expo/config'

export default ({ config }: ConfigContext): ExpoConfig => ({
  ...config,
  name: process.env.APP_NAME || 'MyApp',
  slug: 'my-app',
  version: '1.0.0',
  orientation: 'portrait',
  icon: './assets/icon.png',
  scheme: 'myapp', // Deep linking scheme
  userInterfaceStyle: 'automatic', // Light/dark mode
  splash: {
    image: './assets/splash.png',
    resizeMode: 'contain',
    backgroundColor: '#0A0A0F',
  },
  assetBundlePatterns: ['**/*'],
  ios: {
    supportsTablet: true,
    bundleIdentifier: 'com.company.myapp',
    buildNumber: '1',
    infoPlist: {
      NSCameraUsageDescription: 'Used to scan documents',
      NSPhotoLibraryUsageDescription: 'Used to upload photos',
      NSFaceIDUsageDescription: 'Used for secure authentication',
    },
    config: {
      usesNonExemptEncryption: false,
    },
    associatedDomains: ['applinks:app.company.com'], // Universal links
  },
  android: {
    adaptiveIcon: {
      foregroundImage: './assets/adaptive-icon.png',
      backgroundColor: '#0A0A0F',
    },
    package: 'com.company.myapp',
    versionCode: 1,
    permissions: ['CAMERA', 'READ_EXTERNAL_STORAGE'],
    intentFilters: [
      {
        action: 'VIEW',
        autoVerify: true,
        data: [{ scheme: 'https', host: 'app.company.com', pathPrefix: '/' }],
        category: ['BROWSABLE', 'DEFAULT'],
      },
    ],
  },
  plugins: [
    'expo-router',
    'expo-secure-store',
    'expo-local-authentication',
    [
      'expo-notifications',
      {
        icon: './assets/notification-icon.png',
        color: '#6366F1',
        sounds: ['./assets/notification-sound.wav'],
      },
    ],
    [
      'expo-image-picker',
      { photosPermission: 'Allow access to select photos' },
    ],
  ],
  experiments: {
    typedRoutes: true, // Type-safe route parameters
  },
  extra: {
    eas: { projectId: process.env.EAS_PROJECT_ID },
    apiUrl: process.env.API_URL || 'http://localhost:3000',
  },
})
```

---

## Expo Router (File-Based Routing)

### Route File Conventions

| File | Route | Type |
|---|---|---|
| `app/index.tsx` | `/` | Screen |
| `app/settings.tsx` | `/settings` | Screen |
| `app/users/[id].tsx` | `/users/123` | Dynamic segment |
| `app/[...catch].tsx` | Any unmatched route | Catch-all |
| `app/(tabs)/_layout.tsx` | Tab navigator | Layout |
| `app/(auth)/_layout.tsx` | Auth stack | Layout (group) |
| `app/+not-found.tsx` | 404 handler | Error boundary |
| `app/_layout.tsx` | Root layout | Root |

### Tab Layout

```typescript
// app/(tabs)/_layout.tsx
import { Tabs } from 'expo-router'
import { Ionicons } from '@expo/vector-icons'
import { useTheme } from '@/lib/theme'

export default function TabLayout() {
  const { colors } = useTheme()

  return (
    <Tabs
      screenOptions={{
        tabBarActiveTintColor: colors.primary,
        tabBarInactiveTintColor: colors.textMuted,
        tabBarStyle: {
          backgroundColor: colors.surface,
          borderTopColor: colors.border,
          paddingBottom: 4,
          height: 56,
        },
        headerStyle: { backgroundColor: colors.surface },
        headerTintColor: colors.text,
      }}
    >
      <Tabs.Screen
        name="index"
        options={{
          title: 'Home',
          tabBarIcon: ({ color, size }) => (
            <Ionicons name="home-outline" size={size} color={color} />
          ),
        }}
      />
      <Tabs.Screen
        name="search"
        options={{
          title: 'Search',
          tabBarIcon: ({ color, size }) => (
            <Ionicons name="search-outline" size={size} color={color} />
          ),
        }}
      />
      <Tabs.Screen
        name="profile"
        options={{
          title: 'Profile',
          tabBarIcon: ({ color, size }) => (
            <Ionicons name="person-outline" size={size} color={color} />
          ),
        }}
      />
    </Tabs>
  )
}
```

### Protected Routes Pattern

```typescript
// app/_layout.tsx
import { Slot, useRouter, useSegments } from 'expo-router'
import { useEffect } from 'react'
import { useAuth } from '@/hooks/useAuth'

function AuthGuard({ children }: { children: React.ReactNode }) {
  const { isAuthenticated, isLoading } = useAuth()
  const segments = useSegments()
  const router = useRouter()

  useEffect(() => {
    if (isLoading) return

    const inAuthGroup = segments[0] === '(auth)'

    if (!isAuthenticated && !inAuthGroup) {
      router.replace('/(auth)/login')
    } else if (isAuthenticated && inAuthGroup) {
      router.replace('/(tabs)')
    }
  }, [isAuthenticated, isLoading, segments])

  if (isLoading) return <LoadingScreen />
  return <>{children}</>
}

export default function RootLayout() {
  return (
    <Providers>
      <AuthGuard>
        <Slot />
      </AuthGuard>
    </Providers>
  )
}
```

### Typed Navigation

```typescript
// Type-safe navigation with Expo Router
import { Link, useRouter } from 'expo-router'

// Declarative navigation
<Link href="/users/123">View User</Link>
<Link href={{ pathname: '/users/[id]', params: { id: user.id } }}>
  View User
</Link>

// Imperative navigation
const router = useRouter()
router.push('/settings')
router.push({ pathname: '/users/[id]', params: { id: '123' } })
router.replace('/(tabs)')  // Replace current screen
router.back()              // Go back
```

---

## EAS Build & Development Builds

### eas.json Configuration

```json
{
  "cli": { "version": ">= 10.0.0" },
  "build": {
    "development": {
      "developmentClient": true,
      "distribution": "internal",
      "ios": {
        "simulator": true
      },
      "env": {
        "API_URL": "http://localhost:3000",
        "APP_NAME": "MyApp Dev"
      }
    },
    "preview": {
      "distribution": "internal",
      "ios": {
        "simulator": false
      },
      "env": {
        "API_URL": "https://staging-api.company.com",
        "APP_NAME": "MyApp Preview"
      },
      "channel": "preview"
    },
    "production": {
      "autoIncrement": true,
      "env": {
        "API_URL": "https://api.company.com",
        "APP_NAME": "MyApp"
      },
      "channel": "production"
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
# Development build (with dev menu)
eas build --profile development --platform ios
eas build --profile development --platform android

# Preview build (internal distribution)
eas build --profile preview --platform all

# Production build
eas build --profile production --platform all

# Submit to stores
eas submit --platform ios --latest
eas submit --platform android --latest
```

---

## Config Plugins (Native Customization)

Config plugins allow modifying native project files without ejecting.

```typescript
// plugins/withCustomSplash.ts
import { ConfigPlugin, withInfoPlist } from 'expo/config-plugins'

const withCustomSplash: ConfigPlugin = (config) => {
  return withInfoPlist(config, (config) => {
    config.modResults.UILaunchStoryboardName = 'CustomSplash'
    return config
  })
}

export default withCustomSplash

// Use in app.config.ts
plugins: [
  './plugins/withCustomSplash',
],
```

---

## API Client Pattern

```typescript
// src/lib/api.ts
import { secureStorage } from './secure-storage'
import Constants from 'expo-constants'

const API_URL = Constants.expoConfig?.extra?.apiUrl || 'http://localhost:3000'

class ApiClient {
  private baseUrl: string

  constructor(baseUrl: string) {
    this.baseUrl = baseUrl
  }

  private async request<T>(
    endpoint: string,
    options: RequestInit = {}
  ): Promise<T> {
    const token = await secureStorage.getAccessToken()

    const response = await fetch(`${this.baseUrl}${endpoint}`, {
      ...options,
      headers: {
        'Content-Type': 'application/json',
        ...(token ? { Authorization: `Bearer ${token}` } : {}),
        ...options.headers,
      },
    })

    if (response.status === 401) {
      const refreshed = await this.refreshToken()
      if (refreshed) return this.request<T>(endpoint, options)
      throw new ApiError(401, 'Session expired')
    }

    if (!response.ok) {
      const error = await response.json().catch(() => ({}))
      throw new ApiError(response.status, error.message || 'Request failed', error)
    }

    if (response.status === 204) return undefined as T
    return response.json()
  }

  private async refreshToken(): Promise<boolean> {
    try {
      const refreshToken = await secureStorage.getRefreshToken()
      if (!refreshToken) return false

      const response = await fetch(`${this.baseUrl}/api/v1/auth/refresh`, {
        method: 'POST',
        headers: { 'Content-Type': 'application/json' },
        body: JSON.stringify({ refreshToken }),
      })

      if (!response.ok) return false

      const { accessToken, refreshToken: newRefresh } = await response.json()
      await secureStorage.setTokens(accessToken, newRefresh)
      return true
    } catch {
      return false
    }
  }

  get<T>(endpoint: string) {
    return this.request<T>(endpoint)
  }

  post<T>(endpoint: string, body: unknown) {
    return this.request<T>(endpoint, {
      method: 'POST',
      body: JSON.stringify(body),
    })
  }

  patch<T>(endpoint: string, body: unknown) {
    return this.request<T>(endpoint, {
      method: 'PATCH',
      body: JSON.stringify(body),
    })
  }

  delete<T>(endpoint: string) {
    return this.request<T>(endpoint, { method: 'DELETE' })
  }
}

export class ApiError extends Error {
  constructor(
    public status: number,
    message: string,
    public details?: unknown
  ) {
    super(message)
    this.name = 'ApiError'
  }
}

export const api = new ApiClient(API_URL)
```

### TanStack Query Integration

```typescript
// src/hooks/useUsers.ts
import { useQuery, useMutation, useQueryClient } from '@tanstack/react-query'
import { api } from '@/lib/api'
import { z } from 'zod'

const UserSchema = z.object({
  id: z.string(),
  name: z.string(),
  email: z.string().email(),
  avatar: z.string().url().nullable(),
})

type User = z.infer<typeof UserSchema>

export function useUsers() {
  return useQuery({
    queryKey: ['users'],
    queryFn: async () => {
      const data = await api.get<{ data: User[] }>('/api/v1/users')
      return data.data.map((u) => UserSchema.parse(u))
    },
    staleTime: 5 * 60 * 1000,
  })
}

export function useUser(id: string) {
  return useQuery({
    queryKey: ['users', id],
    queryFn: () => api.get<User>(`/api/v1/users/${id}`),
    enabled: !!id,
  })
}

export function useUpdateUser() {
  const queryClient = useQueryClient()

  return useMutation({
    mutationFn: ({ id, data }: { id: string; data: Partial<User> }) =>
      api.patch<User>(`/api/v1/users/${id}`, data),
    onSuccess: (updatedUser) => {
      queryClient.setQueryData(['users', updatedUser.id], updatedUser)
      queryClient.invalidateQueries({ queryKey: ['users'] })
    },
  })
}
```

---

## Theme System

```typescript
// src/lib/theme.ts
import { createContext, useContext } from 'react'
import { useColorScheme } from 'react-native'

const lightColors = {
  primary: '#6366F1',
  primaryLight: '#818CF8',
  background: '#FFFFFF',
  surface: '#F8FAFC',
  surfaceElevated: '#FFFFFF',
  text: '#0F172A',
  textSecondary: '#64748B',
  textMuted: '#94A3B8',
  border: '#E2E8F0',
  error: '#EF4444',
  success: '#22C55E',
  warning: '#F59E0B',
}

const darkColors = {
  primary: '#818CF8',
  primaryLight: '#A5B4FC',
  background: '#0A0A0F',
  surface: '#1A1A2E',
  surfaceElevated: '#242442',
  text: '#F1F5F9',
  textSecondary: '#94A3B8',
  textMuted: '#64748B',
  border: '#2D2D4A',
  error: '#F87171',
  success: '#4ADE80',
  warning: '#FBBF24',
}

const spacing = {
  xs: 4,
  sm: 8,
  md: 16,
  lg: 24,
  xl: 32,
  xxl: 48,
}

const typography = {
  h1: { fontSize: 32, fontFamily: 'Inter-Bold', lineHeight: 40 },
  h2: { fontSize: 24, fontFamily: 'Inter-Bold', lineHeight: 32 },
  h3: { fontSize: 20, fontFamily: 'Inter-Medium', lineHeight: 28 },
  body: { fontSize: 16, fontFamily: 'Inter-Regular', lineHeight: 24 },
  bodySmall: { fontSize: 14, fontFamily: 'Inter-Regular', lineHeight: 20 },
  caption: { fontSize: 12, fontFamily: 'Inter-Regular', lineHeight: 16 },
}

const borderRadius = {
  sm: 8,
  md: 12,
  lg: 16,
  xl: 24,
  full: 9999,
}

export function useTheme() {
  const colorScheme = useColorScheme()
  const colors = colorScheme === 'dark' ? darkColors : lightColors

  return { colors, spacing, typography, borderRadius, isDark: colorScheme === 'dark' }
}
```
