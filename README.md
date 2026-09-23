# Health Logger

An iPhone + Apple Watch app for manually logging health data that Apple Watch doesn't capture, written straight into Apple Health (HealthKit).

## What you can log

| Category | Metrics |
| --- | --- |
| Vitals | Blood pressure, blood glucose (with before/after meal), body temperature |
| Body | Weight, body fat %, lean body mass, waist circumference |
| Intake | Water, caffeine, alcoholic drinks, calories, protein, carbs, fat, sugar, fiber |
| Symptoms & events | 18 symptoms with severity (and optional duration), inhaler use |

- **Quick Add** buttons for one-tap water, caffeine, drinks and inhaler puffs (iPhone and Watch).
- Units follow your Health app preferences (e.g. lb vs kg, mg/dL vs mmol/L), and you can switch per entry.
- Measurements like weight and blood pressure are prefilled with your last reading.
- **History** tab lists everything logged from either device; swipe to delete.
- Every sample is tagged `HKMetadataKeyWasUserEntered`, so Health shows it as manually entered.

## Running it

1. Open `HealthLogger.xcodeproj` in Xcode.
2. For **both** targets (`HealthLogger` and `HealthLoggerWatch`), open *Signing & Capabilities* and pick your Team.
   If Xcode says the bundle ID is taken, change the `com.justinleahy` prefix on both targets (the Watch target's
   `WKCompanionAppBundleIdentifier` build setting must match the iPhone app's bundle ID).
3. Select the `HealthLogger` scheme and your iPhone, then Run. The Watch app installs through the Watch app on
   your iPhone (or run the `HealthLoggerWatch` scheme directly on your watch).
4. Approve the Health permission sheet on first launch (on each device).

## Adding a metric

Everything is driven by the catalog in `Shared/Metric.swift`. Add a `Metric` entry with its HealthKit
identifier and unit options, and it will appear in the log list, permission request and history on both devices.

## Layout

```
HealthLogger/        iPhone app (Log, Entry, History screens)
HealthLoggerWatch/   Watch app (Quick Add, Digital Crown entry)
Shared/              Metric catalog + HealthStore (HealthKit read/write), compiled into both apps
Config/              Entitlements
```
