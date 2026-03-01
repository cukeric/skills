# Native Module Integration Reference

## When You Need Native Modules

| Scenario | Approach | Complexity |
|---|---|---|
| Using existing native SDK | **Expo Config Plugin** | Low |
| Custom native functionality | **Expo Modules API** | Medium |
| Performance-critical bridge | **Turbo Modules** | High |
| Custom native UI component | **Fabric Components** | High |
| Integrating native library | **Config Plugin + wrapper** | Medium |

---

## Expo Modules API (Recommended)

The Expo Modules API is the modern way to write native modules that work with Expo and React Native.

### Setup

```bash
# Create a new local Expo module
npx create-expo-module@latest --local my-native-module

# This creates:
# modules/my-native-module/
# ├── android/
# │   └── src/main/java/.../MyNativeModule.kt
# ├── ios/
# │   └── MyNativeModule.swift
# ├── src/
# │   └── index.ts          # JS interface
# └── expo-module.config.json
```

### Example: Native Device Info Module

**TypeScript Interface:**

```typescript
// modules/device-info/src/index.ts
import DeviceInfoModule from './DeviceInfoModule'

export function getDeviceName(): string {
  return DeviceInfoModule.getDeviceName()
}

export function getBatteryLevel(): Promise<number> {
  return DeviceInfoModule.getBatteryLevel()
}

export function getStorageInfo(): Promise<{ total: number; free: number }> {
  return DeviceInfoModule.getStorageInfo()
}

export { default as DeviceInfoView } from './DeviceInfoView'
```

**iOS Implementation (Swift):**

```swift
// modules/device-info/ios/DeviceInfoModule.swift
import ExpoModulesCore
import UIKit

public class DeviceInfoModule: Module {
  public func definition() -> ModuleDefinition {
    Name("DeviceInfo")

    Function("getDeviceName") { () -> String in
      return UIDevice.current.name
    }

    AsyncFunction("getBatteryLevel") { () -> Double in
      UIDevice.current.isBatteryMonitoringEnabled = true
      return Double(UIDevice.current.batteryLevel)
    }

    AsyncFunction("getStorageInfo") { () -> [String: Int64] in
      let fileManager = FileManager.default
      do {
        let attrs = try fileManager.attributesOfFileSystem(
          forPath: NSHomeDirectory()
        )
        let total = attrs[.systemSize] as? Int64 ?? 0
        let free = attrs[.systemFreeSize] as? Int64 ?? 0
        return ["total": total, "free": free]
      } catch {
        return ["total": 0, "free": 0]
      }
    }

    Events("onBatteryChange")

    OnStartObserving {
      UIDevice.current.isBatteryMonitoringEnabled = true
      NotificationCenter.default.addObserver(
        self,
        selector: #selector(batteryLevelDidChange),
        name: UIDevice.batteryLevelDidChangeNotification,
        object: nil
      )
    }

    OnStopObserving {
      NotificationCenter.default.removeObserver(self)
    }
  }

  @objc private func batteryLevelDidChange() {
    sendEvent("onBatteryChange", [
      "level": UIDevice.current.batteryLevel
    ])
  }
}
```

**Android Implementation (Kotlin):**

```kotlin
// modules/device-info/android/src/main/java/.../DeviceInfoModule.kt
package com.company.deviceinfo

import android.os.BatteryManager
import android.os.Environment
import android.os.StatFs
import expo.modules.kotlin.modules.Module
import expo.modules.kotlin.modules.ModuleDefinition

class DeviceInfoModule : Module() {
  override fun definition() = ModuleDefinition {
    Name("DeviceInfo")

    Function("getDeviceName") {
      android.os.Build.MODEL
    }

    AsyncFunction("getBatteryLevel") {
      val batteryManager = appContext.reactContext
        ?.getSystemService(android.content.Context.BATTERY_SERVICE) as? BatteryManager
      val level = batteryManager?.getIntProperty(
        BatteryManager.BATTERY_PROPERTY_CAPACITY
      ) ?: -1
      level.toDouble() / 100.0
    }

    AsyncFunction("getStorageInfo") {
      val stat = StatFs(Environment.getDataDirectory().path)
      mapOf(
        "total" to stat.blockSizeLong * stat.blockCountLong,
        "free" to stat.blockSizeLong * stat.availableBlocksLong
      )
    }

    Events("onBatteryChange")
  }
}
```

---

## Config Plugins (Modify Native Projects)

Config plugins modify native iOS/Android project files at build time without ejecting.

### Common Config Plugin Patterns

```typescript
// plugins/withAndroidPermissions.ts
import { ConfigPlugin, withAndroidManifest } from 'expo/config-plugins'

const withBluetoothPermissions: ConfigPlugin = (config) => {
  return withAndroidManifest(config, (config) => {
    const manifest = config.modResults.manifest

    // Add Bluetooth permissions
    const permissions = manifest['uses-permission'] || []
    permissions.push(
      { $: { 'android:name': 'android.permission.BLUETOOTH' } },
      { $: { 'android:name': 'android.permission.BLUETOOTH_ADMIN' } },
      { $: { 'android:name': 'android.permission.BLUETOOTH_CONNECT' } }
    )
    manifest['uses-permission'] = permissions

    return config
  })
}

export default withBluetoothPermissions
```

```typescript
// plugins/withIOSEntitlements.ts
import { ConfigPlugin, withEntitlementsPlist } from 'expo/config-plugins'

const withAppGroups: ConfigPlugin<string[]> = (config, groupIds) => {
  return withEntitlementsPlist(config, (config) => {
    config.modResults['com.apple.security.application-groups'] = groupIds
    return config
  })
}

export default withAppGroups

// Usage in app.config.ts
plugins: [
  ['./plugins/withAppGroups', ['group.com.company.myapp']],
]
```

