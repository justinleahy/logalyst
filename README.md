# Health Logger

An iPhone + Apple Watch app for manually logging health data that Apple Watch doesn't capture, written straight into Apple Health (HealthKit).

## What you can log

| Category | Metrics |
| --- | --- |
| Vitals | Blood pressure, blood glucose (with before/after meal), body temperature |
| Body | Weight, body fat %, lean body mass, waist circumference |
| Intake | Water, caffeine, alcoholic drinks, calories, protein, carbs, fat, sugar, fiber |
| Symptoms & events | 18 symptoms with severity (and optional duration), inhaler use, toothbrushing (duration) |

- **Favorites:** swipe right on a metric (or touch and hold it on iPhone) to star it and pin it to the top of the
  Log list. Favorites sync between iPhone and Watch; if both change at once, the latest edit wins.
- Units follow your Health app preferences (e.g. lb vs kg, mg/dL vs mmol/L) unless you pick one in the
  **Options** tab, and you can switch per entry.
- Measurements like weight and blood pressure are prefilled with your last reading.
- **Nutrition** tab tracks today's water against a daily goal (with a progress ring and a
  list of today's water to fix mistakes), shows calories, macros, sugar, fiber and caffeine against daily
  targets or limits, and charts any intake metric over the last 7 days. Totals include data other apps
  save to Health. Tap the target button to edit goals.
- **Foods:** save foods with their nutrition per serving (My Foods), then log them by the serving. Each one is
  saved to Health as a single food entry, so Health shows it by name and History lists it once. Scan a
  barcode to jump straight to a saved food, or to fill in a new one from
  [Open Food Facts](https://world.openfoodfacts.org), a free, open food database. You can also type the number
  if the camera can't read it. Saved foods live on the iPhone only.
- **History** tab lists everything logged from either device; swipe to delete.
- **Widgets** (iPhone Home Screen, Lock Screen and Control Center):
  - *Water*: today's water against your goal, with buttons that log a glass without opening the app.
  - *Nutrition*: calories and nutrients against your daily goals. On the Lock Screen it shows a calorie gauge,
    or calories with protein, carbs and fat.
  - *Quick Log*: your favorites (or a few common metrics until you star some); tap one to open its entry screen.
  - *Metric*: pick any metric to see its latest reading, or today's total for intake.
  - *Log Water* and *Log Metric* controls for Control Center and the buttons at the bottom of the Lock Screen.
    Log Metric opens the entry screen for the metric you pick.
- The app handles `healthlogger://log/<metric ID>` and `healthlogger://nutrition` links, which the widgets and
  controls use.
- **Complications** on Apple Watch: the Metric widget, showing a metric's latest reading or today's total.
  Tapping it opens that metric's entry screen. Goals are set on the iPhone, so the Watch shows totals without
  progress.
- Widgets read Health directly. While the phone is locked, Health can't be read, so they show the last values
  they read (daily totals reset at midnight). Logging from a widget asks you to unlock first.
- Every sample is tagged `HKMetadataKeyWasUserEntered`, so Health shows it as manually entered.

## Running it

1. Open `HealthLogger.xcodeproj` in Xcode.
2. For **all four** targets (`HealthLogger`, `HealthLoggerWatch`, `HealthLoggerWidgets` and
   `HealthLoggerWatchWidgets`), open *Signing & Capabilities* and pick your Team.
   If Xcode says the bundle ID is taken, change the `com.justinleahy` prefix on every target (the Watch target's
   `WKCompanionAppBundleIdentifier` build setting must match the iPhone app's bundle ID, and each widget
   extension's ID must start with its app's ID). The apps and widgets share settings through the
   `group.com.justinleahy.HealthLogger` app group; if you rename it, update `AppGroup.id` in
   `Shared/AppGroup.swift` and the four entitlements files in `Config/`.
3. Select the `HealthLogger` scheme and your iPhone, then Run. The Watch app installs through the Watch app on
   your iPhone (or run the `HealthLoggerWatch` scheme directly on your watch).
4. Approve the Health permission sheet on first launch (on each device).

## Adding a metric

Everything is driven by the catalog in `Shared/Metric.swift`. Add a `Metric` entry with its HealthKit
identifier and unit options (plus an optional `dailyGoal` for intake metrics), and it will appear in the log list, permission request and history on both devices.

## Layout

```
HealthLogger/        iPhone app (Log, Entry, Nutrition, History, Options screens)
HealthLoggerWatch/   Watch app (Favorites, Digital Crown entry)
HealthLoggerWidgets/ iPhone widget extension (Water, Nutrition, Quick Log, Log Water control)
HealthLoggerWatchWidgets/  Watch widget extension (complications)
Widgets/             Metric widget and widget helpers, compiled into both widget extensions
Shared/              Metric catalog, HealthStore (HealthKit read/write), NutritionGoals, DeviceSync
                     (Watch ↔ iPhone) and app group settings, compiled into every target
Config/              Entitlements and the widget extensions' Info.plists
```