### Adding CocoaPods Dependencies

```typescript
// plugins/withCocoaPods.ts
import { ConfigPlugin, withPodfile } from 'expo/config-plugins'

const withFirebaseAnalytics: ConfigPlugin = (config) => {
  return withPodfile(config, (config) => {
    const podfile = config.modResults

    // Add pod to Podfile
    if (!podfile.contents.includes("pod 'FirebaseAnalytics'")) {
      podfile.contents = podfile.contents.replace(
        /use_expo_modules!/,
        `use_expo_modules!\n  pod 'FirebaseAnalytics'`
      )
    }

    return config
  })
}

export default withFirebaseAnalytics
```

### Adding Gradle Dependencies

```typescript
// plugins/withGradleDependency.ts
import { ConfigPlugin, withAppBuildGradle } from 'expo/config-plugins'

const withMapboxSDK: ConfigPlugin = (config) => {
  return withAppBuildGradle(config, (config) => {
    if (!config.modResults.contents.includes('mapbox-maps-android')) {
      config.modResults.contents = config.modResults.contents.replace(
        /dependencies\s*\{/,
        `dependencies {\n    implementation 'com.mapbox.maps:android:11.0.0'`
      )
    }
    return config
  })
}

export default withMapboxSDK
```

---

## Turbo Modules (Advanced)

Turbo Modules are the new architecture for React Native's native module system — synchronous, lazy-loaded, and type-safe via codegen.

### When to Use Turbo Modules

- Hot-path native calls that need synchronous results
- Performance-critical modules called hundreds of times per second
- You need the new architecture's JSI (JavaScript Interface) bridge

### Key Differences from Expo Modules API

| Feature | Expo Modules API | Turbo Modules |
|---|---|---|
| Setup complexity | Low (built-in tooling) | High (codegen, manual setup) |
| Swift/Kotlin support | Native | Limited (Obj-C++, Java primary) |
| Expo compatibility | Full | Requires New Architecture |
| Synchronous calls | Yes (via JSI) | Yes (via JSI) |
| Type safety | Runtime | Codegen (compile-time) |

**Recommendation:** Use Expo Modules API for most cases. Only drop to Turbo Modules for extreme performance needs or when you need fine-grained control.

---

## Fabric Components (Native Views)

### Creating a Custom Native View

```typescript
// modules/my-chart/src/MyChartView.tsx
import { requireNativeViewManager } from 'expo-modules-core'
import { ViewProps } from 'react-native'

interface MyChartViewProps extends ViewProps {
  data: number[]
  color?: string
  lineWidth?: number
  animated?: boolean
  onDataPointPress?: (event: { index: number; value: number }) => void
}

const NativeView = requireNativeViewManager('MyChart')

export function MyChartView(props: MyChartViewProps) {
  return <NativeView {...props} />
}
```

**iOS Native View (Swift):**

```swift
// modules/my-chart/ios/MyChartView.swift
import ExpoModulesCore
import UIKit

class MyChartView: ExpoView {
  private let chartLayer = CAShapeLayer()
  private var data: [Double] = []

  required init(appContext: AppContext? = nil) {
    super.init(appContext: appContext)
    layer.addSublayer(chartLayer)
  }

  func setData(_ values: [Double]) {
    self.data = values
    drawChart()
  }

  func setColor(_ hex: String) {
    chartLayer.strokeColor = UIColor(hex: hex).cgColor
  }

  private func drawChart() {
    // Draw chart using Core Graphics
    let path = UIBezierPath()
    // ... drawing logic
    chartLayer.path = path.cgPath
  }
}
```

---

## Bridging Third-Party SDKs

### Pattern: Wrapping a Native SDK

```
1. Create Expo module (npx create-expo-module --local)
2. Add SDK dependency via config plugin (CocoaPods / Gradle)
3. Write Swift/Kotlin wrapper in module
4. Expose JS interface via TypeScript
5. Test with development build (NOT Expo Go)
```

### Example: Analytics SDK Wrapper

```typescript
// modules/analytics/src/index.ts
import AnalyticsModule from './AnalyticsModule'

export function initialize(apiKey: string): void {
  AnalyticsModule.initialize(apiKey)
}

export function trackEvent(name: string, properties?: Record<string, unknown>): void {
  AnalyticsModule.trackEvent(name, properties || {})
}

export function identifyUser(userId: string, traits?: Record<string, unknown>): void {
  AnalyticsModule.identifyUser(userId, traits || {})
}

export function resetUser(): void {
  AnalyticsModule.resetUser()
}
```

---

## Development Builds

When using native modules, you must use development builds instead of Expo Go.

```bash
# Create development build
eas build --profile development --platform ios
eas build --profile development --platform android

# Or build locally
npx expo run:ios
npx expo run:android

# Start dev server and connect
npx expo start --dev-client
```

---

## Native Module Checklist

- [ ] Using Expo Modules API (unless Turbo Module performance is needed)
- [ ] Both iOS (Swift) and Android (Kotlin) implementations provided
- [ ] TypeScript interface with proper types exported
- [ ] Config plugin created for native dependencies
- [ ] Development build tested (native modules don't work in Expo Go)
- [ ] Module errors handled gracefully (try/catch, platform checks)
- [ ] Event listeners cleaned up on unmount
- [ ] Memory management: no retain cycles (iOS) or context leaks (Android)
- [ ] Module works on both platforms or platform-specific fallback provided
- [ ] Unit tests for JS interface, integration tests for native code
